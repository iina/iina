//
//  MainWindowController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Mustache
import WebKit

fileprivate let isMacOS11: Bool = {
  if #unavailable(macOS 12.0) {
      return true
  }
  return false
}()

fileprivate let InteractiveModeBottomViewHeight: CGFloat = 60

fileprivate let UIAnimationDuration = 0.25
fileprivate let OSDAnimationDuration = 0.5
fileprivate let CropAnimationDuration = 0.2

fileprivate extension NSStackView.VisibilityPriority {
  static let detachEarly = NSStackView.VisibilityPriority(rawValue: 850)
  static let detachEarlier = NSStackView.VisibilityPriority(rawValue: 800)
  static let detachEarliest = NSStackView.VisibilityPriority(rawValue: 750)
}

// The minimum distance that the user must drag before their click or tap gesture is interpreted as a drag gesture:
fileprivate let minimumInitialDragDistance: CGFloat = 3.0

fileprivate let layoutSides: [NSLayoutConstraint.Attribute] = [.top, .bottom, .leading, .trailing]

class MainWindowController: PlayerWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("MainWindowController")
  }

  @objc let monospacedFont: NSFont = {
    let fontSize = NSFont.systemFontSize(for: .small)
    return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }()

  // MARK: - Constants

  /** For Force Touch. */
  let minimumPressDuration: TimeInterval = 0.5

  // MARK: - Objects, Views

  override var videoView: VideoView {
    return _videoView
  }

  lazy private var _videoView: VideoView = VideoView(frame: window!.contentView!.bounds, player: player)

  /// Owns the sidebar panels, view controllers, and show/hide/resize logic.
  lazy var sidebars = SidebarController(mainWindow: self)

  /** The control view for interactive mode. */
  var cropSettingsView: CropBoxViewController?

  private lazy var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = {
    return NSMagnificationGestureRecognizer(target: self, action: #selector(MainWindowController.handleMagnifyGesture(recognizer:)))
  }()

  /** For auto hiding UI after a timeout. */
  var hideControlTimer: Timer?
  var hideOSDTimer: Timer?

  /** For blacking out other screens. */
  var screens: [NSScreen] = []
  var cachedScreenCount = 0
  var blackWindows: [NSWindow] = []

  lazy var rotation: Int = {
    return player.mpv.getInt(MPVProperty.videoParamsRotate)
  }()


  var titleBarView: Titlebar!
  var titleBarHeightConstraint: NSLayoutConstraint!
  var oscBottomView: OSCBottomView!
  var oscFloatingView: OSCFloatingView!

  var osdView: OSDView!
  var additionalInfoView: AdditionalInfoView!
  var bufferIndicatorView: BufferIndicatorView!
  var timePreviewView: TimePreviewView!
  var titlebarOnTopButton: NSButton!
  var thumbnailPeekView: ThumbnailPeekView!

  // MARK: - Status

  override var isOntop: Bool {
    didSet {
      titleBarView.updateOnTopIcon()
    }
  }

  /** For mpv's `geometry` option. We cache the parsed structure
   so never need to parse it every time. */
  var cachedGeometry: GeometryDef?

  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false

  var pipStatus = PIPStatus.notInPIP
  var isInInteractiveMode: Bool = false
  var isVideoLoaded: Bool = false

  var shouldApplyInitialWindowSize = true
  var isWindowHidden: Bool = false
  var isWindowMiniaturizedDueToPip = false

  // might use another obj to handle slider?
  var isMouseInWindow: Bool = false
  var isMouseInSlider: Bool = false
  /** flag to ignore abrupt momentum scrolls */
  private var isMomentumScrollingAllowed = false

  var isFastforwarding: Bool = false

  var isPausedDueToInactive: Bool = false
  var isPausedDueToMiniaturization: Bool = false
  var isPausedPriorToInteractiveMode: Bool = false

  var lastMagnification: CGFloat = 0.0
  var frameWhenStartedPinching = NSRect()

  /** Views that will show/hide when cursor moving in/out the window. */
  let fadeableViews = FadeableViewController()

  // Left and right arrow buttons

  /** The maximum pressure recorded when clicking on the arrow buttons. */
  var maxPressure: Int32 = 0

  /** The value of speedValueIndex before Force Touch. */
  var oldIndex: Int = AppData.availableSpeedValues.count / 2

  /** When the arrow buttons were last clicked. */
  var lastClick = Date()

  /** The index of current speed in speed value array. */
  var speedValueIndex: Int = AppData.availableSpeedValues.count / 2 {
    didSet {
      if speedValueIndex < 0 || speedValueIndex >= AppData.availableSpeedValues.count {
        speedValueIndex = AppData.availableSpeedValues.count / 2
      }
    }
  }

  /** For force touch action */
  var isCurrentPressInSecondStage = false

  /** Whether current osd needs user interaction to be dismissed */
  var isShowingPersistentOSD = false
  var osdContext: Any?

  /** Activated during interactive mode to prevent video view from being compressed */
  var aspectRatioConstraintForInteractiveMode: NSLayoutConstraint?

  // MARK: - Enums

  // Window state

  enum FullScreenState: Equatable {
    case windowed
    case animating(toFullscreen: Bool, legacy: Bool, priorWindowedFrame: NSRect)
    case fullscreen(legacy: Bool, priorWindowedFrame: NSRect)

    var isFullscreen: Bool {
      switch self {
      case .fullscreen: return true
      case let .animating(toFullscreen: toFullScreen, legacy: _, priorWindowedFrame: _): return toFullScreen
      default: return false
      }
    }

    var priorWindowedFrame: NSRect? {
      get {
        switch self {
        case .windowed: return nil
        case .animating(_, _, let p): return p
        case .fullscreen(_, let p): return p
        }
      }
      set {
        guard let newRect = newValue else { return }
        switch self {
        case .windowed: return
        case let .animating(toFullscreen, legacy, _):
          self = .animating(toFullscreen: toFullscreen, legacy: legacy, priorWindowedFrame: newRect)
        case let .fullscreen(legacy, _):
          self = .fullscreen(legacy: legacy, priorWindowedFrame: newRect)
        }
      }
    }

    mutating func startAnimatingToFullScreen(legacy: Bool, priorWindowedFrame: NSRect) {
      self = .animating(toFullscreen: true, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
    }

    mutating func startAnimatingToWindow() {
      guard case .fullscreen(let legacy, let priorWindowedFrame) = self else { return }
      self = .animating(toFullscreen: false, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
    }

    mutating func finishAnimating() {
      switch self {
      case .windowed, .fullscreen: assertionFailure("something went wrong with the state of the world. One must be .animating to finishAnimating. Not \(self)")
      case .animating(let toFullScreen, let legacy, let frame):
        if toFullScreen {
          self = .fullscreen(legacy: legacy, priorWindowedFrame: frame)
        } else {
          self = .windowed
        }
      }
    }
  }

  var fsState: FullScreenState = .windowed {
    didSet {
      // Must not access mpv while it is asynchronously processing stop and quit commands.
      guard player.info.state.active else { return }
      switch fsState {
      case .fullscreen: player.mpv.setFlag(MPVOption.Window.fullscreen, true)
      case .animating:  break
      case .windowed:   player.mpv.setFlag(MPVOption.Window.fullscreen, false)
      }
    }
  }

  // Animation state

  /// Animation state of he hide/show part
  enum UIAnimationState {
    case shown, hidden, willShow, willHide
  }

  var animationState: UIAnimationState = .shown
  var osdAnimationState: UIAnimationState = .hidden

  private var osdLastMessage: OSDMessage? = nil

  enum PIPStatus {
    case notInPIP
    case inPIP
    case intermediate
  }

  enum InteractiveMode {
    case crop
    case freeSelecting

    func viewController() -> CropBoxViewController {
      var vc: CropBoxViewController
      switch self {
      case .crop:
        vc = CropSettingsViewController()
      case .freeSelecting:
        vc = FreeSelectingViewController()
      }
      return vc
    }
  }

  // MARK: - Observed user defaults

  private var oscIsInitialized = false

  // Cached user default values
  private lazy var oscPosition: Preference.OSCPosition = Preference.enum(for: .oscPosition)
  private lazy var arrowBtnFunction: Preference.ArrowButtonAction = Preference.enum(for: .arrowButtonAction)
  private lazy var pinchAction: Preference.PinchAction = Preference.enum(for: .pinchAction)
  lazy var displayTimeAndBatteryInFullScreen: Bool = Preference.bool(for: .displayTimeAndBatteryInFullScreen)

  private let localObservedPrefKeys: [Preference.Key] = [
    .oscPosition,
    .showChapterPos,
    .arrowButtonAction,
    .pinchAction,
    .blackOutMonitor,
    .useLegacyFullScreen,
    .displayTimeAndBatteryInFullScreen,
    .controlBarToolbarButtons,
    .alwaysShowOnTopIcon,
    .unlockWindowAspectRatio,
    .edgeToEdgeVideo,
    .compactUI,
    .dockedControlBarAndTitlebar,
    .useLiquidGlassOSC,
    .useLiquidGlassOSD,
    .useLiquidGlassSidebar,
  ]

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }
    super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)

    switch keyPath {
    case PK.oscPosition.rawValue:
      if let newValue = change[.newKey] as? Int {
        setupOnScreenController(withPosition: Preference.OSCPosition(rawValue: newValue) ?? .floating)
      }
    case PK.showChapterPos.rawValue:
      if let newValue = change[.newKey] as? Bool {
        (playSlider.cell as! PlaySliderCell).drawChapters = newValue
      }
    case PK.verticalScrollAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case PK.horizontalScrollAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }
    case PK.arrowButtonAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        arrowBtnFunction = Preference.ArrowButtonAction(rawValue: newValue)!
        updateArrowButtons()
      }
    case PK.pinchAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        pinchAction = Preference.PinchAction(rawValue: newValue)!
      }
    case PK.blackOutMonitor.rawValue:
      if let newValue = change[.newKey] as? Bool {
        if fsState.isFullscreen {
          newValue ? blackOutOtherMonitors() : removeBlackWindow()
        }
      }
    case PK.useLegacyFullScreen.rawValue:
      resetCollectionBehavior()
    case PK.displayTimeAndBatteryInFullScreen.rawValue:
      if let newValue = change[.newKey] as? Bool {
        displayTimeAndBatteryInFullScreen = newValue
        if !newValue {
          additionalInfoView.isHidden = true
        }
        fadeableViews.update()
      }
    case PK.controlBarToolbarButtons.rawValue:
      if let newValue = change[.newKey] as? [Int] {
        setupOSCToolbarButtons(newValue.compactMap(Preference.ToolBarButton.init(rawValue:)))
      }
    case PK.alwaysShowOnTopIcon.rawValue:
      titleBarView.updateOnTopIcon()
    case PK.dockedControlBarAndTitlebar.rawValue:
      setupVideoViewConstraints()
      fadeableViews.update()
    case PK.edgeToEdgeVideo.rawValue:
      setupVideoViewConstraints()
      fallthrough
    case PK.unlockWindowAspectRatio.rawValue:
      fadeableViews.update()
      titleBarView.updateRemoveBlackBarButton()
      handleVideoSizeChange(keepWindowSize: true)
    case PK.compactUI.rawValue:
      setWindowToolbar()
    case PK.useLiquidGlassOSD.rawValue:
      [timePreviewView, osdView, additionalInfoView, bufferIndicatorView].forEach {
        $0?.setStyle(Preference.liquidGlass(.osd) ? .liquidGlass : .visualEffect)
      }
    default:
      return
    }
  }

  // MARK: - Outlets

  var standardWindowButtons: [NSButton] {
    get {
      return ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindow.ButtonType]).compactMap {
        window?.standardWindowButton($0)
      }
    }
  }

  /** Get the `NSTextField` of widow's title. */
  var titleTextField: NSTextField? {
    get {
      return window?.standardWindowButton(.closeButton)?.superview?.subviews.compactMap({ $0 as? NSTextField }).first
    }
  }

  /** Current OSC view. */
  var currentControlBar: NSView?

  @IBOutlet weak var bottomBarBottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var fragControlViewMiddleButtons1Constraint: NSLayoutConstraint!
  @IBOutlet weak var fragControlViewMiddleButtons2Constraint: NSLayoutConstraint!

  @IBOutlet weak var leftArrowButton: NSButton!
  @IBOutlet weak var rightArrowButton: NSButton!
  @IBOutlet weak var bottomView: NSView!

  @IBOutlet var fragControlView: NSStackView!
  @IBOutlet var fragToolbarView: NSStackView!
  @IBOutlet var fragVolumeView: NSView!
  @IBOutlet var fragSliderView: NSView!
  @IBOutlet var fragControlViewMiddleView: NSView!
  @IBOutlet var fragControlViewLeftView: NSView!
  @IBOutlet var fragControlViewRightView: NSView!

  @IBOutlet weak var leftArrowLabel: NSTextField!
  @IBOutlet weak var rightArrowLabel: NSTextField!

  @IBOutlet weak var pipOverlayView: NSVisualEffectView!

  lazy var pluginOverlayViewContainer: NSView! = {
    guard let window = window, let cv = window.contentView else { return nil }
    let view = NSView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(view, positioned: .below, relativeTo: bufferIndicatorView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": view])
    return view
  }()

  var videoViewConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]

  override var mouseActionDisabledViews: [NSView?] {
    sidebars.mouseActionDisabledViews + [currentControlBar, titleBarView]
  }

  // MARK: - PIP

  lazy var _pip: PIPViewController = {
    let pip = VideoPIPViewController()
    pip.delegate = self
    return pip
  }()

  var pip: PIPViewController {
    _pip
  }

  var pipVideo: NSViewController!

  // MARK: - Initialization

  override func windowDidLoad() {
    super.windowDidLoad()
    MemoryUsage.shared.logUsage("after window loaded")

    guard let window, let cv = window.contentView else { return }

    window.styleMask.insert(.fullSizeContentView)

    // need to deal with control bar, so we handle it manually
    // w.isMovableByWindowBackground  = true

    // set background color to black
    window.backgroundColor = window.effectiveAppearance.isDark ? .black : .white

    // size
    window.minSize = AppData.mainWindowMinSize
    if let wf = windowFrameFromGeometry() {
      window.setFrame(wf, display: false)
    }

    window.aspectRatio = AppData.sizeWhenNoVideo
    setWindowToolbar()
    cv.autoresizesSubviews = false

    // gesture recognizer
    cv.addGestureRecognizer(magnificationGestureRecognizer)

    // Work around a bug in macOS Ventura where HDR content becomes dimmed when playing in full
    // screen mode once overlaying views are fully hidden (issue #3844). After applying this
    // workaround another bug in Ventura where an external monitor goes black could not be
    // reproduced (issue #4015). The workaround adds a tiny subview with such a low alpha level it
    // is invisible to the human eye. This workaround may not be effective in all cases.
    if #available(macOS 13, *), Preference.bool(for: .enableHdrWorkaround) {
      let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 0.1, height: 0.1)))
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.black.cgColor
      view.layer?.opacity = 0.01
      cv.addSubview(view)
    }

    // init quick setting view now
    let _ = sidebars.quickSettingView

    // create translucent views
    oscBottomView = OSCBottomView(mainWindow: self)
    cv.addSubview(oscBottomView)
    oscFloatingView = OSCFloatingView(mainWindow: self)
    cv.addSubview(oscFloatingView)
    osdView = OSDView(mainWindow: self)
    cv.addSubview(osdView)
    additionalInfoView = AdditionalInfoView(mainWindow: self)
    cv.addSubview(additionalInfoView)
    bufferIndicatorView = BufferIndicatorView(mainWindow: self)
    cv.addSubview(bufferIndicatorView)
    titleBarView = Titlebar(mainWindow: self)
    cv.addSubview(titleBarView)
    sidebars.installSubviews(in: cv)

    // thumbnail peek view
    thumbnailPeekView = ThumbnailPeekView()
    cv.addSubview(thumbnailPeekView)
    self.timePreviewView = TimePreviewView(mainWindow: self)
    cv.addSubview(timePreviewView)
    thumbnailPeekView.isHidden = true
    timePreviewView.isHidden = true
    timePreviewView.textField.font = monospacedFont

    // osc bottom

    oscBottomView.padding(.horizontal)

    // osd

    osdView.padding(.trailing(greaterThan: 8), .bottom(greaterThan: 8))
      .spacing(.top(8), to: titleBarView)
      .spacing(.leading(8), to: sidebars.leadingSidebar.view)

    // additional info view

    additionalInfoView.padding(.leading(greaterThan: 8), .bottom(greaterThan: 8))
      .spacing(.top(8), to: titleBarView)
      .spacing(.trailing(8), to: sidebars.trailingSidebar.view)
    additionalInfoView.isHidden = true

    // buffer indicator view

    bufferIndicatorView.center()
    bufferIndicatorView.update()

    [timePreviewView, osdView, additionalInfoView, bufferIndicatorView].forEach {
      $0?.setStyle(Preference.liquidGlass(.osd) ? .liquidGlass : .visualEffect)
    }

    // titlebar

    titleBarView.padding(.horizontal)

    // osc views

    fragControlView.addView(fragControlViewLeftView, in: .center)
    fragControlView.addView(fragControlViewMiddleView, in: .center)
    fragControlView.addView(fragControlViewRightView, in: .center)
    // Video controllers and timeline indicators should not flip in a right-to-left language.
    fragControlView.userInterfaceLayoutDirection = .leftToRight
    setupOnScreenController(withPosition: oscPosition)
    let buttons = (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    setupOSCToolbarButtons(buttons)

    updateArrowButtons()

    // video view
    addVideoViewToWindow()
    player.initVideo()
    videoView.postsFrameChangedNotifications = true

    // fade-able views

    standardWindowButtons.forEach {
      fadeableViews.add($0) { [unowned self] in
        fsState == .windowed && !Preference.isDocked ? .auto : .alwaysShown
      }
    }

    fadeableViews.add(titleBarView) { [unowned self] in
      if fsState == .windowed {
        Preference.isDocked ? .alwaysShown : .auto
      } else { // full screen
        oscPosition == .top ? .auto : .alwaysHidden
      }
    }

    fadeableViews.add(additionalInfoView) { [unowned self] in
      if fsState == .windowed {
        .alwaysHidden
      } else {
        Preference.bool(for: .displayTimeAndBatteryInFullScreen) ? .auto : .alwaysHidden
      }
    }

    fadeableViews.add(oscBottomView) { [unowned self] in
      if oscPosition == .bottom {
        Preference.isDocked ? .alwaysShown : .auto
      } else {
        .alwaysHidden
      }
    }

    fadeableViews.add(oscFloatingView) { [unowned self] in
      oscPosition == .floating ? .auto : .alwaysHidden
    }

    fadeableViews.update()

    // other initialization
    cachedScreenCount = NSScreen.screens.count
    [pipOverlayView].forEach {
      $0?.state = .active
    }
    // hide other views
    osdView.isHidden = true
    leftArrowLabel.isHidden = true
    rightArrowLabel.isHidden = true
    bottomView.isHidden = true
    pipOverlayView.isHidden = true

    if player.disableUI { hideUI() }

    // add user default observers
    observedPrefKeys.append(contentsOf: localObservedPrefKeys)
    localObservedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    // add notification observers

    addObserver(to: .default, forName: NSView.frameDidChangeNotification, object: videoView) { [unowned self] _ in
      if case .animating(_, _, _) = fsState {
        forceDraw("window resized during animated enter or exit full screen")
      } else if !videoView.videoLayer.inLiveResize {
        forceDraw("window resized")
      } else if Preference.unlockWindowAspectRatio && videoView.isIdle {
        forceDraw("window resized with aspect ratio unlocked and paused")
      }
    }

    addObserver(to: .default, forName: .iinaFileLoaded, object: player) { [unowned self] _ in
      self.sidebars.quickSettingView.reload()
    }

    addObserver(to: .default, forName: NSApplication.didChangeScreenParametersNotification) { [unowned self] _ in
      // This observer handles a situation that the user connected a new screen or removed a screen
      let screenCount = NSScreen.screens.count
      let countChanged = cachedScreenCount != screenCount
      if fsState.isFullscreen && Preference.bool(for: .blackOutMonitor) && countChanged {
        removeBlackWindow()
        blackOutOtherMonitors()
      }
      // Update the cached value
      cachedScreenCount = screenCount
      videoView.updateDisplayLink()
      DisplayController.shared.addNewDisplays()
      // In normal full screen mode AppKit will automatically adjust the window frame if the window
      // is moved to a new screen such as when the window is on an external display and that display
      // is disconnected. In legacy full screen mode IINA is responsible for adjusting the window's
      // frame.
      guard countChanged, fsState.isFullscreen, Preference.bool(for: .useLegacyFullScreen) else { return }
      setWindowFrameForLegacyFullScreen()
    }

    // Observe the loop knobs on the progress bar and update mpv when the knobs move.
    addObserver(to: .default, forName: .iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopA) { [weak self] _ in
      guard let self = self else { return }
      let seconds = self.percentToSeconds(self.playSlider.abLoopA.doubleValue)
      self.player.abLoopA = seconds
      self.player.sendOSD(.abLoopUpdate(.aSet, VideoTime(seconds).stringRepresentation))
    }
    addObserver(to: .default, forName: .iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopB) { [weak self] _ in
      guard let self = self else { return }
      let seconds = self.percentToSeconds(self.playSlider.abLoopB.doubleValue)
      self.player.abLoopB = seconds
      self.player.sendOSD(.abLoopUpdate(.bSet, VideoTime(seconds).stringRepresentation))
    }

    // Observers for toolbar buttons
    let notifications: [Notification.Name] = [.iinaPIPStatusChanged, .iinaFullscreenChanged, .iinaSidebarStatusChanged]
    notifications.forEach {
      NotificationCenter.default.addObserver(self, selector: #selector(updateOSCToolbarButtons(_:)), name: $0, object: nil)
    }

    player.events.emit(.windowLoaded)

    // Must workaround an AppKit defect in some versions of macOS. This defect is known to exist in
    // Catalina and Big Sur. The problem was not reproducible in early versions of Monterey. It
    // reappeared in Ventura. The status of other versions of macOS is unknown, however the
    // workaround should be safe to apply in any version of macOS. The problem was reported in
    // issues #4229, #3159, #3097 and #3253. The titles of open windows shown in the "Window" menu
    // are automatically managed by the AppKit framework. To improve performance PlayerCore caches
    // and reuses player instances along with their windows. This technique is valid and recommended
    // by Apple. But in some versions of macOS, if a window is reused the framework will display the
    // title first used for the window in the "Window" menu even after IINA has updated the title of
    // the window. This problem can also be seen when right-clicking or control-clicking the IINA
    // icon in the dock. As a workaround reset the window's title to "Window" before it is reused.
    // This is the default title AppKit assigns to a window when it is first created. Surprising and
    // rather disturbing this works as a workaround, but it does.
    window.title = "Window"

    // As there have been issues in this area, log details about the screen selection process.
    NSScreen.log("window.screen", window.screen)
    NSScreen.screens.enumerated().forEach { screen in
      if screen.element != window.screen {
        NSScreen.log("NSScreen.screens[\(screen.offset)]" , screen.element)
      }
    }

    // If a video is not actively playing then the initial drawing of the view needs to be forced.
    // The forceDraw method will check to see if drawing is actually needed.
    forceDraw("window loaded")
  }

  func setWindowToolbar() {
    guard let window else { return }

    let compactUI = Preference.bool(for: .compactUI)
    let hasLeadingSidebar = sidebars.leadingSidebar.status != .hidden

    if (compactUI && !hasLeadingSidebar) || fsState != .windowed {
      window.toolbar = nil
    } else if hasLeadingSidebar {
      window.toolbar = NSToolbar()
      window.toolbarStyle = .unified
      window.toolbar?.displayMode = .iconOnly
    } else {
      window.toolbar = NSToolbar()
      window.toolbarStyle = .unifiedCompact
      window.toolbar?.displayMode = .iconOnly
    }
  }

  /// Returns the position in seconds for the given percent of the total duration of the video the percentage represents.
  ///
  /// The number of seconds returned must be considered an estimate that could change. The duration of the video is obtained from
  /// the [mpv](https://mpv.io/manual/stable/) `duration` property. The documentation for this property cautions that
  /// mpv is not always able to determine the duration and when it does return a duration it may be an estimate. If the duration is
  /// unknown this method will fallback to using the current playback position, if that is known. Otherwise this method will return zero.
  /// - Parameter percent: Position in the video as a percentage of the duration.
  /// - Returns: The position in the video the given percentage represents.
  private func percentToSeconds(_ percent: Double) -> Double {
    if let duration = player.info.videoDuration?.second {
      return duration * percent / 100
    } else if let position = player.info.videoPosition?.second {
      return position * percent / 100
    } else {
      return 0
    }
  }

  func addVideoViewToWindow() {
    guard let cv = window?.contentView else { return }
    if videoView.superview != nil {
      videoView.removeFromSuperview()
    }
    cv.addSubview(videoView, positioned: .below, relativeTo: nil)
    videoView.translatesAutoresizingMaskIntoConstraints = false
    setupVideoViewConstraints()
  }

  private func setupVideoViewConstraints() {
    guard let cv = window?.contentView else { return }

    layoutSides.forEach { videoViewConstraints[$0].flatMap(cv.removeConstraint) }
    if Preference.bool(for: .edgeToEdgeVideo) {
      layoutSides.forEach { attr in
        videoViewConstraints[attr] = NSLayoutConstraint(item: videoView, attribute: attr, relatedBy: .equal,
                                                        toItem: cv, attribute: attr, multiplier: 1, constant: 0)
      }
    } else {
      let docked = Preference.bool(for: .dockedControlBarAndTitlebar)
      videoViewConstraints[.top] = videoView.topAnchor
        .constraint(equalTo: docked ? titleBarView.bottomAnchor : cv.topAnchor)
      videoViewConstraints[.bottom] = videoView.bottomAnchor
        .constraint(equalTo: docked ? oscBottomView.topAnchor : cv.bottomAnchor)
      videoViewConstraints[.leading] = videoView.leadingAnchor.constraint(equalTo: sidebars.leadingSidebar.view.trailingAnchor)
      videoViewConstraints[.trailing] = videoView.trailingAnchor.constraint(equalTo: sidebars.trailingSidebar.view.leadingAnchor)
    }
    layoutSides.forEach { videoViewConstraints[$0]?.isActive = true }
  }

  @objc func removeVideoViewBlackBars() {
    guard let window, Preference.unlockWindowAspectRatio else { return }

    let currentSize = videoView.frame.size
    let videoSize = player.videoSizeForDisplay
    let newSize = currentSize.crop(withAspect: CGFloat(videoSize.0) / CGFloat(videoSize.1))
    let dw = newSize.width - currentSize.width
    let dh = newSize.height - currentSize.height
    let currWindowSize = window.frame.size
    let newWindowSize = NSSize(width: currWindowSize.width + dw, height: currWindowSize.height + dh)
    let newFrame = window.frame.centeredResize(to: newWindowSize)

    window.setFrame(newFrame, display: true, animate: true)
  }

  private func setupOSCToolbarButtons(_ buttons: [Preference.ToolBarButton]) {
    fragToolbarView.views.forEach { fragToolbarView.removeView($0) }
    for buttonType in buttons {
      let button = NSButton()
      OSCToolbarButton.setStyle(of: button, buttonType: buttonType, reducedWidth: buttons.count > 4)
      button.action = #selector(self.toolBarButtonAction(_:))
      fragToolbarView.addView(button, in: .trailing)
    }
  }

  @objc
  private func updateOSCToolbarButtons(_ notification: Notification) {

    func highlight(_ button: Preference.ToolBarButton, _ isHighlighted: Bool) {
      let buttons = fragToolbarView.subviews as! [NSButton]
      let currentButton = buttons.first(where: { $0.tag == button.rawValue })
      currentButton?.image = isHighlighted ? button.alternateImage() : button.image()
    }

    let enable = (notification.userInfo?["enable"] as? Bool ?? false)
    switch notification.name {
    case .iinaPIPStatusChanged:
      highlight(.pip, enable)
    case .iinaFullscreenChanged:
      highlight(.fullScreen, enable)
    case .iinaSidebarStatusChanged:
      // no userInfo is provided in this notification
      highlight(.settings, sidebars.isShowing(.settings))
      highlight(.plugins, sidebars.isShowing(.plugins))
      highlight(.playlist, sidebars.isShowing(.playlist))
    default:
      break
    }
  }

  private func setupOnScreenController(withPosition newPosition: Preference.OSCPosition) {

    guard !oscIsInitialized || oscPosition != newPosition else { return }
    oscIsInitialized = true

    let isSwitchingToTop = newPosition == .top
    let isSwitchingFromTop = oscPosition == .top
    let isFloating = newPosition == .floating

    // reset
    [oscFloatingView, oscBottomView].forEach { $0.isHidden = true }

    oscFloatingView.isDragging = false

    // detach all fragment views
    [oscFloatingView.oscTopView, titleBarView.oscView, oscBottomView.oscView].forEach { stackView in
      stackView!.views.forEach {
        stackView!.removeView($0)
      }
    }
    [fragSliderView, fragControlView, fragToolbarView, fragVolumeView].forEach {
        $0!.removeFromSuperview()
    }

    let isInFullScreen = fsState.isFullscreen
    titleBarView.update(hasOSC: isSwitchingToTop, inFullScreen: isInFullScreen)

    if isSwitchingFromTop && isInFullScreen {
      titleBarView.isHidden = true
    }

    oscBottomView.updateVerticalConstraint(isDisplaying: newPosition == .bottom)

    oscPosition = newPosition

    // add fragment views
    switch oscPosition {
    case .floating:
      currentControlBar = oscFloatingView
      fragControlView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragControlViewLeftView)
      fragControlView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragControlViewRightView)
      oscFloatingView.oscTopView.addView(fragVolumeView, in: .leading)
      oscFloatingView.oscTopView.addView(fragToolbarView, in: .trailing)
      oscFloatingView.oscTopView.addView(fragControlView, in: .center)

      // Setting the visibility priority to detach only will cause freeze when resizing the window
      // (and triggering the detach) in macOS 11.
      if !isMacOS11 {
        oscFloatingView.oscTopView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragVolumeView)
        oscFloatingView.oscTopView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragToolbarView)
        oscFloatingView.oscTopView.setClippingResistancePriority(.defaultLow, for: .horizontal)
      }
      oscFloatingView.oscBottomView.addSubview(fragSliderView)
      Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": fragSliderView])
      Utility.quickConstraints(["H:|-(>=0)-[v]-(>=0)-|"], ["v": fragControlView])
      // center control bar
      let cph = Preference.float(for: .controlBarPositionHorizontal)
      let cpv = Preference.float(for: .controlBarPositionVertical)
      oscFloatingView.xConstraint.constant = window!.frame.width * CGFloat(cph)
      oscFloatingView.yConstraint.constant = window!.frame.height * CGFloat(cpv)
    case .top:
      let oscTopMainView = titleBarView.oscView!
      currentControlBar = nil
      fragControlView.setVisibilityPriority(.notVisible, for: fragControlViewLeftView)
      fragControlView.setVisibilityPriority(.notVisible, for: fragControlViewRightView)
      oscTopMainView.addView(fragVolumeView, in: .trailing)
      oscTopMainView.addView(fragToolbarView, in: .trailing)
      oscTopMainView.addView(fragControlView, in: .leading)
      oscTopMainView.addView(fragSliderView, in: .leading)
      oscTopMainView.setClippingResistancePriority(.defaultLow, for: .horizontal)
      oscTopMainView.setVisibilityPriority(.mustHold, for: fragSliderView)
      oscTopMainView.setVisibilityPriority(.detachEarly, for: fragVolumeView)
      oscTopMainView.setVisibilityPriority(.detachEarlier, for: fragToolbarView)
    case .bottom:
      oscBottomView.isHidden = false
      let oscBottomMainView = oscBottomView.oscView!
      currentControlBar = oscBottomView
      fragControlView.setVisibilityPriority(.notVisible, for: fragControlViewLeftView)
      fragControlView.setVisibilityPriority(.notVisible, for: fragControlViewRightView)
      oscBottomMainView.addView(fragVolumeView, in: .trailing)
      oscBottomMainView.addView(fragToolbarView, in: .trailing)
      oscBottomMainView.addView(fragControlView, in: .leading)
      oscBottomMainView.addView(fragSliderView, in: .leading)
      oscBottomMainView.setClippingResistancePriority(.defaultLow, for: .horizontal)
      oscBottomMainView.setVisibilityPriority(.mustHold, for: fragSliderView)
      oscBottomMainView.setVisibilityPriority(.detachEarly, for: fragVolumeView)
      oscBottomMainView.setVisibilityPriority(.detachEarlier, for: fragToolbarView)
    }

    fadeableViews.update()
    showUI()

    if isFloating {
      fragControlViewMiddleButtons1Constraint.constant = 24
      fragControlViewMiddleButtons2Constraint.constant = 24
    } else {
      fragControlViewMiddleButtons1Constraint.constant = 16
      fragControlViewMiddleButtons2Constraint.constant = 16
    }
  }

  // MARK: - Mouse / Trackpad events

  override func keyDown(with event: NSEvent) {
    if isShowingPersistentOSD {
      let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
      let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)

      if normalizedKeyCode == "ESC", osdView.performKeyEquivalent(with: event) {
        log("ESC key was handled by OSD", level: .verbose)
        return
      }
    }

    super.keyDown(with: event)
  }

  @discardableResult
  override func handleKeyBinding(_ keyBinding: KeyMapping) -> Bool {
    let success = super.handleKeyBinding(keyBinding)
    if success && keyBinding.action.first! == MPVCommand.screenshot.rawValue {
      player.sendOSD(.screenshot)
    }
    return success
  }

  override func pressureChange(with event: NSEvent) {
    if isCurrentPressInSecondStage == false && event.stage == 2 {
      performMouseAction(Preference.enum(for: .forceTouchAction))
      isCurrentPressInSecondStage = true
    } else if event.stage == 1 {
      isCurrentPressInSecondStage = false
    }
  }

  /// Workaround for issue #4183, Cursor remains visible after resuming playback with the touchpad using secondary click
  ///
  /// When IINA hides the OSC it also calls the macOS AppKit method `NSCursor.setHiddenUntilMouseMoves` to hide the
  /// cursor. In macOS Catalina that method works as documented and keeps the cursor hidden until the mouse moves. Starting with
  /// macOS Big Sur the cursor becomes visible if mouse buttons are clicked without moving the mouse. To workaround this defect
  /// call this method again to keep the cursor hidden when the OSC is not visible.
  ///
  /// This erroneous behavior has been reported to Apple as: "Regression in NSCursor.setHiddenUntilMouseMoves"
  /// Feedback number FB11963121
  private func workaroundCursorDefect() {
    guard animationState == .hidden else { return }
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  override func mouseDown(with event: NSEvent) {
    if Logger.isEmitting(.verbose) {
      log("MainWindow mouseDown @ \(event.locationInWindow)", level: .verbose)
    }
    workaroundCursorDefect()
    // do nothing if it's related to floating OSC
    guard !oscFloatingView.isDragging else { return }
    mousePosRelatedToWindow = event.locationInWindow
    let consumedBySidebar = sidebars.handleMouseDown(event, at: event.locationInWindow)
    // currently, it only passes the event to plugins in super
    if !consumedBySidebar {
      super.mouseDown(with: event)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    if sidebars.handleMouseDragged(event) {
      return
    }
    if !fsState.isFullscreen {
      guard !oscFloatingView.isDragging else { return }

      if let mousePosRelatedToWindow = mousePosRelatedToWindow {
        if !isDragging {
          /// Require that the user must drag the cursor at least a small distance for it to start a "drag" (`isDragging==true`)
          /// The user's action will only be counted as a click if `isDragging==false` when `mouseUp` is called.
          /// (Apple's trackpad in particular is very sensitive and tends to call `mouseDragged()` if there is even the slightest
          /// roll of the finger during a click, and the distance of the "drag" may be less than `minimumInitialDragDistance`)
          if mousePosRelatedToWindow.distance(to: event.locationInWindow) <= minimumInitialDragDistance {
            return
          }
          if Logger.isEmitting(.verbose) {
            log("MainWindow mouseDrag: minimum dragging distance was met", level: .verbose)
          }
          isDragging = true
        }
        window?.performDrag(with: event)
        super.informPluginMouseDragged(with: event)
      }
    }
  }

  override func mouseUp(with event: NSEvent) {
    if Logger.isEmitting(.verbose) {
      log("MainWindow mouseUp @ \(event.locationInWindow), isDragging: \(isDragging), resizingSidebar: \(String(describing: sidebars.resizingSidebarSide)), clickCount: \(event.clickCount)", level: .verbose)
    }
    workaroundCursorDefect()
    mousePosRelatedToWindow = nil
    if isDragging {
      // if it's a mouseup after dragging window
      isDragging = false
    } else if sidebars.handleMouseUp(event) {
      // sidebar handled it (resize finish or click-outside-to-dismiss)
    } else {
      if event.clickCount == 2 && event.inAnyOf([titleBarView]) {
        let userDefault = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
        if userDefault == "Minimize" {
          window?.performMiniaturize(nil)
        } else if userDefault == "Maximize" {
          window?.performZoom(nil)
        }
        return
      }

      super.mouseUp(with: event)
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    workaroundCursorDefect()
    super.otherMouseDown(with: event)
  }

  override func otherMouseUp(with event: NSEvent) {
    workaroundCursorDefect()
    super.otherMouseUp(with: event)
  }

  /// Workaround for issue #4183, Cursor remains visible after resuming playback with the touchpad using secondary click
  ///
  /// AppKit contains special handling for [rightMouseDown](https://developer.apple.com/documentation/appkit/nsview/event_handling/1806802-rightmousedown) having to do with contextual menus.
  /// Even though the documentation indicates the event will be passed up the responder chain, the event is not being received by the
  /// window controller. We are having to catch the event in the view. Because of that we do not call the super method and instead
  /// return to the view.`
  override func rightMouseDown(with event: NSEvent) {
    workaroundCursorDefect()
    super.rightMouseDown(with: event)
  }

  override func rightMouseUp(with event: NSEvent) {
    workaroundCursorDefect()
    super.rightMouseUp(with: event)
  }

  override internal func performMouseAction(_ action: Preference.MouseClickAction) {
    super.performMouseAction(action)
    switch action {
    case .fullscreen:
      toggleWindowFullScreen()
    case .hideOSC:
      hideUIAndCursor()
    case .togglePIP:
      menuTogglePIP(.dummy)
    case .abLoop:
      player.abLoop()
    case .resetSpeed:
      player.setSpeed(1.0)
    default:
      break
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    if !isMomentumScrollingAllowed && !event.momentumPhase.isEmpty {
      // ignore delta caused by abrupt momentum phases
      return
    }
    /**
     reference: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html#//apple_ref/doc/uid/10000060i-CH13

     normal momentum scrolling will be like this:
        phase=Began momentumPhase=None
        phase=Changed momentumPhase=None
        ...
        **phase=Ended** momentumPhase=None
        **phase=None** momentumPhase=None
        phase=None **momentumPhase=Began**

     abnormal momentum scrolling, e.g. after dismissing notification banner quickly like:
        phase=None **momentumPhase=Began/Changed**
     */
    isMomentumScrollingAllowed = event.phase.contains(.ended) || isMouseInWindow // previous
    if event.inAnyOf([fragSliderView]) && playSlider.isEnabled {
      seekOverride = true
    } else if event.inAnyOf([fragVolumeView]) && volumeSlider.isEnabled {
      volumeOverride = true
    } else {
      guard !event.inAnyOf([currentControlBar]) else { return }
    }

    guard !event.inAnyOf(sidebars.mouseActionDisabledViews + [titleBarView])
               || seekOverride || volumeOverride else { return }

    super.scrollWheel(with: event)

    seekOverride = false
    volumeOverride = false
  }

  override func mouseEntered(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let obj = event.trackingArea?.userInfo?["obj"] as? Int else {
      log("No data for tracking area", level: .warning)
      return
    }
    mouseExitEnterCount += 1
    if obj == 0 {
      // main window
      isMouseInWindow = true
      showUI()
      updateTimer()
    } else if obj == 1 {
      // slider
      if oscFloatingView.isDragging { return }
      isMouseInSlider = true
      if !oscFloatingView.isDragging {
        timePreviewView.isHidden = false
        thumbnailPeekView.isHidden = !player.info.thumbnailsReady
      }
      refreshSeekTimeAndThumbnail(from: event)
    }
  }

  override func mouseExited(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let obj = event.trackingArea?.userInfo?["obj"] as? Int else {
      log("No data for tracking area", level: .warning)
      return
    }
    mouseExitEnterCount += 1
    if obj == 0 {
      // main window
      isMouseInWindow = false
      if oscFloatingView.isDragging { return }
      destroyTimer()
      hideUI()
      // reset after moved out of window
      isMomentumScrollingAllowed = false
    } else if obj == 1 {
      // slider
      isMouseInSlider = false
      timePreviewView.isHidden = true
      refreshSeekTimeAndThumbnail(from: event)
      thumbnailPeekView.isHidden = true
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard !isInInteractiveMode else { return }

    refreshSeekTimeAndThumbnail(from: event)
    if isMouseInWindow {
      showUI()
    }
    // check whether mouse is in osc
    if event.inAnyOf([currentControlBar, titleBarView]) {
      destroyTimer()
    } else {
      updateTimer()
    }
  }

  @objc func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard pinchAction != .none else { return }
    guard !isInInteractiveMode, let window = window, let screenFrame = NSScreen.main?.visibleFrame else { return }

    switch pinchAction {
    case .none:
      return
    case .fullscreen:
      // enter/exit fullscreen
      if recognizer.state == .began {
        let isEnlarge = recognizer.magnification > 0
        if isEnlarge != fsState.isFullscreen {
          recognizer.state = .recognized
          self.toggleWindowFullScreen()
        }
      }
    case .windowSize:
      if fsState.isFullscreen { return }

      // adjust window size
      if recognizer.state == .began {
        // began
        lastMagnification = recognizer.magnification
        videoView.videoLayer.inLiveResize = true
        frameWhenStartedPinching = window.frame
      } else if recognizer.state == .changed {
        // changed
        let offset = recognizer.magnification - lastMagnification + 1.0;
        let newWidth = window.frame.width * offset
        let newHeight = newWidth / frameWhenStartedPinching.size.aspect

        //Check against max & min threshold
        if newHeight < screenFrame.height && newHeight > AppData.mainWindowMinSize.height && newWidth > AppData.mainWindowMinSize.width {
          let newSize = NSSize(width: newWidth, height: newHeight);
          window.setFrame(frameWhenStartedPinching.centeredResize(to: newSize), display: true)
        }

        lastMagnification = recognizer.magnification
      } else if recognizer.state == .ended {
        updateWindowParametersForMPV()
        videoView.videoLayer.inLiveResize = false
      }
    }
  }

  // MARK: - Window delegate: Open / Close

  /// Displays the window.
  /// - Important: AppKit will refuse to move a window to a different screen before the window has been shown. If the origin
  ///     places the window on a screen other than `window.screen` then
  ///     [showWindow](https://developer.apple.com/documentation/appkit/nswindowcontroller/showwindow(_:))
  ///     will adjust the origin such that the window is within the current screen of the window. This will happen when
  ///     `determineScreenToUse` selects a different screen for the window based on `MainWindowLastPosition`.  To
  ///     workaround the AppKit behavior requires allowing `showWindow` to complete and then resetting the origin to display the
  ///     window on the correct screen. As of macOS Tahoe this AppKit defect has been fixed.
  /// - Parameter sender: The control sending the message; can be `nil`.
  override func showWindow(_ sender: Any?) {
    guard let window else { return }
    log("Showing window at \(window.frame)")
    let origin = window.frame.origin
    super.showWindow(sender)
    if #unavailable(macOS 26), Preference.bool(for: .enableWrongScreenWorkaround),
       NSScreen.screens.count > 1, window.frame.origin != origin {
      log("NSWindowController.showWindow changed origin from \(origin) to \(window.frame.origin)")
      if player.info.state == .loaded, Preference.bool(for: .fullScreenWhenOpen),
         !fsState.isFullscreen, !player.isInMiniPlayer {
        // PlayerCore.notifyWindowVideoSizeChanged will be toggling the window into full screen
        // mode. Merely resetting the origin works when NSWindow.toggleFullScreen is called.
        log("Resetting window origin to \(origin)")
        window.setFrameOrigin(origin)
      } else {
        // When not immediately toggling into full screen mode resetting the origin will not work
        // unless it is done in another task.
        log("Applying workaround for AppKit using the wrong screen")
        window.alphaValue = 0
        DispatchQueue.main.async {
          self.log("Resetting window origin to \(origin)")
          window.setFrameOrigin(origin)
          window.alphaValue = 1
        }
      }
    }
    resetCollectionBehavior()
    // update buffer indicator view
    bufferIndicatorView.update()
    // start tracking mouse event
    guard let cv = window.contentView else { return }
    if cv.trackingAreas.isEmpty {
      cv.addTrackingArea(NSTrackingArea(rect: cv.bounds,
                                        options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                        owner: self, userInfo: ["obj": 0]))
    }
    if playSlider.trackingAreas.isEmpty {
      playSlider.addTrackingArea(NSTrackingArea(rect: playSlider.bounds,
                                                options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                                owner: self, userInfo: ["obj": 1]))
    }
    // Track the thumbs on the progress bar representing the A-B loop points and treat them as part
    // of the slider.
    if playSlider.abLoopA.trackingAreas.count <= 1 {
      playSlider.abLoopA.addTrackingArea(NSTrackingArea(rect: playSlider.abLoopA.bounds, options:  [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 1]))
    }
    if playSlider.abLoopB.trackingAreas.count <= 1 {
      playSlider.abLoopB.addTrackingArea(NSTrackingArea(rect: playSlider.abLoopB.bounds, options: [.activeAlways, .enabledDuringMouseDrag, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 1]))
    }

    // update timer
    updateTimer()
    // truncate middle for title
    if let attrTitle = titleTextField?.attributedStringValue.mutableCopy() as? NSMutableAttributedString, attrTitle.length > 0 {
      let p = attrTitle.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSMutableParagraphStyle
      p.lineBreakMode = .byTruncatingMiddle
      attrTitle.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: attrTitle.length))
    }
  }

  func windowWillClose(_ notification: Notification) {
    shouldApplyInitialWindowSize = true
    // Close PIP
    if pipStatus == .inPIP {
      exitPIP()
    }
    // stop playing
    if case .fullscreen(legacy: true, priorWindowedFrame: _) = fsState {
      restoreDockSettings()
    }
    player.stop()
    // stop tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
    cv.trackingAreas.forEach(cv.removeTrackingArea)
    playSlider.trackingAreas.forEach(playSlider.removeTrackingArea)
    UserDefaults.standard.set(NSStringFromRect(window!.frame), forKey: "MainWindowLastPosition")

    player.events.emit(.windowWillClose)
  }

  // MARK: - Window delegate: Full screen

  func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
    return [window]
  }

  func customWindowsToExitFullScreen(for window: NSWindow) -> [NSWindow]? {
    return [window]
  }

  func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenOn screen: NSScreen, withDuration duration: TimeInterval) {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = duration
      window.animator().setFrame(screen.frame, display: true, animate: !Preference.bool(for: PK.disableAnimations))
    }, completionHandler: nil)
  }

  func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
    if NSMenu.menuBarVisible() {
      NSMenu.setMenuBarVisible(false)
    }
    let priorWindowedFrame = fsState.priorWindowedFrame!

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = duration
      window.animator().setFrame(priorWindowedFrame, display: true, animate: !Preference.bool(for: PK.disableAnimations))
    }, completionHandler: nil)

    NSMenu.setMenuBarVisible(true)
  }

  /// The window is about to enter full screen mode.
  ///
  /// The `NSWindowDelegate` method
  /// [windowWillEnterFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowwillenterfullscreen(_:))
  /// is called after the AppKit
  /// [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// method has been called when the window is not in full screen mode. Prepare the window to start transitioning to full screen mode.
  /// - Attention: After altering this method you _must_ update the
  ///     [windowDidFailToEnterFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidfailtoenterfullscreen(_:))
  ///     method which is responsible for reverting changes made by this method should the transition to full screen mode fail.
  /// - Parameter notification: A notification named
  ///     [willEnterFullScreenNotification](https://developer.apple.com/documentation/appkit/nswindow/willenterfullscreennotification).
  func windowWillEnterFullScreen(_ notification: Notification) {
    log("Entering full screen mode")
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning to full screen mode.
    videoView.displayActive()
    if isInInteractiveMode {
      exitInteractiveMode(immediately: true)
    }

    // Set the appearance to match the theme so the titlebar matches the theme
    let iinaTheme = Preference.enum(for: .themeMaterial) as Preference.Theme
    window?.appearance = NSAppearance(iinaTheme: iinaTheme)

    // show titlebar
    titleBarView.update(hasOSC: oscPosition == .top, inFullScreen: true)
    standardWindowButtons.forEach { $0.alphaValue = 0 }
    titleTextField?.alphaValue = 0

    setWindowFloatingOnTop(false, updateOnTopStatus: false)

    thumbnailPeekView.isHidden = true
    timePreviewView.isHidden = true
    isMouseInSlider = false

    let isLegacyFullScreen = notification.name == .iinaLegacyFullScreen
    fsState.startAnimatingToFullScreen(legacy: isLegacyFullScreen, priorWindowedFrame: window!.frame)
    setWindowToolbar()
    fadeableViews.update()
  }

  /// The window has entered full screen mode.
  ///
  /// The `NSWindowDelegate` method
  /// [windowDidEnterFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidenterfullscreen(_:))
  /// is called after the transition into full screen mode has finished. Finish configuring the window for full screen mode.
  /// - Parameter notification: A notification named
  ///     [didEnterFullScreenNotification](https://developer.apple.com/documentation/appkit/nswindow/didenterfullscreennotification).
  func windowDidEnterFullScreen(_ notification: Notification) {
    log("Entered full screen mode")
    fsState.finishAnimating()

    titleTextField?.alphaValue = 1
    for view in standardWindowButtons {
      view.alphaValue = 1
      view.isHidden = false
    }
    window?.titlebarAppearsTransparent = false

    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    forceDraw("entered full screen mode")

    if Preference.bool(for: .blackOutMonitor) {
      blackOutOtherMonitors()
    }
    fadeableViews.update()

    if player.info.state == .paused {
      if Preference.bool(for: .playWhenEnteringFullScreen) {
        player.resume()
      } else {
        // When playback is paused the display link is stopped in order to avoid wasting energy on
        // needless processing. It must be running while transitioning to full screen mode. Now that
        // the transition has completed it can be stopped.
        videoView.displayIdle()
      }
    }

    player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: true)

    updateWindowParametersForMPV()

    // Exit PIP if necessary
    if pipStatus == .inPIP {
      exitPIP()
    }

    additionalInfoView.update()
    player.events.emit(.windowFullscreenChanged, data: true)
    NotificationCenter.default.post(name: .iinaFullscreenChanged, object: nil, userInfo: ["enable": true])
  }

  /// Called if the window failed to enter full screen mode.
  ///
  /// The AppKit [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// method can fail. If that happens while transitioning into full screen mode the `NWWindowDelegate` method
  /// [windowDidFailToEnterFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidfailtoenterfullscreen(_:))
  /// is called. When this happens the changes made by `windowWillEnterFullScreen` must be reverted.
  /// - Parameter window: The window that failed to enter to full screen mode.
  func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    log("AppKit failed to enter full screen mode! Restoring previous windowed state", level: .warning)
    guard case .animating(let toFullscreen, let legacy, let priorWindowedFrame) = fsState,
            toFullscreen, !legacy else {
      // Must not occur! Represents an error in IINA or AppKit.
      log("Unable to restore windowed state: \(fsState)", level: .error)
      return
    }

    // Reset the full screen state to indicate exiting full screen mode so that finishAnimating
    // will correctly set the state to windowed.
    fsState = .animating(toFullscreen: false, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
    fsState.finishAnimating()

    titleBarView.update(hasOSC: oscPosition == .top, inFullScreen: false)
    setWindowToolbar()
    fadeableViews.update()
    showUI()

    if player.info.state == .playing {
      setWindowFloatingOnTop(isOntop, updateOnTopStatus: false)
    }

    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    forceDraw("failed to enter full screen mode")
  }

  /// The window is about to exit full screen mode.
  ///
  /// The `NSWindowDelegate` method [windowWillExitFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowwillexitfullscreen(_:))
  /// is called after the AppKit
  /// [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// method has been called when the window is in full screen mode. Prepare the window to start transitioning to windowed mode.
  /// - Attention: After altering this method you _must_ update the
  ///     [windowDidFailToExitFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidfailtoexitfullscreen(_:))
  ///     method which is responsible for reverting changes made by this method should the transition to wndowed mode fail.
  /// - Parameter notification: A notification named
  ///     [willExitFullScreenNotification](https://developer.apple.com/documentation/appkit/nswindow/willexitfullscreennotification).
  func windowWillExitFullScreen(_ notification: Notification) {
    log("Exiting full screen mode")
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning from full screen mode.
    videoView.displayActive()
    if isInInteractiveMode {
      exitInteractiveMode(immediately: true)
    }

    titleBarView.update(hasOSC: oscPosition == .top, inFullScreen: false)

    thumbnailPeekView.isHidden = true
    timePreviewView.isHidden = true
    additionalInfoView.isHidden = true
    isMouseInSlider = false

    fsState.startAnimatingToWindow()
    fadeableViews.update()
  }

  /// The window has left full screen mode.
  ///
  /// The `NSWindowDelegate` method
  /// [windowDidExitFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidexitfullscreen(_:))
  /// is called after the transition to windowed mode initiated by calling
  /// [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// completes. Finish configuring IINA for windowed mode.
  /// - Important: The following unexpected sequence of calls from AppKit has been encountered:
  ///     - windowWillExitFullScreen
  ///     - windowDidFailToExitFullScreen
  ///     - windowDidExitFullScreen
  ///
  ///     As this AppKit behavior is very hard to trigger it is not entirely clear why is happening. The working assumption is that this
  ///     occurs when the app starts to terminate after failing to exit full screen mode. See issue
  ///     [#5368](https://github.com/iina/iina/issues/5368) for more details.
  /// - Parameter notification: A notification named
  ///     [didExitFullScreenNotification](https://developer.apple.com/documentation/appkit/nswindow/didexitfullscreennotification).
  func windowDidExitFullScreen(_ notification: Notification) {
    log("Exited full screen mode")

    if fsState.isFullscreen {
      // IINA should not be in full screen mode at this point. The fsState should indicate IINA is
      // animating to the windowed state. This happens when AppKit calls windowDidExitFullScreen
      // after having called windowDidFailToExitFullScreen. As we think this is triggered when the
      // app starts terminating we only change fsState to indicate IINA was animating to windowed
      // mode. If this is not done the call to finishAnimating below will trigger a fatal error.
      log("AppKit exited full screen mode without informing IINA", level: .warning)
      fsState.startAnimatingToWindow()
    }

    if Preference.bool(for: PK.disableAnimations) {
      // When animation is not used exiting full screen does not restore the previous size of the
      // window. Restore it now.
      window!.setFrame(fsState.priorWindowedFrame!, display: true, animate: false)
    }

    window?.titlebarAppearsTransparent = true

    fsState.finishAnimating()
    setWindowToolbar()
    fadeableViews.update()

    if Preference.bool(for: .blackOutMonitor) {
      removeBlackWindow()
    }

    if player.info.state == .paused {
      // When playback is paused the display link is stopped in order to avoid wasting energy on
      // needless processing. It must be running while transitioning from full screen mode. Now that
      // the transition has completed it can be stopped.
      videoView.displayIdle()
    }

    player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: false)

    // Must not access mpv while it is asynchronously processing stop and quit commands.
    // See comments in windowWillExitFullScreen for details.
    guard player.info.state.active else { return }
    showUI()
    updateTimer()

    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    forceDraw("exited full screen mode")

    if Preference.bool(for: .pauseWhenLeavingFullScreen) && player.info.state == .playing {
      player.pause()
    }

    // restore ontop status
    if player.info.state == .playing {
      setWindowFloatingOnTop(isOntop, updateOnTopStatus: false)
    }

    resetCollectionBehavior()
    updateWindowParametersForMPV()

    player.events.emit(.windowFullscreenChanged, data: false)
    NotificationCenter.default.post(name: .iinaFullscreenChanged, object: nil, userInfo: ["enable": false])
  }

  /// Called if the window failed to exit full screen mode.
  ///
  /// The AppKit [toggleFullScreen](https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:))
  /// method can fail. If that happens while transitioning out of full screen mode the `NWWindowDelegate` method
  /// [windowDidFailToExitFullScreen](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidfailtoexitfullscreen(_:))
  /// is called. When this happens the changes made by `windowWillExitFullScreen` must be reverted.
  /// - Parameter window: The window that failed to exit to full screen mode.
  func windowDidFailToExitFullScreen(_ window: NSWindow) {
    log("AppKit failed to exit full screen mode! Restoring full screen state", level: .error)
    guard case .animating(let toFullscreen, let legacy, let priorWindowedFrame) = fsState,
            !toFullscreen, !legacy else {
      // Must not occur! Represents an error in IINA or AppKit.
      log("Unable to restore full screen state: \(fsState)", level: .error)
      return
    }

    // Reset the full screen state to indicate entering full screen mode so that finishAnimating
    // will correctly set the state to  full screen mode.
    fsState = .animating(toFullscreen: true, legacy: legacy, priorWindowedFrame: priorWindowedFrame)
    fsState.finishAnimating()

    titleBarView.update(hasOSC: oscPosition == .top, inFullScreen: true)
    setWindowToolbar()
    fadeableViews.update()
    showUI()

    additionalInfoView.update()

    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    forceDraw("failed to exit full screen mode")
  }

  func toggleWindowFullScreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    switch fsState {
    case .windowed:
      guard !player.isInMiniPlayer else { return }
      if Preference.bool(for: .useLegacyFullScreen) {
        log("Will enter legacy full screen mode")
        self.legacyAnimateToFullscreen()
      } else {
        log("Requesting AppKit enter full screen mode")
        window.toggleFullScreen(self)
      }
    case let .fullscreen(legacy, oldFrame):
      if legacy {
        log("Will exit legacy full screen mode")
        self.legacyAnimateToWindowed(framePriorToBeingInFullscreen: oldFrame)
      } else {
        log("Requesting AppKit exit full screen mode")
        window.toggleFullScreen(self)
      }
    case let .animating(toFullscreen, legacy, _):
      let legacyAppKit = legacy ? "IINA" : "AppKit"
      let enteringExiting = toFullscreen ? "entering" : "exiting"
      log("""
        \(legacyAppKit) is currently \(enteringExiting) full screen mode, \
        ignoring request to toggle full screen mode
        """)
    }
  }

  private func restoreDockSettings() {
    log("Restoring dock settings")
    NSApp.presentationOptions.remove(.autoHideMenuBar)
    NSApp.presentationOptions.remove(.autoHideDock)
  }

  private func legacyAnimateToWindowed(framePriorToBeingInFullscreen: NSRect) {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    // call delegate
    windowWillExitFullScreen(Notification(name: .iinaLegacyFullScreen))
    // stylemask
    window.styleMask.remove(.borderless)
    window.styleMask.insert(.resizable)
    window.styleMask.insert(.titled)
    window.hasShadow = true
    (window as! MainWindow).forceKeyAndMain = false
    window.level = .normal

    restoreDockSettings()
    // restore window frame and aspect ratio
    let videoSize = player.videoSizeForDisplay
    let aspectRatio = NSSize(width: videoSize.0, height: videoSize.1)
    let useAnimation = {
      // Animation causes lagging under the macOS Tahoe beta, so don't allow it for now.
      guard #unavailable(macOS 26) else { return false }
      return !Preference.bool(for: .disableAnimations)
    }()
    if useAnimation {
      // firstly resize to a big frame with same aspect ratio for better visual experience
      let aspectFrame = aspectRatio.shrink(toSize: window.frame.size).centeredRect(in: window.frame)
      window.setFrame(aspectFrame, display: true, animate: false)
    }
    // then animate to the original frame
    window.setFrame(framePriorToBeingInFullscreen, display: true, animate: useAnimation)
    setWindowAspectRatio(aspectRatio)
    // call delegate
    windowDidExitFullScreen(Notification(name: .iinaLegacyFullScreen))
  }

  /// Set the window frame and if needed the content view frame to appropriately use the full screen.
  ///
  /// For screens that contain a camera housing the content view will be adjusted to not use that area of the screen.
  private func setWindowFrameForLegacyFullScreen() {
    guard let window = self.window else { return }
    let useAnimation = {
      // Animation causes lagging under the macOS Tahoe beta, so don't allow it for now.
      guard #unavailable(macOS 26) else { return false }
      return !Preference.bool(for: .disableAnimations)
    }()
    let screen = window.screen ?? NSScreen.main!
    window.setFrame(screen.frame, display: true, animate: useAnimation)
    guard let unusable = screen.cameraHousingHeight else { return }
    // This screen contains an embedded camera. Shorten the height of the window's content view's
    // frame to avoid having part of the window obscured by the camera housing.
    let view = window.contentView!
    view.setFrameSize(NSMakeSize(view.frame.width, screen.frame.height - unusable))
  }

  private func legacyAnimateToFullscreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }
    // call delegate
    windowWillEnterFullScreen(Notification(name: .iinaLegacyFullScreen))
    // stylemask
    window.styleMask.insert(.borderless)
    window.styleMask.remove(.resizable)
    window.styleMask.remove(.titled)
    window.hasShadow = false
    (window as! MainWindow).forceKeyAndMain = true
    window.level = .floating

    // cancel aspect ratio
    window.resizeIncrements = NSSize(width: 1, height: 1)
    // auto hide menubar and dock
    NSApp.presentationOptions.insert(.autoHideMenuBar)
    NSApp.presentationOptions.insert(.autoHideDock)
    // set window frame and in some cases content view frame
    setWindowFrameForLegacyFullScreen()

    // The volume slider and the toolbar views in the floating OSC will be detached and not shown in
    // the floating OSC if the window is too narrow. Once in full screen mode there is enough space
    // for the full OSC to be shown. Sometimes, but not always, the subview holding the pause/resume
    // and left/right buttons will not be centered after the OSC expands to full size. Forcing
    // layout corrects this. See issue #5244.
    if oscPosition == .floating {
      fragControlView.needsLayout = true
    }

    // call delegate
    windowDidEnterFullScreen(Notification(name: .iinaLegacyFullScreen))
  }

  // MARK: - Window delegate: Size

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    guard let window = window else { return frameSize }
    // disable resizing in interactive mode, little benefit but complicates the layout logic
    if isInInteractiveMode {
      return window.frame.size
    }
    if frameSize.height <= AppData.mainWindowMinSize.height || frameSize.width <= AppData.mainWindowMinSize.width {
      return currentWindowAspectRatio.grow(toSize: AppData.mainWindowMinSize)
    }
    return frameSize
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = window else { return }

    // update control bar position
    if oscPosition == .floating {
      let cph = Preference.float(for: .controlBarPositionHorizontal)
      let cpv = Preference.float(for: .controlBarPositionVertical)

      let windowWidth = window.frame.width
      let margin: CGFloat = 10
      let minWindowWidth: CGFloat = 480 // 460 + 20 margin
      var xPos: CGFloat

      if windowWidth < minWindowWidth {
        // osc is compressed
        xPos = windowWidth / 2
      } else {
        // osc has full width
        let oscHalfWidth: CGFloat = 230
        xPos = windowWidth * CGFloat(cph)
        if xPos - oscHalfWidth < margin {
          xPos = oscHalfWidth + margin
        } else if xPos + oscHalfWidth + margin > windowWidth {
          xPos = windowWidth - oscHalfWidth - margin
        }
      }

      let windowHeight = window.frame.height
      var yPos = windowHeight * CGFloat(cpv)
      let oscHeight: CGFloat = 67
      let yMargin: CGFloat = 25

      if yPos < 0 {
        yPos = 0
      } else if yPos + oscHeight + yMargin > windowHeight {
        yPos = windowHeight - oscHeight - yMargin
      }

      oscFloatingView.xConstraint.constant = xPos
      oscFloatingView.yConstraint.constant = yPos
    }

    // Detach the views in oscFloatingTopView manually on macOS 11 only; as it will cause freeze
    if isMacOS11 && oscPosition == .floating {
      guard let maxWidth = [fragVolumeView, fragToolbarView].compactMap({ $0?.frame.width }).max() else {
        return
      }

      // window - 10 - controlBarFloating
      // controlBarFloating - 12 - oscFloatingTopView
      let margin: CGFloat = (10 + 12) * 2
      let hide = (window.frame.width
                    - fragControlView.frame.width
                    - maxWidth*2
                    - margin) < 0

      let views = oscFloatingView.oscTopView.views
      if hide {
        if views.contains(fragVolumeView)
            && views.contains(fragToolbarView) {
          oscFloatingView.oscTopView.removeView(fragVolumeView)
          oscFloatingView.oscTopView.removeView(fragToolbarView)
        }
      } else {
        if !views.contains(fragVolumeView)
            && !views.contains(fragToolbarView) {
          oscFloatingView.oscTopView.addView(fragVolumeView, in: .leading)
          oscFloatingView.oscTopView.addView(fragToolbarView, in: .trailing)
        }
      }
    }

    player.events.emit(.windowResized, data: window.frame)
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    videoView.videoLayer.inLiveResize = true
  }

  // resize framebuffer in videoView after resizing.
  func windowDidEndLiveResize(_ notification: Notification) {
    // Must not access mpv while it is asynchronously processing stop and quit commands.
    // See comments in windowWillExitFullScreen for details.
    guard player.info.state.active else { return }
    videoView.videoLayer.inLiveResize = false
    updateWindowParametersForMPV()
  }

  func windowDidChangeBackingProperties(_ notification: Notification) {
    if let oldScale = (notification.userInfo?[NSWindow.oldScaleFactorUserInfoKey] as? NSNumber)?.doubleValue,
      oldScale != Double(window!.backingScaleFactor) {
      videoView.videoLayer.contentsScale = window!.backingScaleFactor
    }
  }

  override func windowDidChangeScreen(_ notification: Notification) {
    super.windowDidChangeScreen(notification)

    player.events.emit(.windowScreenChanged)
  }

  // MARK: - Window delegate: Activeness status
  func windowDidMove(_ notification: Notification) {
    guard let window = window else { return }
    player.events.emit(.windowMoved, data: window.frame)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    window!.makeFirstResponder(window!)
    if Preference.bool(for: .pauseWhenInactive) && isPausedDueToInactive {
      player.resume()
      isPausedDueToInactive = false
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    // keyWindow is nil: The whole app is inactive
    // keyWindow is another MainWindow: Switched to another video window
    if NSApp.keyWindow == nil ||
      (NSApp.keyWindow?.windowController is MainWindowController ||
        (NSApp.keyWindow?.windowController is MiniPlayerWindowController && NSApp.keyWindow?.windowController != player.miniPlayer)) {
      if Preference.bool(for: .pauseWhenInactive), player.info.state == .playing {
        player.pause()
        isPausedDueToInactive = true
      }
    }
  }

  override func windowDidBecomeMain(_ notification: Notification) {
    super.windowDidBecomeMain(notification)

    if fsState.isFullscreen && Preference.bool(for: .blackOutMonitor) {
      blackOutOtherMonitors()
    }
    player.events.emit(.windowMainStatusChanged, data: true)
  }

  override func windowDidResignMain(_ notification: Notification) {
    super.windowDidResignMain(notification)
    if Preference.bool(for: .blackOutMonitor) {
      removeBlackWindow()
    }
    player.events.emit(.windowMainStatusChanged, data: false)
  }

  func windowWillMiniaturize(_ notification: Notification) {
    if Preference.bool(for: .pauseWhenMinimized), player.info.state == .playing {
      isPausedDueToMiniaturization = true
      player.pause()
    }
  }

  func windowDidMiniaturize(_ notification: Notification) {
    if Preference.bool(for: .togglePipByMinimizingWindow) && (!Preference.bool(for: .togglePipByMinimizingWindowForVideoOnly) ||  player.info.isAudio == .notAudio) && !isWindowMiniaturizedDueToPip {
      enterPIP()
    }
    player.events.emit(.windowMiniaturized)
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    if Preference.bool(for: .pauseWhenMinimized) && isPausedDueToMiniaturization {
      player.resume()
      isPausedDueToMiniaturization = false
    }
    if Preference.bool(for: .togglePipByMinimizingWindow) && (!Preference.bool(for: .togglePipByMinimizingWindowForVideoOnly) ||  player.info.isAudio == .notAudio) && !isWindowMiniaturizedDueToPip {
      exitPIP()
    }
    player.events.emit(.windowDeminiaturized)
  }

  // MARK: - UI: Show / Hide

  @objc func hideUIAndCursor() {
    // don't hide UI when dragging control bar
    if oscFloatingView.isDragging { return }
    hideUI()
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  private func hideUI(force: Bool = false) {
    // Don't hide UI when in PIP
    guard pipStatus == .notInPIP || animationState == .hidden else {
      return
    }
    // Don't hide UI when auto hide control bar is disabled
    guard force || Preference.bool(for: .enableControlBarAutoHide) else { return }

    animationState = .willHide
    player.refreshSyncUITimer()
    fadeableViews.forEach { (v) in
      v.isHidden = false
    }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = AccessibilityPreferences.adjustedDuration(UIAnimationDuration)
      fadeableViews.forEach { (v) in
        v.animator().alphaValue = 0
      }
      if !self.fsState.isFullscreen {
        titleTextField?.animator().alphaValue = 0
      }
    }) {
      // if no interrupt then hide animation
      if self.animationState == .willHide {
        self.fadeableViews.forEach { (v) in
          if let btn = v as? NSButton, self.standardWindowButtons.contains(btn) {
            v.alphaValue = 1e-100
          } else {
            v.isHidden = true
          }
        }
        self.animationState = .hidden
      }
    }
  }

  private func showUI() {
    if player.disableUI { return }
    animationState = .willShow
    fadeableViews.forEach { (v) in
      v.isHidden = false
    }
    // The OSC may not have been updated while it was hidden to avoid wasting energy. Make sure it
    // is up to date.
    player.refreshSyncUITimer()
    standardWindowButtons.forEach { $0.isEnabled = true }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = AccessibilityPreferences.adjustedDuration(UIAnimationDuration)
      fadeableViews.forEach { (v) in
        v.animator().alphaValue = 1
      }
      if !fsState.isFullscreen {
        titleTextField?.animator().alphaValue = 1
      }
    }) {
      // if no interrupt then hide animation
      if self.animationState == .willShow {
        self.animationState = .shown
      }
    }
  }

  // MARK: - UI: Show / Hide Timer

  private func updateTimer() {
    destroyTimer()
    createTimer()
  }

  private func destroyTimer() {
    // if timer exist, destroy first
    if hideControlTimer != nil {
      hideControlTimer!.invalidate()
      hideControlTimer = nil
    }
  }

  private func createTimer() {
    // create new timer
    let timeout = Preference.float(for: .controlBarAutoHideTimeout)
    hideControlTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideUIAndCursor), userInfo: nil, repeats: false)
  }

  // MARK: - UI: Title

  @objc
  override func updateTitle() {
    if player.info.isNetworkResource {
      window?.representedURL = nil
      window?.title = player.getMediaTitle()
    } else {
      window?.representedURL = player.info.currentURL
      // Workaround for issue #3543, IINA crashes reporting:
      // NSInvalidArgumentException [NSNextStepFrame _displayName]: unrecognized selector
      // When running on an M1 under Big Sur and using legacy full screen.
      //
      // Changes in Big Sur broke the legacy full screen feature. The MainWindowController method
      // legacyAnimateToFullscreen had to be changed to get this feature working again. Under
      // Big Sur that method now calls "window.styleMask.remove(.titled)". Removing titled from the
      // style mask causes the AppKit method NSWindow.setTitleWithRepresentedFilename to trigger the
      // exception listed above. This appears to be a defect in the Cocoa framework. The window's
      // title can still be set directly without triggering the exception. The problem seems to be
      // isolated to the setTitleWithRepresentedFilename method, possibly only when running on an
      // Apple Silicon based Mac. Based on the Apple documentation setTitleWithRepresentedFilename
      // appears to be a convenience method. As a workaround for the issue directly set the window
      // title.
      //
      // This problem has been reported to Apple as:
      // "setTitleWithRepresentedFilename throws NSInvalidArgumentException: NSNextStepFrame _displayName"
      // Feedback number FB9789129
      if Preference.bool(for: .useLegacyFullScreen) {
        window?.title = player.info.currentURL?.lastPathComponent ?? ""
      } else {
        window?.setTitleWithRepresentedFilename(player.info.currentURL?.path ?? "")
      }
    }
    titleBarView?.updateTitle()

    // Sometimes the doc icon may not be available, eg. when opened an online video.
    // We should try to add it every time when window title changed.
    if let docIcon = window?.standardWindowButton(.documentIconButton) {
      fadeableViews.add(docIcon) { [unowned self] in
        fsState == .windowed ? .auto : .alwaysShown
      }
    }
  }

  // MARK: - UI: OSD

  /// Show a message in the on screen display.
  /// - Parameters:
  ///   - message: The `OSDMessage` to display.
  ///   - autoHide: If `true` (the default) the message will be hidden after a timeout.
  ///   - forcedTimeout: Timeout after which the message will be hidden (overrides user configured timeout).
  ///   - accessoryView: Custom view to display (if not supplied normal OSD views are used).
  ///   - context: Additional information associated with the message.
  /// - Attention: Do not call `displayOSD` directly, call `PlayerCore.sendOSD` instead.
  /// - Important: As per Apple's [Internationalization and Localization Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/SupportingRight-To-LeftLanguages/SupportingRight-To-LeftLanguages.html)
  ///     timeline indicators should not flip in a right-to-left language. Thus OSD messages referencing a position within the video
  ///     must always use a left to right layout.
  func displayOSD(_ message: OSDMessage, autoHide: Bool = true, forcedTimeout: Float? = nil, accessoryView: NSView? = nil, context: Any? = nil) {
    guard player.displayOSD || message.alwaysEnabled, !isShowingPersistentOSD else { return }

    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    if osdAnimationState != .shown {
      osdAnimationState = .shown  /// set this before calling `refreshSyncUITimer()`
      player.refreshSyncUITimer()
    } else {
      osdAnimationState = .shown
    }

    osdView.updateViews(fromMessage: message, player: player)

    osdView.alphaValue = 1
    osdView.isHidden = false
    osdView.layoutSubtreeIfNeeded()

    if let accessoryView = accessoryView {
      isShowingPersistentOSD = true
      if context != nil {
        osdContext = context
      }

      let heightConstraint = NSLayoutConstraint(item: accessoryView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 300)
      heightConstraint.priority = .defaultLow
      heightConstraint.isActive = true

      osdView.addAccessoryView(accessoryView)

      // enlarge window if too small
      let winFrame = window!.frame
      var newFrame = winFrame
      if (winFrame.height < 300) {
        newFrame = winFrame.centeredResize(to: winFrame.size.satisfyMinSizeWithSameAspectRatio(NSSize(width: 500, height: 300)))
      }

      accessoryView.wantsLayer = true
      accessoryView.layer?.opacity = 0

      NSAnimationContext.runAnimationGroup({ context in
        context.duration = AccessibilityPreferences.adjustedDuration(0.3)
        context.allowsImplicitAnimation = true
        window!.setFrame(newFrame, display: true)
        osdView.layoutSubtreeIfNeeded()
      }, completionHandler: {
        accessoryView.layer?.opacity = 1
      })
    }

    if autoHide {
      let timeout = forcedTimeout ?? Preference.float(for: .osdAutoHideTimeout)
      hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
    }
  }

  @objc
  func hideOSD() {
    NSAnimationContext.runAnimationGroup({ (context) in
      self.osdAnimationState = .willHide
      context.duration = OSDAnimationDuration
      osdView.animator().alphaValue = 0
    }) {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
        self.osdView.isHidden = true
        self.osdView.removeAccessoryView()
      }
    }
    isShowingPersistentOSD = false
    osdContext = nil
    player.refreshSyncUITimer()
  }

  private func setConstraintsForVideoView(_ constraints: [NSLayoutConstraint.Attribute: CGFloat]) {
    for (attr, value) in constraints {
      videoViewConstraints[attr]?.constant = value
    }
  }

  // MARK: - UI: Interactive mode

  func enterInteractiveMode(_ mode: InteractiveMode, selectWholeVideoByDefault: Bool = false) {
    // prerequisites
    guard !isInInteractiveMode, let window = window else { return }

    let (ow, oh) = player.originalVideoSize
    guard ow != 0 && oh != 0 else {
      Utility.showAlert("no_video_track")
      return
    }

    window.backgroundColor = .windowBackgroundColor
    standardWindowButtons.forEach { $0.isEnabled = false }

    isPausedPriorToInteractiveMode = player.info.state == .paused
    player.pause()
    isInInteractiveMode = true
    hideUI(force: true)

    if fsState.isFullscreen {
      let aspect: NSSize
      if window.aspectRatio == .zero {
        let dsize = player.videoSizeForDisplay
        aspect = NSSize(width: dsize.0, height: dsize.1)
      } else {
        aspect = window.aspectRatio
      }
      let frame = aspect.shrink(toSize: window.frame.size).centeredRect(in: window.frame)
      setConstraintsForVideoView([
        .left: frame.minX,
        .right: window.frame.width - frame.maxX,  // `frame.x` should also work
        .bottom: -frame.minY,
        .top: window.frame.height - frame.maxY  // `frame.y` should also work
      ])
      videoView.needsLayout = true
      videoView.layoutSubtreeIfNeeded()
      // force rerender a frame
      forceDraw("interactive cropping")
    }

    let controlView = mode.viewController()
    controlView.mainWindow = self
    bottomView.isHidden = false
    bottomView.addSubview(controlView.view)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": controlView.view])

    let origVideoSize = NSSize(width: ow, height: oh)
    // the max region that the video view can occupy
    let newVideoViewBounds = NSRect(x: 20, y: 20 + 60, width: window.frame.width - 40, height: window.frame.height - 104)
    let newVideoViewSize = origVideoSize.shrink(toSize: newVideoViewBounds.size)
    let newVideoViewFrame = newVideoViewBounds.centeredResize(to: newVideoViewSize)

    let newConstants: [NSLayoutConstraint.Attribute: CGFloat] = [
      .left: newVideoViewFrame.minX,
      .right: newVideoViewFrame.maxX - window.frame.width,
      .bottom: -newVideoViewFrame.minY,
      .top: window.frame.height - newVideoViewFrame.maxY
    ]

    let selectedRect: NSRect = selectWholeVideoByDefault ? NSRect(origin: .zero, size: origVideoSize) : .zero

    // add crop setting view
    videoView.addSubview(controlView.cropBoxView)
    controlView.cropBoxView.isHidden = true
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": controlView.cropBoxView])
    controlView.cropBoxView.selectedRect = selectedRect
    controlView.cropBoxView.actualSize = origVideoSize
    controlView.cropBoxView.updateCursorRects()

    self.cropSettingsView = controlView

    // show crop settings view
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = AccessibilityPreferences.adjustedDuration(CropAnimationDuration)
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      bottomBarBottomConstraint.animator().constant = 0
      layoutSides.forEach { attr in
        videoViewConstraints[attr]!.animator().constant = newConstants[attr]!
      }
    }) {
      self.videoView.layer?.shadowColor = .black
      self.videoView.layer?.shadowOpacity = 1
      self.videoView.layer?.shadowOffset = .zero
      self.videoView.layer?.shadowRadius = 3
      self.cropSettingsView?.cropBoxView.resized()
      self.cropSettingsView?.cropBoxView.isHidden = false
      self.forceDraw("interactive cropping")
    }
  }

  func exitInteractiveMode(immediately: Bool = false, then: @escaping () -> Void = {}) {
    window?.backgroundColor = .black
    standardWindowButtons.forEach { $0.isEnabled = true }

    if let constraint = aspectRatioConstraintForInteractiveMode {
      constraint.isActive = false
      aspectRatioConstraintForInteractiveMode = nil
    }

    if !isPausedPriorToInteractiveMode {
      player.resume()
    }
    isInInteractiveMode = false
    cropSettingsView?.cropBoxView.isHidden = true

    // if exit without animation
    if immediately {
      bottomBarBottomConstraint.constant = -InteractiveModeBottomViewHeight
      layoutSides.forEach { attr in
        videoViewConstraints[attr]!.constant = 0
      }
      self.cropSettingsView?.cropBoxView.removeFromSuperview()
      self.sidebars.leadingSidebar.status = .hidden
      self.sidebars.trailingSidebar.status = .hidden
      self.bottomView.subviews.removeAll()
      self.bottomView.isHidden = true
      return
    }

    // if with animation
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = AccessibilityPreferences.adjustedDuration(CropAnimationDuration)
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      bottomBarBottomConstraint.animator().constant = -InteractiveModeBottomViewHeight
      layoutSides.forEach { attr in
        videoViewConstraints[attr]!.animator().constant = 0
      }
    }) {
      self.cropSettingsView?.cropBoxView.removeFromSuperview()
      self.sidebars.leadingSidebar.status = .hidden
      self.sidebars.trailingSidebar.status = .hidden
      self.bottomView.subviews.removeAll()
      self.bottomView.isHidden = true
      self.showUI()
      then()
    }
  }

  private func refreshSeekTimeAndThumbnail(from event: NSEvent) {
    let isCoveredByOSD = !osdView.isHidden && event.inAnyOf([osdView])
    let isCoveredBySidebar = sidebars.isEventCoveringVisibleSidebar(event)
    if isMouseInSlider, !isCoveredByOSD, !isCoveredBySidebar {
      updateTimePreviewAndThumbnail(event.locationInWindow)
    } else {
      thumbnailPeekView.isHidden = true
      timePreviewView.isHidden = true
    }
  }

  /// Determine if the thumbnail preview can be shown above the progress bar in the on screen controller..
  ///
  /// Normally the OSC's thumbnail preview is shown above the time preview. This is the preferred location. However the
  /// thumbnail preview extends beyond the frame of the OSC. If the OSC is near the top of the window this could result
  /// in the thumbnail extending outside of the window resulting in clipping. This method checks if there is room for the
  /// thumbnail to fully fit in the window. Otherwise the thumbnail must be displayed below the OSC's progress bar.
  /// - Parameters:
  ///   - timePreviewYPos: The y-coordinate of the time preview `TextField`.
  ///   - thumbnailHeight: The height of the thumbnail.
  /// - Returns: `true` if the thumbnail can be shown above the slider, `false` otherwise.
  private func canShowThumbnailAbove(timePreviewYPos: Double, thumbnailHeight: Double) -> Bool {
    guard oscPosition != .bottom else { return true }
    guard oscPosition != .top else { return false }
    // The layout preference for the on screen controller is set to the default floating layout.
    // Must insure the top of the thumbnail would be below the top of the window.
    let topOfThumbnail = timePreviewYPos + timePreviewView.frame.height + thumbnailHeight
    // Normally the height of the usable area of the window can be obtained from the content
    // layout. But when the legacy full screen preference is enabled the layout height may be
    // larger than the content view if the display contains a camera housing. Use the lower of
    // the two heights.
    let windowContentHeight = min(window!.contentLayoutRect.height, window!.contentView!.frame.height)
    return topOfThumbnail <= windowContentHeight
  }

  // MARK: - UI: Window size / aspect

  private var currentWindowAspectRatio: NSSize {
    guard let window else { return .zero }
    return Preference.unlockWindowAspectRatio ? window.frame.size : window.aspectRatio
  }

  private func setWindowAspectRatio(_ aspectRatio: NSSize) {
    guard let window else { return }
    if Preference.unlockWindowAspectRatio {
      window.aspectRatio = .zero
      window.resizeIncrements = .init(width: 1, height: 1)
    } else {
      window.aspectRatio = aspectRatio
    }
  }

  /// Calculate the window frame from a parsed struct of mpv's `geometry` option.
  func windowFrameFromGeometry(newSize: NSSize? = nil, screen: NSScreen? = nil) -> NSRect? {
    guard let geometry = cachedGeometry ?? player.getGeometry(),
      let screenFrame = (screen ?? window?.screen)?.visibleFrame else { return nil }

    cachedGeometry = geometry
    var winFrame = window!.frame
    if let ns = newSize {
      winFrame.size.width = ns.width
      winFrame.size.height = ns.height
    }
    let winAspect = winFrame.size.aspect
    var widthOrHeightIsSet = false
    // w and h can't take effect at same time
    if let strw = geometry.w, strw != "0" {
      var w: CGFloat
      if strw.hasSuffix("%") {
        w = CGFloat(Double(String(strw.dropLast()))! * 0.01 * Double(screenFrame.width))
      } else {
        w = CGFloat(Int(strw)!)
      }
      w = max(AppData.mainWindowMinSize.width, w)
      winFrame.size.width = w
      winFrame.size.height = w / winAspect
      widthOrHeightIsSet = true
    } else if let strh = geometry.h, strh != "0" {
      var h: CGFloat
      if strh.hasSuffix("%") {
        h = CGFloat(Double(String(strh.dropLast()))! * 0.01 * Double(screenFrame.height))
      } else {
        h = CGFloat(Int(strh)!)
      }
      h = max(AppData.mainWindowMinSize.height, h)
      winFrame.size.height = h
      winFrame.size.width = h * winAspect
      widthOrHeightIsSet = true
    }
    // x, origin is window center
    if let strx = geometry.x, let xSign = geometry.xSign {
      let x: CGFloat
      if strx.hasSuffix("%") {
        x = CGFloat(Double(String(strx.dropLast()))! * 0.01 * Double(screenFrame.width)) - winFrame.width / 2
      } else {
        x = CGFloat(Int(strx)!)
      }
      winFrame.origin.x = xSign == "+" ? x : screenFrame.width - x
      // if xSign equals "-", need set right border as origin
      if (xSign == "-") {
        winFrame.origin.x -= winFrame.width
      }
    }
    // y
    if let stry = geometry.y, let ySign = geometry.ySign {
      let y: CGFloat
      if stry.hasSuffix("%") {
        y = CGFloat(Double(String(stry.dropLast()))! * 0.01 * Double(screenFrame.height)) - winFrame.height / 2
      } else {
        y = CGFloat(Int(stry)!)
      }
      winFrame.origin.y = ySign == "+" ? y : screenFrame.height - y
      if (ySign == "-") {
        winFrame.origin.y -= winFrame.height
      }
    }
    // if x and y are not specified
    if geometry.x == nil && geometry.y == nil && widthOrHeightIsSet {
      winFrame.origin.x = (screenFrame.width - winFrame.width) / 2
      winFrame.origin.y = (screenFrame.height - winFrame.height) / 2
    }
    // if the screen has offset
    winFrame.origin.x += screenFrame.origin.x
    winFrame.origin.y += screenFrame.origin.y

    return winFrame
  }

  /// Determine the screen to use for the window.
  /// - Parameter window: Window to determine the screen for.
  /// - Returns: Screen to use for the given window.
  private func determineScreenToUse(_ window: NSWindow) -> NSScreen {
    // If the window is currently showing on a screen, use this screen
    if window.isOnActiveSpace, let currentScreen = window.screen {
      NSScreen.log("Window is currently showing screen", currentScreen)
      return currentScreen
    }
    guard let rectString = UserDefaults.standard.value(forKey: "MainWindowLastPosition") as? String else {
      let selected = window.selectDefaultScreen()
      NSScreen.log("MainWindowLastPosition not found, using default screen", selected)
      return selected
    }
    let rect = NSRectFromString(rectString)
    guard let lastScreen = NSScreen.screens.first(where: { NSPointInRect(rect.origin, $0.frame) }) else {
      // The previous window origin is not on any screen. Could be an external screen is no longer
      // connected or the arrangement of the screens has changed.
      let selected = window.selectDefaultScreen()
      NSScreen.log("MainWindowLastPosition \(rect.origin) is not within any screens, using default screen",
                   selected)
      return selected
    }
    // Found a screen containing the previous window origin. Use that screen for the window.
    NSScreen.log("MainWindowLastPosition \(rect.origin) matched", lastScreen)
    return lastScreen
  }

  override func handleVideoSizeChange() {
    handleVideoSizeChange(keepWindowSize: false)
  }

  /** Set window size when info available, or video size changed. */
  func handleVideoSizeChange(keepWindowSize: Bool) {
    guard let window = window else { return }

    // When starting to play the file try and find the screen the window was previously on.
    let screen = player.info.justStartedFile ? determineScreenToUse(window) : window.selectDefaultScreen()
    let screenRect = screen.visibleFrame
    let screenSize = screenRect.size

    let (width, height) = player.videoSizeForDisplay

    // set aspect ratio
    let originalVideoSize = NSSize(width: width, height: height)
    setWindowAspectRatio(originalVideoSize)
    pip.aspectRatio = originalVideoSize

    var rect: NSRect
    let needResizeWindow: Bool

    let frame = fsState.priorWindowedFrame ?? window.frame

    if player.info.justStartedFile {
      // Many settings can require the window to be resized/repositioned:
      // - Initial window size
      // - Initial window position
      // - Resize the window to fit video size
      // - Use physical resolution on Retina displays
      // - Direct use of the mpv geometry option
      let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
      switch resizeTiming {
      case .always:
        needResizeWindow = true
      case .onlyWhenOpen:
        needResizeWindow = player.info.justOpenedFile || shouldApplyInitialWindowSize
      case .never:
        needResizeWindow = shouldApplyInitialWindowSize
      }
    } else {
      // video size changed during playback
      needResizeWindow = !keepWindowSize
    }

    if needResizeWindow {
      log("Need to resize window")
      // get videoSize on screen
      var videoSize = originalVideoSize
      if Preference.bool(for: .usePhysicalResolution) {
        videoSize = window.convertFromBacking(
          NSMakeRect(window.frame.origin.x, window.frame.origin.y, CGFloat(width), CGFloat(height))).size
        if videoSize != originalVideoSize {
          log("""
            Adjusted size from \(originalVideoSize) to \(videoSize) based on physical \
            resolution of display
            """)
        }
      }
      let resizePreference = Preference.enum(for: .resizeWindowOption) as Preference.ResizeWindowOption
      if player.info.justStartedFile {
        let sizeBefore = videoSize
        if resizePreference == .fitScreen {
          videoSize = videoSize.shrink(toSize: screenSize)
          if sizeBefore != videoSize {
            log("Resized window to \(videoSize) to fit in screen")
          }
        } else {
          let resizeRatio = resizePreference.ratio
          videoSize = videoSize.multiply(CGFloat(resizeRatio))
          if sizeBefore != videoSize {
            log("Resized window to \(resizeRatio)x video size \(videoSize)")
          }
        }
      }
      // check screen size
      videoSize = videoSize.satisfyMaxSizeWithSameAspectRatio(screenSize)
      // guard min size
      // must be slightly larger than the min size, or it will crash when the min size is auto saved as window frame size.
      videoSize = videoSize.satisfyMinSizeWithSameAspectRatio(AppData.mainWindowMinSize)
      if shouldApplyInitialWindowSize {
        // check if have geometry set (initial window position/size)
        if let wfg = windowFrameFromGeometry(newSize: videoSize, screen: screen) {
          rect = wfg
          log("Adjusted window frame based on geometry option: \(rect)")
        } else {
          rect = videoSize.centeredRect(in: screenRect)
          log("Centered window in screen: \(rect)")
        }
      } else if player.info.justStartedFile, resizePreference == .fitScreen {
        rect = screenRect.centeredResize(to: videoSize)
        log("Centered window in screen and resized: \(rect)")
      } else {
        rect = frame.centeredResize(to: videoSize)
        log("Resized window preserving centering: \(rect)")
      }
    } else if shouldApplyInitialWindowSize {
      rect = originalVideoSize.centeredRect(in: screenRect)
      log("Centered original sized window in screen: \(rect)")
    } else {
      // user is navigating in playlist. remain same window area.
      rect = frame.areaPreservingResized(newWidth: CGFloat(width), height: CGFloat(height))
      log("Adjusted height of window preserving area: \(rect)")
    }

    shouldApplyInitialWindowSize = false

    let rectBefore = rect
    rect = rect.constrain(in: screenRect)
    if rectBefore != rect {
      log("Constrained window frame to be in screen: \(rect)")
    }

    if Preference.unlockWindowAspectRatio && !player.info.justOpenedFile {
      // do nothing when window aspect ratio is unlocked
      // however, if this is the first time opening the window, still apply the sizing logic
    } else if fsState.isFullscreen {
      log("In full screen mode, setting prior window frame")
      fsState.priorWindowedFrame = rect
    } else {
      log("Setting window frame to: \(rect)")
      if player.disableWindowAnimation || Preference.bool(for: .disableAnimations) || !window.isVisible {
        window.setFrame(rect, display: true, animate: false)
      } else {
        // animated `setFrame` can be inaccurate!
        window.setFrame(rect, display: true, animate: true)
        window.setFrame(rect, display: true)
      }
      updateWindowParametersForMPV(withFrame: rect)
    }

    // generate thumbnails after video loaded if it's the first time
    if !isVideoLoaded {
      player.generateThumbnails()
      isVideoLoaded = true
    }

    // UI and slider
    updatePlayTime(withDuration: true, andProgressBar: true)
    player.events.emit(.windowSizeAdjusted, data: rect)
  }

  func updateWindowParametersForMPV(withFrame frame: NSRect? = nil) {
    guard let window = self.window else { return }
    if let videoWidth = player.info.videoWidth {
      let windowScale = Double((frame ?? window.frame).width) / Double(videoWidth)
      player.info.cachedWindowScale = windowScale
      player.mpv.setDouble(MPVProperty.windowScale, windowScale, level: .verbose)
    }
  }

  func setWindowScale(_ scale: Double) {
    guard let window = window, fsState == .windowed else { return }
    let screenFrame = (window.screen ?? NSScreen.main!).visibleFrame
    let (videoWidth, videoHeight) = player.videoSizeForDisplay
    let newFrame: NSRect
    // calculate 1x size
    let useRetinaSize = Preference.bool(for: .usePhysicalResolution)
    let logicalFrame = NSRect(x: window.frame.origin.x,
                             y: window.frame.origin.y,
                             width: CGFloat(videoWidth),
                             height: CGFloat(videoHeight))
    var finalSize = (useRetinaSize ? window.convertFromBacking(logicalFrame) : logicalFrame).size
    // calculate scaled size
    let scalef = CGFloat(scale)
    finalSize.width *= scalef
    finalSize.height *= scalef
    // set size
    if finalSize.width > screenFrame.size.width || finalSize.height > screenFrame.size.height {
      // if final size is bigger than screen
      newFrame = window.frame.centeredResize(to: window.frame.size.shrink(toSize: screenFrame.size)).constrain(in: screenFrame)
    } else {
      // otherwise, resize the window normally
      newFrame = window.frame.centeredResize(to: finalSize.satisfyMinSizeWithSameAspectRatio(AppData.mainWindowMinSize)).constrain(in: screenFrame)
    }
    window.setFrame(newFrame, display: true, animate: true)
    MemoryUsage.shared.logUsage("after window scale changed (\(newFrame.width)x\(newFrame.height))")
  }

  // MARK: - UI: Others

  private func blackOutOtherMonitors() {
    screens = NSScreen.screens.filter { $0 != window?.screen }

    for window in blackWindows {
      window.orderOut(self)
    }
    blackWindows = []

    for screen in screens {
      var screenRect = screen.frame
      screenRect.origin = CGPoint(x: 0, y: 0)
      let blackWindow = NSWindow(contentRect: screenRect, styleMask: [], backing: .buffered, defer: false, screen: screen)
      blackWindow.backgroundColor = .black
      blackWindow.level = .iinaBlackScreen

      blackWindows.append(blackWindow)
      blackWindow.orderFront(self)
    }
  }

  private func removeBlackWindow() {
    for window in blackWindows {
      window.orderOut(self)
    }
    blackWindows = []
  }

  override func setWindowFloatingOnTop(_ onTop: Bool, updateOnTopStatus: Bool = true) {
    guard !fsState.isFullscreen else { return }
    super.setWindowFloatingOnTop(onTop, updateOnTopStatus: updateOnTopStatus)

    resetCollectionBehavior()
    // don't know why they will be disabled
    standardWindowButtons.forEach { $0.isEnabled = true }
  }

  // MARK: - Sync UI with playback

  func isUITimerNeeded() -> Bool {
    let isShowingFadeableViews = animationState == .shown || animationState == .willShow
    let isShowingOSD = osdAnimationState == .shown || osdAnimationState == .willShow
    return isShowingFadeableViews || isShowingOSD
  }

  override func updatePlayTime(withDuration duration: Bool, andProgressBar: Bool) {
    super.updatePlayTime(withDuration: duration, andProgressBar: andProgressBar)

    if osdAnimationState == .shown, let osdLastMessage = self.osdLastMessage {
      let message: OSDMessage
      switch osdLastMessage {
      case .pause, .resume:
        message = osdLastMessage
      case .seek(_, _):
        let osdText = (player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder) + " / " +
        (player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder)
        let percentage = (player.info.videoPosition / player.info.videoDuration) ?? 1
        message = .seek(osdText, percentage)
      default:
        return
      }

      self.osdLastMessage = message
      osdView.updateViews(fromMessage: message, player: player)
    }
  }

  override func updatePlayButtonState(paused: Bool) {
    super.updatePlayButtonState(paused: paused)
    if paused {
      speedValueIndex = AppData.availableSpeedValues.count / 2
    }
  }

  /// Configure the OSC arrow buttons based on IINA's `Use left/right button for` setting.
  ///
  /// For most settings the button is configured to be a
  /// [momentaryPushIn](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/momentarypushin)
  /// button. However if the button is set to control playback speed the button is configured to be a
  /// [multiLevelAccelerator](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/multilevelaccelerator)
  /// button. This allows the user to control the speed using pressure when using devices that support pressure sensitivity.
  func updateArrowButtons() {
    if arrowBtnFunction == .playlist {
      leftArrowButton.image = #imageLiteral(resourceName: "nextl")
      rightArrowButton.image = #imageLiteral(resourceName: "nextr")
    } else {
      leftArrowButton.image = #imageLiteral(resourceName: "speedl")
      rightArrowButton.image = #imageLiteral(resourceName: "speed")
    }
    if arrowBtnFunction == .speed {
      leftArrowButton.setButtonType(.multiLevelAccelerator)
      rightArrowButton.setButtonType(.multiLevelAccelerator)
    } else {
      leftArrowButton.setButtonType(.momentaryPushIn)
      rightArrowButton.setButtonType(.momentaryPushIn)
    }
  }

  override func updateVolume() {
    guard loaded else { return }
    super.updateVolume()
    guard !player.info.isMuted else { return }
    muteButton.image = volumeIcon()
  }

  // MARK: - IBActions

  @IBAction override func playButtonAction(_ sender: NSButton) {
    super.playButtonAction(sender)
    if player.info.state == .paused {
      // speed is already reset by playerCore
      speedValueIndex = AppData.availableSpeedValues.count / 2
      // set speed to 0 if is fastforwarding
      if isFastforwarding {
        player.setSpeed(1)
        isFastforwarding = false
      }
    }
  }

  @IBAction override func muteButtonAction(_ sender: NSButton) {
    super.muteButtonAction(sender)
    player.sendOSD(player.info.isMuted ? .mute : .unMute)
  }

  /// User has triggered the left button in the OSC.
  ///
  /// The behavior of the button depends upon the `Use left/right button for` setting found in the
  /// `On Screen Controller` section on the `UI` tab of IINA's settings. For most settings the button is configured to be a
  /// [momentaryPushIn](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/momentarypushin)
  /// button. However if the button is set to control playback speed the button is configured to be a
  /// [multiLevelAccelerator](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/multilevelaccelerator)
  /// button. This allows the user to control the speed using pressure when using devices that support pressure sensitivity.
  /// - Parameter sender: The button invoking this action.
  @IBAction func leftButtonAction(_ sender: NSButton) {
    switch arrowBtnFunction {
    case .playlist, .seek:
      arrowButtonAction(left: true)
    case .speed:
      let speeds = AppData.availableSpeedValues.count
      // If fast forwarding change speed to 1x
      if speedValueIndex > speeds / 2 {
        speedValueIndex = speeds / 2
      }

      if sender.intValue == 0 { // Released
        if maxPressure == 1 &&
          (speedValueIndex < speeds / 2 - 1 ||
          Date().timeIntervalSince(lastClick) < minimumPressDuration) { // Single click ended, 2x speed
          speedValueIndex = oldIndex - 1
        } else { // Force Touch or long press ended
          speedValueIndex = speeds / 2
        }
        maxPressure = 0
      } else {
        if sender.intValue == 1 && maxPressure == 0 { // First press
          oldIndex = speedValueIndex
          speedValueIndex -= 1
          lastClick = Date()
        } else { // Force Touch
          speedValueIndex = max(oldIndex - Int(sender.intValue), 0)
        }
        maxPressure = max(maxPressure, sender.intValue)
      }
      arrowButtonAction(left: true)
    }
  }

  /// User has triggered the right button in the OSC.
  ///
  /// The behavior of the button depends upon the `Use left/right button for` setting found in the
  /// `On Screen Controller` section on the `UI` tab of IINA's settings. For most settings the button is configured to be a
  /// [momentaryPushIn](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/momentarypushin)
  /// button. However if the button is set to control playback speed the button is configured to be a
  /// [multiLevelAccelerator](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/multilevelaccelerator)
  /// button. This allows the user to control the speed using pressure when using devices that support pressure sensitivity.
  /// - Parameter sender: The button invoking this action.
  @IBAction func rightButtonAction(_ sender: NSButton) {
    switch arrowBtnFunction {
    case .playlist, .seek:
      arrowButtonAction(left: false)
    case .speed:
      let speeds = AppData.availableSpeedValues.count
      // If rewinding change speed to 1x
      if speedValueIndex < speeds / 2 {
        speedValueIndex = speeds / 2
      }

      if sender.intValue == 0 { // Released
        if maxPressure == 1 &&
          (speedValueIndex > speeds / 2 + 1 ||
          Date().timeIntervalSince(lastClick) < minimumPressDuration) { // Single click ended
          speedValueIndex = oldIndex + 1
        } else { // Force Touch or long press ended
          speedValueIndex = speeds / 2
        }
        maxPressure = 0
      } else {
        if sender.intValue == 1 && maxPressure == 0 { // First press
          oldIndex = speedValueIndex
          speedValueIndex += 1
          lastClick = Date()
        } else { // Force Touch
          speedValueIndex = min(oldIndex + Int(sender.intValue), speeds - 1)
        }
        maxPressure = max(maxPressure, sender.intValue)
      }
      arrowButtonAction(left: false)
    }
  }

  /** handle action of both left and right arrow button */
  func arrowButtonAction(left: Bool) {
    switch arrowBtnFunction {
    case .speed:
      isFastforwarding = true
      let speedValue = AppData.availableSpeedValues[speedValueIndex]
      player.setSpeed(speedValue)
      // if is paused
      if player.info.state == .paused {
        player.resume()
      }

    case .playlist:
      player.navigateInPlaylist(nextMedia: !left)

    case .seek:
      player.seek(relativeSecond: left ? -10 : 10, option: .relative)

    }
  }

  func updateSpeedLabel(speed: Double) {
    if (speed == 1) {
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = true
    } else if speed < 1 {
      leftArrowLabel.isHidden = false
      rightArrowLabel.isHidden = true
      leftArrowLabel.stringValue = String(format: "%.2fx", speed)
    } else if speed > 1 {
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = false
      let fmt = NumberFormatter()
      fmt.numberStyle = .decimal
      fmt.maximumSignificantDigits = 3
      rightArrowLabel.stringValue = fmt.string(for: speed)! + "x"
    }
  }

  @objc func ontopButtonAction(_ sender: NSButton) {
    setWindowFloatingOnTop(!isOntop)
  }

  /** When slider changes */
  @IBAction override func playSliderChanges(_ sender: NSSlider) {
    // guard let event = NSApp.currentEvent else { return }
    guard player.info.state.active, player.info.state != .loading else { return }
    super.playSliderChanges(sender)

    updateTimePreview(sender.doubleValue / sender.maxValue)
  }

  @objc func toolBarButtonAction(_ sender: NSButton) {
    guard let buttonType = Preference.ToolBarButton(rawValue: sender.tag) else { return }
    switch buttonType {
    case .fullScreen:
      toggleWindowFullScreen()
    case .musicMode:
      player.switchToMiniPlayer()
    case .pip:
      if pipStatus == .inPIP {
        exitPIP()
      } else if pipStatus == .notInPIP {
        enterPIP()
      }
    case .playlist:
      sidebars.showPlaylist()
    case .settings:
      sidebars.showSettings()
    case .subTrack:
      sidebars.quickSettingView.showSubChooseMenu(forView: sender, showLoadedSubs: true)
    case .screenshot:
      player.screenshot()
    case .plugins:
      sidebars.showPlugin(tab: nil)
    }
  }

  override func handleIINACommand(_ cmd: IINACommand) {
    super.handleIINACommand(cmd)
    switch cmd {
    case .toggleMusicMode:
      player.switchToMiniPlayer()
    default:
      break
    }
  }

  // MARK: - Time Preveiew & Thumbnail

  /** Display time label when mouse over slider */
  private func updateTimePreviewAndThumbnail(_ posInWindow: NSPoint) {
    guard let duration = player.info.videoDuration else {
      thumbnailPeekView.isHidden = true
      timePreviewView.isHidden = true
      return
    }

    let mouseXPos = playSlider.convert(posInWindow, from: nil).x
    let percentage = max(0, Double((mouseXPos - 3) / (playSlider.bounds.width - 6)))

    timePreviewView.isHidden = false
    let previewTime = duration * percentage
    updateTimePreview(percentage)
    let sliderFrameInWindow = playSlider.convert(playSlider.frame, to: nil)

    if player.info.thumbnailsReady, let image = player.info.getThumbnail(forSecond: previewTime.second)?.image {
      thumbnailPeekView.imageView.image = image.rotate(rotation)
      thumbnailPeekView.isHidden = false

      // In some formats (like most of Japanese TV video formats), display aspect ratios (DAR) are different from the
      // sample aspect ratio (SAR). A typical configuration is SAR 1440x1080i (4:3) w/ DAR 1920x1080 (16:9). We use video
      // display size to consider pixel formats as well as rotation from metadata properly display the thumbnail.
      let (videoWidth, videoHeight) = player.videoSizeForDisplay
      let displayAspectRatio = CGFloat(videoWidth) / CGFloat(videoHeight)

      let width = CGFloat(UserDefaults.standard.integer(forKey: "thumbnailWidth"))
      let height = round(width / displayAspectRatio)
      let showAbove = canShowThumbnailAbove(timePreviewYPos: timePreviewView.frame.origin.y, thumbnailHeight: height)
      let yPos = if showAbove {
        max(sliderFrameInWindow.maxY, timePreviewView.frame.maxY) + 5
      } else {
        min(sliderFrameInWindow.minY, timePreviewView.frame.minY) - height - 5
      }
      thumbnailPeekView.frame.size = NSSize(width: width, height: height)
      thumbnailPeekView.frame.origin = NSPoint(x: round(posInWindow.x - thumbnailPeekView.frame.width / 2), y: yPos)
    }
  }

  private func updateTimePreview(_ percentage: Double) {
    guard let duration = player.info.videoDuration else { return }
    let time = duration * percentage
    let chapterTitle = if let chapter = player.info.getChapter(forVideoTime: time) {
      chapter.title + "\n"
    } else {
      ""
    }
    timePreviewView.textField.stringValue = chapterTitle + time.stringRepresentation

    let sliderFrame = playSlider.convert(playSlider.bounds, to: nil)
    let timeLabelYPos: CGFloat
    if oscPosition == .top {
      timeLabelYPos = sliderFrame.origin.y - timePreviewView.bounds.height - 5
    } else {
      timeLabelYPos = sliderFrame.origin.y + playSlider.frame.height + 5
    }
    timePreviewView.frame.origin = CGPoint(
      x: round(sliderFrame.origin.x + sliderFrame.size.width * percentage - timePreviewView.frame.width / 2),
      y: timeLabelYPos)
  }


  // MARK: - Utility

  private func resetCollectionBehavior() {
    guard !fsState.isFullscreen else { return }
    if Preference.bool(for: .useLegacyFullScreen) {
      window?.collectionBehavior = [.managed, .fullScreenAuxiliary]
    } else {
      window?.collectionBehavior = [.managed, .fullScreenPrimary]
    }
  }

}

// MARK: - Picture in Picture

extension MainWindowController: PIPViewControllerDelegate {

  func enterPIP() {
    guard pipStatus != .inPIP else { return }
    pipStatus = .inPIP
    showUI()

    pipVideo = NSViewController()
    pipVideo.view = videoView
    pip.playing = player.info.state == .playing
    pip.title = window?.title

    pip.presentAsPicture(inPicture: pipVideo)
    pipOverlayView.isHidden = false

    if let window = self.window {
      let windowShouldDoNothing = window.styleMask.contains(.fullScreen) || window.isMiniaturized
      let pipBehavior = windowShouldDoNothing ? .doNothing : Preference.enum(for: .windowBehaviorWhenPip) as Preference.WindowBehaviorWhenPip
      switch pipBehavior {
      case .doNothing:
        break
      case .hide:
        isWindowHidden = true
        window.orderOut(self)
        break
      case .minimize:
        isWindowMiniaturizedDueToPip = true
        window.miniaturize(self)
        break
      }
      if Preference.bool(for: .pauseWhenPip) {
        player.pause()
      }
    }

    player.events.emit(.pipChanged, data: true)
    NotificationCenter.default.post(name: .iinaPIPStatusChanged, object: self, userInfo: ["enable": true])
  }

  func exitPIP() {
    guard pipStatus == .inPIP else { return }
    if pipShouldClose(pip) {
      // Prod Swift to pick the dismiss(_ viewController: NSViewController)
      // overload over dismiss(_ sender: Any?). A change in the way implicitly
      // unwrapped optionals are handled in Swift means that the wrong method
      // is chosen in this case. See https://bugs.swift.org/browse/SR-8956.
      pip.dismiss(pipVideo!)
    }
  }

  func doneExitingPIP() {
    if isWindowHidden {
      window?.makeKeyAndOrderFront(self)
    }

    pipStatus = .notInPIP

    addVideoViewToWindow()

    // Similarly, we need to run a redraw here as well. We check to make sure we are paused, because
    // this causes a janky animation in either case but as it's not necessary while the video is
    // playing and significantly more noticeable, we only redraw if we are paused. The forceDraw
    // method checks to make sure drawing is required.
    forceDraw("exiting PiP")

    updateTimer()

    isWindowMiniaturizedDueToPip = false
    isWindowHidden = false
    player.events.emit(.pipChanged, data: false)
    NotificationCenter.default.post(name: .iinaPIPStatusChanged, object: self, userInfo: ["enable": false])
  }

  func prepareForPIPClosure(_ pip: PIPViewController) {
    guard pipStatus == .inPIP else { return }
    guard let window = window else { return }
    // This is called right before we're about to close the PIP
    pipStatus = .intermediate

    // Hide the overlay view preemptively, to prevent any issues where it does
    // not hide in time and ends up covering the video view (which will be added
    // to the window under everything else, including the overlay).
    pipOverlayView.isHidden = true

    // Set frame to animate back to
    if fsState.isFullscreen {
      let newVideoSize = videoView.frame.size.shrink(toSize: window.frame.size)
      pip.replacementRect = newVideoSize.centeredRect(in: .init(origin: .zero, size: window.frame.size))
    } else {
      pip.replacementRect = window.contentView?.frame ?? .zero
    }
    pip.replacementWindow = window

    // Bring the window to the front and deminiaturize it
    NSApp.activate(ignoringOtherApps: true)
    window.deminiaturize(pip)
  }

  func pipWillClose(_ pip: PIPViewController) {
    prepareForPIPClosure(pip)
  }

  func pipShouldClose(_ pip: PIPViewController) -> Bool {
    prepareForPIPClosure(pip)
    return true
  }

  func pipDidClose(_ pip: PIPViewController) {
    doneExitingPIP()
  }

  func pipActionPlay(_ pip: PIPViewController) {
    player.resume()
  }

  func pipActionPause(_ pip: PIPViewController) {
    player.pause()
  }

  func pipActionStop(_ pip: PIPViewController) {
    // Stopping PIP pauses playback
    player.pause()
  }
}
