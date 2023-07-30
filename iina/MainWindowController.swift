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
  if #available(macOS 11.0, *) {
    if #unavailable(macOS 12.0) {
        return true
    }
  }
  return false
}()

fileprivate let TitleBarHeightNormal: CGFloat = {
  if #available(macOS 10.16, *) {
    return 28
  } else {
    return 22
  }
}()
fileprivate let TitleBarHeightWithOSC: CGFloat = TitleBarHeightNormal + 24 + 10
fileprivate let TitleBarHeightWithOSCInFullScreen: CGFloat = 24 + 10
fileprivate let OSCTopMainViewMarginTop: CGFloat = 26
fileprivate let OSCTopMainViewMarginTopInFullScreen: CGFloat = 6

fileprivate let SettingsWidth: CGFloat = 360
fileprivate let PlaylistMinWidth: CGFloat = 240
fileprivate let PlaylistMaxWidth: CGFloat = 400

fileprivate let InteractiveModeBottomViewHeight: CGFloat = 60

fileprivate let UIAnimationDuration = 0.25
fileprivate let OSDAnimationDuration = 0.5
fileprivate let SideBarAnimationDuration = 0.2
fileprivate let CropAnimationDuration = 0.2


fileprivate extension NSStackView.VisibilityPriority {
  static let detachEarly = NSStackView.VisibilityPriority(rawValue: 850)
  static let detachEarlier = NSStackView.VisibilityPriority(rawValue: 800)
  static let detachEarliest = NSStackView.VisibilityPriority(rawValue: 750)
}

// The minimum distance that the user must drag before their click or tap gesture is interpreted as a drag gesture:
fileprivate let minimumInitialDragDistance: CGFloat = 3.0

class MainWindowController: PlayerWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("MainWindowController")
  }

  @objc let monospacedFont: NSFont = {
    let fontSize = NSFont.systemFontSize(for: .small)
    return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }()

  // MARK: - Constants

  /** Minimum window size. */
  let minSize = NSMakeSize(285, 120)

  /** For Force Touch. */
  let minimumPressDuration: TimeInterval = 0.5

  // MARK: - Objects, Views

  override var videoView: VideoView {
    return _videoView
  }

  lazy private var _videoView: VideoView = VideoView(frame: window!.contentView!.bounds, player: player)

  /** The quick setting sidebar (video, audio, subtitles). */
  lazy var quickSettingView: QuickSettingViewController = {
    let quickSettingView = QuickSettingViewController()
    quickSettingView.mainWindow = self
    return quickSettingView
  }()

  /** The playlist and chapter sidebar. */
  lazy var playlistView: PlaylistViewController = {
    let playlistView = PlaylistViewController()
    playlistView.mainWindow = self
    return playlistView
  }()

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

  // MARK: - Status

  override var isOntop: Bool {
    didSet {
      updateOnTopIcon()
    }
  }

  /** For mpv's `geometry` option. We cache the parsed structure
   so never need to parse it every time. */
  var cachedGeometry: GeometryDef?

  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  var isResizingSidebar: Bool = false

  var pipStatus = PIPStatus.notInPIP
  var isInInteractiveMode: Bool = false
  var isVideoLoaded: Bool = false

  var shouldApplyInitialWindowSize = true
  var isWindowHidden: Bool = false
  var isWindowMiniaturizedDueToPip = false

  // might use another obj to handle slider?
  var isMouseInWindow: Bool = false
  var isMouseInSlider: Bool = false

  var isFastforwarding: Bool = false

  var isPausedDueToInactive: Bool = false
  var isPausedDueToMiniaturization: Bool = false
  var isPausedPriorToInteractiveMode: Bool = false

  var lastMagnification: CGFloat = 0.0

  /** Views that will show/hide when cursor moving in/out the window. */
  var fadeableViews: [NSView] = []

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

  private var isClosing = false

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
        } else{
          self = .windowed
        }
      }
    }
  }

  var fsState: FullScreenState = .windowed {
    didSet {
      // Must not access mpv while it is asynchronously processing stop and quit commands.
      guard !isClosing else { return }
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
  var sidebarAnimationState: UIAnimationState = .hidden

  // Sidebar

  /** Type of the view embedded in sidebar. */
  enum SideBarViewType {
    case hidden // indicating that sidebar is hidden. Should only be used by `sideBarStatus`
    case settings
    case playlist
    func width() -> CGFloat {
      switch self {
      case .settings:
        return SettingsWidth
      case .playlist:
        return CGFloat(Preference.integer(for: .playlistWidth)).clamped(to: PlaylistMinWidth...PlaylistMaxWidth)
      default:
        Logger.fatal("SideBarViewType.width shouldn't be called here")
      }
    }
  }

  var sideBarStatus: SideBarViewType = .hidden

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
    .alwaysShowOnTopIcon
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
        updateArrowButtonImage()
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
      }
    case PK.controlBarToolbarButtons.rawValue:
      if let newValue = change[.newKey] as? [Int] {
        setupOSCToolbarButtons(newValue.compactMap(Preference.ToolBarButton.init(rawValue:)))
      }
    case PK.alwaysShowOnTopIcon.rawValue:
      updateOnTopIcon()
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

  var titlebarAccesoryViewController: NSTitlebarAccessoryViewController!
  @IBOutlet var titlebarAccessoryView: NSView!

  /** Current OSC view. */
  var currentControlBar: NSView?

  @IBOutlet weak var sideBarRightConstraint: NSLayoutConstraint!
  @IBOutlet weak var sideBarWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var bottomBarBottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var titleBarHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var oscTopMainViewTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var fragControlViewMiddleButtons1Constraint: NSLayoutConstraint!
  @IBOutlet weak var fragControlViewMiddleButtons2Constraint: NSLayoutConstraint!

  @IBOutlet weak var titleBarView: NSVisualEffectView!
  @IBOutlet weak var titleBarBottomBorder: NSBox!
  @IBOutlet weak var titlebarOnTopButton: NSButton!

  @IBOutlet weak var controlBarFloating: ControlBarView!
  @IBOutlet weak var controlBarBottom: NSVisualEffectView!
  @IBOutlet weak var timePreviewWhenSeek: NSTextField!
  @IBOutlet weak var leftArrowButton: NSButton!
  @IBOutlet weak var rightArrowButton: NSButton!
  @IBOutlet weak var settingsButton: NSButton!
  @IBOutlet weak var playlistButton: NSButton!
  @IBOutlet weak var sideBarView: NSVisualEffectView!
  @IBOutlet weak var bottomView: NSView!
  @IBOutlet weak var bufferIndicatorView: NSVisualEffectView!
  @IBOutlet weak var bufferProgressLabel: NSTextField!
  @IBOutlet weak var bufferSpin: NSProgressIndicator!
  @IBOutlet weak var bufferDetailLabel: NSTextField!
  @IBOutlet var thumbnailPeekView: ThumbnailPeekView!
  @IBOutlet weak var additionalInfoView: NSVisualEffectView!
  @IBOutlet weak var additionalInfoLabel: NSTextField!
  @IBOutlet weak var additionalInfoStackView: NSStackView!
  @IBOutlet weak var additionalInfoTitle: NSTextField!
  @IBOutlet weak var additionalInfoBatteryView: NSView!
  @IBOutlet weak var additionalInfoBattery: NSTextField!

  @IBOutlet weak var oscFloatingTopView: NSStackView!
  @IBOutlet weak var oscFloatingBottomView: NSView!
  @IBOutlet weak var oscBottomMainView: NSStackView!
  @IBOutlet weak var oscTopMainView: NSStackView!

  @IBOutlet var fragControlView: NSStackView!
  @IBOutlet var fragToolbarView: NSStackView!
  @IBOutlet var fragVolumeView: NSView!
  @IBOutlet var fragSliderView: NSView!
  @IBOutlet var fragControlViewMiddleView: NSView!
  @IBOutlet var fragControlViewLeftView: NSView!
  @IBOutlet var fragControlViewRightView: NSView!

  @IBOutlet weak var leftArrowLabel: NSTextField!
  @IBOutlet weak var rightArrowLabel: NSTextField!

  @IBOutlet weak var osdVisualEffectView: NSVisualEffectView!
  @IBOutlet weak var osdStackView: NSStackView!
  @IBOutlet weak var osdLabel: NSTextField!
  @IBOutlet weak var osdAccessoryText: NSTextField!
  @IBOutlet weak var osdAccessoryProgress: NSProgressIndicator!

  @IBOutlet weak var pipOverlayView: NSVisualEffectView!

  lazy var pluginOverlayViewContainer: NSView! = {
    guard let window = window, let cv = window.contentView else { return nil }
    let view = NSView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(view, positioned: .below, relativeTo: bufferIndicatorView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": view])
    return view
  }()

  lazy var subPopoverView = playlistView.subPopover?.contentViewController?.view

  var videoViewConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]
  private var oscFloatingLeadingTrailingConstraint: [NSLayoutConstraint]?

  override var mouseActionDisabledViews: [NSView?] {[sideBarView, currentControlBar, titleBarView, subPopoverView]}

  // MARK: - PIP

  lazy var _pip: PIPViewController = {
    let pip = VideoPIPViewController()
    if #available(macOS 10.12, *) {
      pip.delegate = self
    }
    return pip
  }()
  
  @available(macOS 10.12, *)
  var pip: PIPViewController {
    _pip
  }

  var pipVideo: NSViewController!

  // MARK: - Initialization

  override func windowDidLoad() {
    super.windowDidLoad()

    guard let window = window else { return }

    window.styleMask.insert(.fullSizeContentView)

    // need to deal with control bar, so we handle it manually
    // w.isMovableByWindowBackground  = true

    // set background color to black
    window.backgroundColor = .black

    titleBarView.layerContentsRedrawPolicy = .onSetNeedsDisplay

    titlebarAccesoryViewController = NSTitlebarAccessoryViewController()
    titlebarAccesoryViewController.view = titlebarAccessoryView
    titlebarAccesoryViewController.layoutAttribute = .right
    window.addTitlebarAccessoryViewController(titlebarAccesoryViewController)
    updateOnTopIcon()

    // size
    window.minSize = minSize
    if let wf = windowFrameFromGeometry() {
      window.setFrame(wf, display: false)
    }

    window.aspectRatio = AppData.sizeWhenNoVideo

    // sidebar views
    sideBarView.isHidden = true

    // osc views
    fragControlView.addView(fragControlViewLeftView, in: .center)
    fragControlView.addView(fragControlViewMiddleView, in: .center)
    fragControlView.addView(fragControlViewRightView, in: .center)
    setupOnScreenController(withPosition: oscPosition)
    let buttons = (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    setupOSCToolbarButtons(buttons)

    updateArrowButtonImage()

    // fade-able views
    fadeableViews.append(contentsOf: standardWindowButtons as [NSView])
    fadeableViews.append(titleBarView)
    fadeableViews.append(titlebarAccessoryView)

    // video view
    guard let cv = window.contentView else { return }
    cv.autoresizesSubviews = false
    addVideoViewToWindow()
    window.setIsVisible(true)

    // gesture recognizer
    cv.addGestureRecognizer(magnificationGestureRecognizer)

    // Work around a bug in macOS Ventura where HDR content becomes dimmed when playing in full
    // screen mode once overlaying views are fully hidden (issue #3844). After applying this
    // workaround another bug in Ventura where an external monitor goes black could not be
    // reproduced (issue #4015). The workaround adds a tiny subview with such a low alpha level it
    // is invisible to the human eye. This workaround may not be effective in all cases.
    if #available(macOS 13, *) {
      let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 0.1, height: 0.1)))
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.black.cgColor
      view.layer?.opacity = 0.01
      cv.addSubview(view)
    }

    player.initVideo()

    // init quick setting view now
    let _ = quickSettingView

    // buffer indicator view
    bufferIndicatorView.roundCorners(withRadius: 10)
    updateBufferIndicatorView()

    // thumbnail peek view
    window.contentView?.addSubview(thumbnailPeekView)
    thumbnailPeekView.isHidden = true

    // other initialization
    osdAccessoryProgress.usesThreadedAnimation = false
    if #available(macOS 10.14, *) {
      titleBarBottomBorder.fillColor = NSColor(named: .titleBarBorder)!
    }
    cachedScreenCount = NSScreen.screens.count
    [titleBarView, osdVisualEffectView, controlBarBottom, controlBarFloating, sideBarView, osdVisualEffectView, pipOverlayView].forEach {
      $0?.state = .active
    }
    // hide other views
    osdVisualEffectView.isHidden = true
    osdVisualEffectView.roundCorners(withRadius: 10)
    additionalInfoView.roundCorners(withRadius: 10)
    leftArrowLabel.isHidden = true
    rightArrowLabel.isHidden = true
    timePreviewWhenSeek.isHidden = true
    bottomView.isHidden = true
    pipOverlayView.isHidden = true
    
    if player.disableUI { hideUI() }

    // add user default observers
    observedPrefKeys.append(contentsOf: localObservedPrefKeys)
    localObservedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    // add notification observers

    addObserver(to: .default, forName: .iinaFileLoaded, object: player) { [unowned self] _ in
      self.quickSettingView.reload()
    }

    addObserver(to: .default, forName: NSApplication.didChangeScreenParametersNotification) { [unowned self] _ in
      // This observer handles a situation that the user connected a new screen or removed a screen
      let screenCount = NSScreen.screens.count
      if self.fsState.isFullscreen && Preference.bool(for: .blackOutMonitor) && self.cachedScreenCount != screenCount {
        self.removeBlackWindow()
        self.blackOutOtherMonitors()
      }
      // Update the cached value
      self.cachedScreenCount = screenCount
      self.videoView.updateDisplayLink()
      // In normal full screen mode AppKit will automatically adjust the window frame if the window
      // is moved to a new screen such as when the window is on an external display and that display
      // is disconnected. In legacy full screen mode IINA is responsible for adjusting the window's
      // frame.
      guard self.fsState.isFullscreen, Preference.bool(for: .useLegacyFullScreen) else { return }
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

    player.events.emit(.windowLoaded)
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

  /** Set material for OSC and title bar */
  override internal func setMaterial(_ theme: Preference.Theme?) {
    if #available(macOS 10.14, *) {
      super.setMaterial(theme)
      return
    }
    guard let window = window, let theme = theme else { return }

    let (appearance, material) = Utility.getAppearanceAndMaterial(from: theme)
    let isDarkTheme = appearance?.isDark ?? true
    (playSlider.cell as? PlaySliderCell)?.isInDarkTheme = isDarkTheme

    [titleBarView, controlBarFloating, controlBarBottom, osdVisualEffectView, pipOverlayView, additionalInfoView, bufferIndicatorView].forEach {
      $0?.material = material
      $0?.appearance = appearance
    }

    sideBarView.material = .dark
    sideBarView.appearance = NSAppearance(named: .vibrantDark)

    window.appearance = appearance
  }


  private func addVideoViewToWindow() {
    guard let cv = window?.contentView else { return }
    cv.addSubview(videoView, positioned: .below, relativeTo: nil)
    videoView.translatesAutoresizingMaskIntoConstraints = false
    // add constraints
    ([.top, .bottom, .left, .right] as [NSLayoutConstraint.Attribute]).forEach { attr in
      videoViewConstraints[attr] = NSLayoutConstraint(item: videoView, attribute: attr, relatedBy: .equal, toItem: cv, attribute: attr, multiplier: 1, constant: 0)
      videoViewConstraints[attr]!.isActive = true
    }
  }

  private func setupOSCToolbarButtons(_ buttons: [Preference.ToolBarButton]) {
    var buttons = buttons
    if #available(macOS 10.12.2, *) {} else {
      buttons = buttons.filter { $0 != .pip }
    }
    fragToolbarView.views.forEach { fragToolbarView.removeView($0) }
    for buttonType in buttons {
      let button = NSButton()
      button.bezelStyle = .regularSquare
      button.isBordered = false
      button.image = buttonType.image()
      button.action = #selector(self.toolBarButtonAction(_:))
      button.tag = buttonType.rawValue
      button.translatesAutoresizingMaskIntoConstraints = false
      button.refusesFirstResponder = true
      button.toolTip = buttonType.description()
      let buttonWidth = buttons.count == 5 ? "20" : "24"
      Utility.quickConstraints(["H:[btn(\(buttonWidth))]", "V:[btn(24)]"], ["btn": button])
      fragToolbarView.addView(button, in: .trailing)
    }
  }

  private func setupOnScreenController(withPosition newPosition: Preference.OSCPosition) {

    guard !oscIsInitialized || oscPosition != newPosition else { return }
    oscIsInitialized = true

    let isSwitchingToTop = newPosition == .top
    let isSwitchingFromTop = oscPosition == .top
    let isFloating = newPosition == .floating

    if let cb = currentControlBar {
      // remove current osc view from fadeable views
      fadeableViews = fadeableViews.filter { $0 != cb }
    }

    // reset
    ([controlBarFloating, controlBarBottom, oscTopMainView] as [NSView]).forEach { $0.isHidden = true }
    titleBarHeightConstraint.constant = TitleBarHeightNormal

    controlBarFloating.isDragging = false

    // detach all fragment views
    [oscFloatingTopView, oscTopMainView, oscBottomMainView].forEach { stackView in
      stackView!.views.forEach {
        stackView!.removeView($0)
      }
    }
    [fragSliderView, fragControlView, fragToolbarView, fragVolumeView].forEach {
        $0!.removeFromSuperview()
    }

    let isInFullScreen = fsState.isFullscreen

    if isSwitchingToTop {
      if isInFullScreen {
        addBackTitlebarViewToFadeableViews()
        oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTopInFullScreen
        titleBarHeightConstraint.constant = TitleBarHeightWithOSCInFullScreen
      } else {
        oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTop
        titleBarHeightConstraint.constant = TitleBarHeightWithOSC
      }
      // Remove this if it's acceptable in 10.13-
      // titleBarBottomBorder.isHidden = true
    } else {
      // titleBarBottomBorder.isHidden = false
    }

    if isSwitchingFromTop {
      if isInFullScreen {
        titleBarView.isHidden = true
        removeTitlebarViewFromFadeableViews()
      }
    }

    oscPosition = newPosition

    // add fragment views
    switch oscPosition {
    case .floating:
      currentControlBar = controlBarFloating
      fragControlView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragControlViewLeftView)
      fragControlView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragControlViewRightView)
      oscFloatingTopView.addView(fragVolumeView, in: .leading)
      oscFloatingTopView.addView(fragToolbarView, in: .trailing)
      oscFloatingTopView.addView(fragControlView, in: .center)
      
      // Setting the visibility priority to detach only will cause freeze when resizing the window
      // (and triggering the detach) in macOS 11.
      if !isMacOS11 {
        oscFloatingTopView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragVolumeView)
        oscFloatingTopView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragToolbarView)
        oscFloatingTopView.setClippingResistancePriority(.defaultLow, for: .horizontal)
      }
      oscFloatingBottomView.addSubview(fragSliderView)
      Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": fragSliderView])
      Utility.quickConstraints(["H:|-(>=0)-[v]-(>=0)-|"], ["v": fragControlView])
      // center control bar
      let cph = Preference.float(for: .controlBarPositionHorizontal)
      let cpv = Preference.float(for: .controlBarPositionVertical)
      controlBarFloating.xConstraint.constant = window!.frame.width * CGFloat(cph)
      controlBarFloating.yConstraint.constant = window!.frame.height * CGFloat(cpv)
    case .top:
      oscTopMainView.isHidden = false
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
      currentControlBar = controlBarBottom
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

    if currentControlBar != nil {
      fadeableViews.append(currentControlBar!)
    }
    showUI()

    if isFloating {
      fragControlViewMiddleButtons1Constraint.constant = 24
      fragControlViewMiddleButtons2Constraint.constant = 24
      oscFloatingLeadingTrailingConstraint = NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=10)-[v]-(>=10)-|",
                                                                            options: [], metrics: nil, views: ["v": controlBarFloating as Any])
      NSLayoutConstraint.activate(oscFloatingLeadingTrailingConstraint!)
    } else {
      fragControlViewMiddleButtons1Constraint.constant = 16
      fragControlViewMiddleButtons2Constraint.constant = 16
      if let constraints = oscFloatingLeadingTrailingConstraint {
        controlBarFloating.superview?.removeConstraints(constraints)
        oscFloatingLeadingTrailingConstraint = nil
      }
    }
  }

  // MARK: - Mouse / Trackpad events

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
    guard #available(macOS 11, *) else { return }
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  override func mouseDown(with event: NSEvent) {
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      Logger.log("MainWindow mouseDown @ \(event.locationInWindow)", level: .verbose, subsystem: player.subsystem)
    }
    workaroundCursorDefect()
    // do nothing if it's related to floating OSC
    guard !controlBarFloating.isDragging else { return }
    // record current mouse pos
    mousePosRelatedToWindow = event.locationInWindow
    // playlist resizing
    if sideBarStatus == .playlist {
      let sf = sideBarView.frame
      if NSPointInRect(mousePosRelatedToWindow!, NSMakeRect(sf.origin.x - 4, sf.origin.y, 4, sf.height)) {
        isResizingSidebar = true
      }
    }
  }

  override func mouseDragged(with event: NSEvent) {
    if isResizingSidebar {
      // resize sidebar
      let currentLocation = event.locationInWindow
      let newWidth = window!.frame.width - currentLocation.x - 2
      sideBarWidthConstraint.constant = newWidth.clamped(to: PlaylistMinWidth...PlaylistMaxWidth)
    } else if !fsState.isFullscreen {
      guard !controlBarFloating.isDragging else { return }

      if let mousePosRelatedToWindow = mousePosRelatedToWindow {
        if !isDragging {
          /// Require that the user must drag the cursor at least a small distance for it to start a "drag" (`isDragging==true`)
          /// The user's action will only be counted as a click if `isDragging==false` when `mouseUp` is called.
          /// (Apple's trackpad in particular is very sensitive and tends to call `mouseDragged()` if there is even the slightest
          /// roll of the finger during a click, and the distance of the "drag" may be less than `minimumInitialDragDistance`)
          if mousePosRelatedToWindow.distance(to: event.locationInWindow) <= minimumInitialDragDistance {
            return
          }
          if Logger.enabled && Logger.Level.preferred >= .verbose {
            Logger.log("MainWindow mouseDrag: minimum dragging distance was met", level: .verbose, subsystem: player.subsystem)
          }
          isDragging = true
        }
        window?.performDrag(with: event)
      }
    }
  }

  override func mouseUp(with event: NSEvent) {
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      Logger.log("MainWindow mouseUp @ \(event.locationInWindow), isDragging: \(isDragging), isResizingSidebar: \(isResizingSidebar), clickCount: \(event.clickCount)",
                 level: .verbose, subsystem: player.subsystem)
    }
    workaroundCursorDefect()
    mousePosRelatedToWindow = nil
    if isDragging {
      // if it's a mouseup after dragging window
      isDragging = false
    } else if isResizingSidebar {
      // if it's a mouseup after resizing sidebar
      isResizingSidebar = false
      Preference.set(Int(sideBarWidthConstraint.constant), for: .playlistWidth)
    } else {
      // if it's a mouseup after clicking

      // Single click. Note that `event.clickCount` will be 0 if there is at least one call to `mouseDragged()`,
      // but we will only count it as a drag if `isDragging==true`
      if event.clickCount <= 1 && !isMouseEvent(event, inAnyOf: [sideBarView, subPopoverView]) && sideBarStatus != .hidden {
        hideSideBar()
        return
      }
      if event.clickCount == 2 && isMouseEvent(event, inAnyOf: [titleBarView]) {
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
      hideUI()
    case .togglePIP:
      if #available(macOS 10.12, *) {
        menuTogglePIP(.dummy)
      }
    default:
      break
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard !isMouseEvent(event, inAnyOf: [sideBarView, titleBarView, subPopoverView]) else { return }

    if isMouseEvent(event, inAnyOf: [fragSliderView]) && playSlider.isEnabled {
      seekOverride = true
    } else if isMouseEvent(event, inAnyOf: [fragVolumeView]) && volumeSlider.isEnabled {
      volumeOverride = true
    } else {
      guard !isMouseEvent(event, inAnyOf: [currentControlBar]) else { return }
    }

    super.scrollWheel(with: event)

    seekOverride = false
    volumeOverride = false
  }

  override func mouseEntered(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let obj = event.trackingArea?.userInfo?["obj"] as? Int else {
      Logger.log("No data for tracking area", level: .warning)
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
      if controlBarFloating.isDragging { return }
      isMouseInSlider = true
      if !controlBarFloating.isDragging {
        timePreviewWhenSeek.isHidden = false
        thumbnailPeekView.isHidden = !player.info.thumbnailsReady
      }
      let mousePos = playSlider.convert(event.locationInWindow, from: nil)
      updateTimeLabel(mousePos.x, originalPos: event.locationInWindow)
    }
  }

  override func mouseExited(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let obj = event.trackingArea?.userInfo?["obj"] as? Int else {
      Logger.log("No data for tracking area", level: .warning)
      return
    }
    mouseExitEnterCount += 1
    if obj == 0 {
      // main window
      isMouseInWindow = false
      if controlBarFloating.isDragging { return }
      destroyTimer()
      hideUI()
    } else if obj == 1 {
      // slider
      isMouseInSlider = false
      timePreviewWhenSeek.isHidden = true
      let mousePos = playSlider.convert(event.locationInWindow, from: nil)
      updateTimeLabel(mousePos.x, originalPos: event.locationInWindow)
      thumbnailPeekView.isHidden = true
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    let mousePos = playSlider.convert(event.locationInWindow, from: nil)
    if isMouseInSlider {
      updateTimeLabel(mousePos.x, originalPos: event.locationInWindow)
    }
    if isMouseInWindow {
      showUI()
    }
    // check whether mouse is in osc
    if isMouseEvent(event, inAnyOf: [currentControlBar, titleBarView]) {
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
      } else if recognizer.state == .changed {
        // changed
        let offset = recognizer.magnification - lastMagnification + 1.0;
        let newWidth = window.frame.width * offset
        let newHeight = newWidth / window.aspectRatio.aspect

        //Check against max & min threshold
        if newHeight < screenFrame.height && newHeight > minSize.height && newWidth > minSize.width {
          let newSize = NSSize(width: newWidth, height: newHeight);
          window.setFrame(window.frame.centeredResize(to: newSize), display: true)
        }

        lastMagnification = recognizer.magnification
      } else if recognizer.state == .ended {
        updateWindowParametersForMPV()
      }
    }
  }

  // MARK: - Window delegate: Open / Close

  func windowWillOpen() {
    isClosing = false
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
    window!.title = "Window"

    // As there have been issues in this area, log details about the screen selection process.
    NSScreen.log("window!.screen", window!.screen)
    NSScreen.log("NSScreen.main", NSScreen.main)
    NSScreen.screens.enumerated().forEach { screen in
      NSScreen.log("NSScreen.screens[\(screen.offset)]" , screen.element)
    }

    var screen = window!.selectDefaultScreen()

    if let rectString = UserDefaults.standard.value(forKey: "MainWindowLastPosition") as? String {
      let rect = NSRectFromString(rectString)
      if let lastScreen = NSScreen.screens.first(where: { NSPointInRect(rect.origin, $0.visibleFrame) }) {
        screen = lastScreen
        NSScreen.log("MainWindowLastPosition \(rect.origin) matched", screen)
      }
    }

    if shouldApplyInitialWindowSize, let wfg = windowFrameFromGeometry(newSize: AppData.sizeWhenNoVideo, screen: screen) {
      window!.setFrame(wfg, display: true, animate: !AccessibilityPreferences.motionReductionEnabled)
    } else {
      window!.setFrame(AppData.sizeWhenNoVideo.centeredRect(in: screen.visibleFrame), display: true, animate: !AccessibilityPreferences.motionReductionEnabled)
    }

    videoView.videoLayer.draw(forced: true)
  }

  /** A method being called when window open. Pretend to be a window delegate. */
  override func windowDidOpen() {
    super.windowDidOpen()

    window!.makeMain()
    window!.makeKeyAndOrderFront(nil)
    resetCollectionBehavior()
    // update buffer indicator view
    updateBufferIndicatorView()
    // start tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
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
    isClosing = true
    shouldApplyInitialWindowSize = true
    // Close PIP
    if pipStatus == .inPIP {
      if #available(macOS 10.12, *) {
        exitPIP()
      }
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
      window.animator().setFrame(screen.frame, display: true, animate: !AccessibilityPreferences.motionReductionEnabled)
    }, completionHandler: nil)

  }

  func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
    if NSMenu.menuBarVisible() {
      NSMenu.setMenuBarVisible(false)
    }
    let priorWindowedFrame = fsState.priorWindowedFrame!

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = duration
      window.animator().setFrame(priorWindowedFrame, display: true, animate: !AccessibilityPreferences.motionReductionEnabled)
    }, completionHandler: nil)

    NSMenu.setMenuBarVisible(true)
  }

  func windowWillEnterFullScreen(_ notification: Notification) {
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning to full screen mode.
    videoView.displayActive()
    if isInInteractiveMode {
      exitInteractiveMode(immediately: true)
    }

    // Set the appearance to match the theme so the titlebar matches the theme
    let iinaTheme = Preference.enum(for: .themeMaterial) as Preference.Theme
    if #available(macOS 10.14, *) {
      window?.appearance = NSAppearance(iinaTheme: iinaTheme)
    } else {
      switch(iinaTheme) {
      case .dark, .ultraDark: window!.appearance = NSAppearance(named: .vibrantDark)
      default: window!.appearance = NSAppearance(named: .vibrantLight)
      }
    }

    // show titlebar
    if oscPosition == .top {
      oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTopInFullScreen
      titleBarHeightConstraint.constant = TitleBarHeightWithOSCInFullScreen
    } else {
      // stop animation and hide titleBarView
      removeTitlebarViewFromFadeableViews()
      titleBarView.isHidden = true
    }
    standardWindowButtons.forEach { $0.alphaValue = 0 }
    titleTextField?.alphaValue = 0
    
    window!.removeTitlebarAccessoryViewController(at: 0)
    setWindowFloatingOnTop(false, updateOnTopStatus: false)

    thumbnailPeekView.isHidden = true
    timePreviewWhenSeek.isHidden = true
    isMouseInSlider = false

    let isLegacyFullScreen = notification.name == .iinaLegacyFullScreen
    fsState.startAnimatingToFullScreen(legacy: isLegacyFullScreen, priorWindowedFrame: window!.frame)

    videoView.videoLayer.suspend()
    // Let mpv decide the correct render region in full screen
    player.mpv.setFlag(MPVOption.Window.keepaspect, true)
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    fsState.finishAnimating()

    titleTextField?.alphaValue = 1
    removeStandardButtonsFromFadeableViews()

    videoViewConstraints.values.forEach { $0.constant = 0 }
    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    videoView.videoLayer.resume()

    if Preference.bool(for: .blackOutMonitor) {
      blackOutOtherMonitors()
    }

    if Preference.bool(for: .displayTimeAndBatteryInFullScreen) {
      fadeableViews.append(additionalInfoView)
    }

    if player.info.isPaused {
      if Preference.bool(for: .playWhenEnteringFullScreen) {
        player.resume()
      } else {
        // When playback is paused the display link is stopped in order to avoid wasting energy on
        // needless processing. It must be running while transitioning to full screen mode. Now that
        // the transition has completed it can be stopped.
        videoView.displayIdle()
      }
    }

    if #available(macOS 10.12.2, *) {
      player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: true)
    }

    updateWindowParametersForMPV()

    // Exit PIP if necessary
    if pipStatus == .inPIP,
      #available(macOS 10.12, *) {
      exitPIP()
    }
    
    player.events.emit(.windowFullscreenChanged, data: true)
  }

  func windowWillExitFullScreen(_ notification: Notification) {
    // When playback is paused the display link is stopped in order to avoid wasting energy on
    // needless processing. It must be running while transitioning from full screen mode.
    videoView.displayActive()
    if isInInteractiveMode {
      exitInteractiveMode(immediately: true)
    }

    // show titleBarView
    if oscPosition == .top {
      oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTop
      titleBarHeightConstraint.constant = TitleBarHeightWithOSC
    }

    thumbnailPeekView.isHidden = true
    timePreviewWhenSeek.isHidden = true
    additionalInfoView.isHidden = true
    isMouseInSlider = false

    if let index = fadeableViews.firstIndex(of: additionalInfoView) {
      fadeableViews.remove(at: index)
    }

    fsState.startAnimatingToWindow()

    // If a window is closed while in full screen mode (control-w pressed) AppKit will still call
    // this method. Because windows are tied to player cores and cores are cached and reused some
    // processing must be performed to leave the window in a consistent state for reuse. However
    // the windowWillClose method will have initiated unloading of the file being played. That
    // operation is processed asynchronously by mpv. If the window is being closed due to IINA
    // quitting then mpv could be in the process of shutting down. Must not access mpv while it is
    // asynchronously processing stop and quit commands.
    guard !isClosing else { return }
    videoView.videoLayer.suspend()
    player.mpv.setFlag(MPVOption.Window.keepaspect, false)
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    if AccessibilityPreferences.motionReductionEnabled {
      // When animation is not used exiting full screen does not restore the previous size of the
      // window. Restore it now.
      window!.setFrame(fsState.priorWindowedFrame!, display: true, animate: false)
    }
    if oscPosition != .top {
      addBackTitlebarViewToFadeableViews()
    }
    addBackStandardButtonsToFadeableViews()
    titleBarView.isHidden = false
    fsState.finishAnimating()

    if Preference.bool(for: .blackOutMonitor) {
      removeBlackWindow()
    }

    if player.info.isPaused {
      // When playback is paused the display link is stopped in order to avoid wasting energy on
      // needless processing. It must be running while transitioning from full screen mode. Now that
      // the transition has completed it can be stopped.
      videoView.displayIdle()
    }

    if #available(macOS 10.12.2, *) {
      player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: false)
    }

    window!.addTitlebarAccessoryViewController(titlebarAccesoryViewController)

    // Must not access mpv while it is asynchronously processing stop and quit commands.
    // See comments in windowWillExitFullScreen for details.
    guard !isClosing else { return }
    showUI()
    updateTimer()

    videoViewConstraints.values.forEach { $0.constant = 0 }
    videoView.needsLayout = true
    videoView.layoutSubtreeIfNeeded()
    videoView.videoLayer.resume()

    if Preference.bool(for: .pauseWhenLeavingFullScreen) && player.info.isPlaying {
      player.pause()
    }

    // restore ontop status
    if player.info.isPlaying {
      setWindowFloatingOnTop(isOntop, updateOnTopStatus: false)
    }

    resetCollectionBehavior()
    updateWindowParametersForMPV()
    
    player.events.emit(.windowFullscreenChanged, data: false)
  }

  func toggleWindowFullScreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    switch fsState {
    case .windowed:
      guard !player.isInMiniPlayer else { return }
      if Preference.bool(for: .useLegacyFullScreen) {
        self.legacyAnimateToFullscreen()
      } else {
        window.toggleFullScreen(self)
      }
    case let .fullscreen(legacy, oldFrame):
      if legacy {
        self.legacyAnimateToWindowed(framePriorToBeingInFullscreen: oldFrame)
      } else {
        window.toggleFullScreen(self)
      }
    default:
      return
    }
  }

  private func restoreDockSettings() {
    NSApp.presentationOptions.remove(.autoHideMenuBar)
    NSApp.presentationOptions.remove(.autoHideDock)
  }

  private func legacyAnimateToWindowed(framePriorToBeingInFullscreen: NSRect) {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    // call delegate
    windowWillExitFullScreen(Notification(name: .iinaLegacyFullScreen))
    // stylemask
    window.styleMask.remove(.borderless)
    if #available(macOS 10.16, *) {
      window.styleMask.insert(.titled)
      (window as! MainWindow).forceKeyAndMain = false
      window.level = .normal
    } else {
      window.styleMask.remove(.fullScreen)
    }
 
    restoreDockSettings()
    // restore window frame and aspect ratio
    let videoSize = player.videoSizeForDisplay
    let aspectRatio = NSSize(width: videoSize.0, height: videoSize.1)
    let useAnimation = Preference.bool(for: .legacyFullScreenAnimation)
    if useAnimation {
      // firstly resize to a big frame with same aspect ratio for better visual experience
      let aspectFrame = aspectRatio.shrink(toSize: window.frame.size).centeredRect(in: window.frame)
      window.setFrame(aspectFrame, display: true, animate: false)
    }
    // then animate to the original frame
    window.setFrame(framePriorToBeingInFullscreen, display: true, animate: useAnimation)
    window.aspectRatio = aspectRatio
    // call delegate
    windowDidExitFullScreen(Notification(name: .iinaLegacyFullScreen))
  }

  /// Set the window frame and if needed the content view frame to appropriately use the full screen.
  ///
  /// For screens that contain a camera housing the content view will be adjusted to not use that area of the screen.
  private func setWindowFrameForLegacyFullScreen() {
    guard let window = self.window else { return }
    let screen = window.screen ?? NSScreen.main!
    window.setFrame(screen.frame, display: true, animate: !AccessibilityPreferences.motionReductionEnabled)
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
    if #available(macOS 10.16, *) {
      window.styleMask.remove(.titled)
      (window as! MainWindow).forceKeyAndMain = true
      window.level = .floating
    } else {
      window.styleMask.insert(.fullScreen)
    }
    // cancel aspect ratio
    window.resizeIncrements = NSSize(width: 1, height: 1)
    // auto hide menubar and dock
    NSApp.presentationOptions.insert(.autoHideMenuBar)
    NSApp.presentationOptions.insert(.autoHideDock)
    // set window frame and in some cases content view frame
    setWindowFrameForLegacyFullScreen()
    // call delegate
    windowDidEnterFullScreen(Notification(name: .iinaLegacyFullScreen))
  }

  // MARK: - Window delegate: Size

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    guard let window = window else { return frameSize }
    if frameSize.height <= minSize.height || frameSize.width <= minSize.width {
      return window.aspectRatio.grow(toSize: minSize)
    }
    return frameSize
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = window else { return }

    // The `videoView` is not updated during full screen animation (unless using a custom one, however it could be
    // unbearably laggy under current render meahcanism). Thus when entering full screen, we should keep `videoView`'s
    // aspect ratio. Otherwise, when entered full screen, there will be an awkward animation that looks like
    // `videoView` "resized" to screen size suddenly when mpv redraws the video content in correct aspect ratio.
    if case let .animating(toFullScreen, _, _) = fsState {
      let aspect: NSSize
      let targetFrame: NSRect
      if toFullScreen {
        aspect = window.aspectRatio == .zero ? window.frame.size : window.aspectRatio
        targetFrame = aspect.shrink(toSize: window.frame.size).centeredRect(in: window.contentView!.frame)
      } else {
        aspect = window.screen?.frame.size ?? NSScreen.main!.frame.size
        targetFrame = aspect.grow(toSize: window.frame.size).centeredRect(in: window.contentView!.frame)
      }

      setConstraintsForVideoView([
        .left: targetFrame.minX,
        .right:  targetFrame.maxX - window.frame.width,
        .bottom: -targetFrame.minY,
        .top: window.frame.height - targetFrame.maxY
      ])
    }

    // interactive mode
    if isInInteractiveMode {
      cropSettingsView?.cropBoxView.resized(with: videoView.frame)
    }

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

      controlBarFloating.xConstraint.constant = xPos
      controlBarFloating.yConstraint.constant = yPos
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
      
      let views = oscFloatingTopView.views
      if hide {
        if views.contains(fragVolumeView)
            && views.contains(fragToolbarView) {
          oscFloatingTopView.removeView(fragVolumeView)
          oscFloatingTopView.removeView(fragToolbarView)
        }
      } else {
        if !views.contains(fragVolumeView)
            && !views.contains(fragToolbarView) {
          oscFloatingTopView.addView(fragVolumeView, in: .leading)
          oscFloatingTopView.addView(fragToolbarView, in: .trailing)
        }
      }
    }

    player.events.emit(.windowResized, data: window.frame)
  }

  // resize framebuffer in videoView after resizing.
  func windowDidEndLiveResize(_ notification: Notification) {
    // Must not access mpv while it is asynchronously processing stop and quit commands.
    // See comments in windowWillExitFullScreen for details.
    guard !isClosing else { return }
    videoView.videoSize = window!.convertToBacking(videoView.bounds).size
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
      if Preference.bool(for: .pauseWhenInactive), player.info.isPlaying {
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
    if Preference.bool(for: .pauseWhenMinimized), player.info.isPlaying {
      isPausedDueToMiniaturization = true
      player.pause()
    }
  }

  func windowDidMiniaturize(_ notification: Notification) {
    if Preference.bool(for: .togglePipByMinimizingWindow) && !isWindowMiniaturizedDueToPip {
      if #available(macOS 10.12, *) {
        enterPIP()
      }
    }
    player.events.emit(.windowMiniaturized)
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    if Preference.bool(for: .pauseWhenMinimized) && isPausedDueToMiniaturization {
      player.resume()
      isPausedDueToMiniaturization = false
    }
    if Preference.bool(for: .togglePipByMinimizingWindow) && !isWindowMiniaturizedDueToPip {
      if #available(macOS 10.12, *) {
        exitPIP()
      }
    }
    player.events.emit(.windowDeminiaturized)
  }

  // MARK: - UI: Show / Hide

  @objc func hideUIAndCursor() {
    // don't hide UI when dragging control bar
    if controlBarFloating.isDragging { return }
    hideUI()
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  private func hideUI() {
    // Don't hide UI when in PIP
    guard pipStatus == .notInPIP || animationState == .hidden else {
      return
    }

    animationState = .willHide
    player.refreshSyncUITimer()
    fadeableViews.forEach { (v) in
      v.isHidden = false
    }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = UIAnimationDuration
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
      context.duration = UIAnimationDuration
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
      window?.title = player.getMediaTitle()
    } else {
      window?.representedURL = player.info.currentURL
      // Workaround for issue #3543, IINA crashes reporting:
      // NSInvalidArgumentException [NSNextStepFrame _displayName]: unrecognized selector
      // When running on an M1 under Big Sur and using legacy full screen.
      //
      // Changes in Big Sur broke the legacy full screen feature. The MainWindowController method
      // legacyAnimateToFullscreen had to be changed to get this feature working again. Under Big
      // Sur that method now calls "window.styleMask.remove(.titled)". Removing titled from the
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
      if Preference.bool(for: .useLegacyFullScreen), #available(macOS 11, *) {
        window?.title = player.info.currentURL?.lastPathComponent ?? ""
      } else {
        window?.setTitleWithRepresentedFilename(player.info.currentURL?.path ?? "")
      }
    }
    addDocIconToFadeableViews()
  }

  func updateOnTopIcon() {
    titlebarOnTopButton.isHidden = Preference.bool(for: .alwaysShowOnTopIcon) ? false : !isOntop
    titlebarOnTopButton.state = isOntop ? .on : .off
  }

  // MARK: - UI: OSD

  // Do not call displayOSD directly, call PlayerCore.sendOSD instead.
  func displayOSD(_ message: OSDMessage, autoHide: Bool = true, forcedTimeout: Float? = nil, accessoryView: NSView? = nil, context: Any? = nil) {
    guard player.displayOSD && !isShowingPersistentOSD else { return }

    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    osdAnimationState = .shown

    let (osdString, osdType) = message.message()

    let osdTextSize = Preference.float(for: .osdTextSize)
    osdLabel.font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(osdTextSize), weight: .regular)
    osdAccessoryText.font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(osdTextSize * 0.5).clamped(to: 11...25), weight: .regular)
    osdLabel.stringValue = osdString

    switch osdType {
    case .normal:
      osdStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)
    case .withProgress(let value):
      osdStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdStackView.setVisibilityPriority(.mustHold, for: osdAccessoryProgress)
      osdAccessoryProgress.doubleValue = value
    case .withText(let text):
      // data for mustache redering
      let osdData: [String: String] = [
        "duration": player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "position": player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).description,
        "chapterCount": player.info.chapters.count.description
      ]

      osdStackView.setVisibilityPriority(.mustHold, for: osdAccessoryText)
      osdStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)
      osdAccessoryText.stringValue = try! (try! Template(string: text)).render(osdData)
    }

    osdVisualEffectView.alphaValue = 1
    osdVisualEffectView.isHidden = false
    osdVisualEffectView.layoutSubtreeIfNeeded()

    osdStackView.views(in: .bottom).forEach {
      osdStackView.removeView($0)
    }
    if let accessoryView = accessoryView {
      isShowingPersistentOSD = true
      if context != nil {
        osdContext = context
      }

      if #available(macOS 10.14, *) {} else {
        accessoryView.appearance = NSAppearance(named: .vibrantDark)
      }
      let heightConstraint = NSLayoutConstraint(item: accessoryView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 300)
      heightConstraint.priority = .defaultLow
      heightConstraint.isActive = true

      osdStackView.addView(accessoryView, in: .bottom)
      Utility.quickConstraints(["H:|-0-[v(>=240)]-0-|"], ["v": accessoryView])

      // enlarge window if too small
      let winFrame = window!.frame
      var newFrame = winFrame
      if (winFrame.height < 300) {
        newFrame = winFrame.centeredResize(to: winFrame.size.satisfyMinSizeWithSameAspectRatio(NSSize(width: 500, height: 300)))
      }

      accessoryView.wantsLayer = true
      accessoryView.layer?.opacity = 0

      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.3
        context.allowsImplicitAnimation = true
        window!.setFrame(newFrame, display: true)
        osdVisualEffectView.layoutSubtreeIfNeeded()
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
      osdVisualEffectView.animator().alphaValue = 0
    }) {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
        self.osdStackView.views(in: .bottom).forEach { self.osdStackView.removeView($0) }
      }
    }
    isShowingPersistentOSD = false
    osdContext = nil
  }

  func updateAdditionalInfo() {
    additionalInfoLabel.stringValue = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
    additionalInfoTitle.stringValue = window?.representedURL?.lastPathComponent ?? window?.title ?? ""
    if let capacity = PowerSource.getList().filter({ $0.type == "InternalBattery" }).first?.currentCapacity {
      additionalInfoBattery.stringValue = "\(capacity)%"
      additionalInfoStackView.setVisibilityPriority(.mustHold, for: additionalInfoBatteryView)
    } else {
      additionalInfoStackView.setVisibilityPriority(.notVisible, for: additionalInfoBatteryView)
    }
  }

  // MARK: - UI: Side bar

  private func showSideBar(viewController: SidebarViewController, type: SideBarViewType) {
    guard !isInInteractiveMode else { return }

    // adjust sidebar width
    guard let view = (viewController as? NSViewController)?.view else {
        Logger.fatal("viewController is not a NSViewController")
    }
    sidebarAnimationState = .willShow
    let width = type.width()
    sideBarWidthConstraint.constant = width
    sideBarRightConstraint.constant = -width
    sideBarView.isHidden = false
    // add view and constraints
    sideBarView.addSubview(view)
    let constraintsH = NSLayoutConstraint.constraints(withVisualFormat: "H:|[v]|", options: [], metrics: nil, views: ["v": view])
    let constraintsV = NSLayoutConstraint.constraints(withVisualFormat: "V:|[v]|", options: [], metrics: nil, views: ["v": view])
    NSLayoutConstraint.activate(constraintsH)
    NSLayoutConstraint.activate(constraintsV)
    var viewController = viewController
    viewController.downShift = titleBarView.frame.height
    // show sidebar
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = AccessibilityPreferences.adjustedDuration(SideBarAnimationDuration)
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      sideBarRightConstraint.animator().constant = 0
    }) {
      self.sidebarAnimationState = .shown
      self.sideBarStatus = type
    }
  }

  func hideSideBar(animate: Bool = true, after: @escaping () -> Void = { }) {
    sidebarAnimationState = .willHide
    let currWidth = sideBarWidthConstraint.constant
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = animate ? AccessibilityPreferences.adjustedDuration(SideBarAnimationDuration) : 0
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      sideBarRightConstraint.animator().constant = -currWidth
    }) {
      if self.sidebarAnimationState == .willHide {
        self.sideBarStatus = .hidden
        self.sideBarView.subviews.removeAll()
        self.sideBarView.isHidden = true
        self.sidebarAnimationState = .hidden
        after()
      }
    }
  }

  private func setConstraintsForVideoView(_ constraints: [NSLayoutConstraint.Attribute: CGFloat]) {
    for (attr, value) in constraints {
      videoViewConstraints[attr]?.constant = value
    }
  }

  // MARK: - UI: "Fadeable" views

  private func removeStandardButtonsFromFadeableViews() {
    fadeableViews = fadeableViews.filter { view in
      !standardWindowButtons.contains {
        $0 == view
      }
    }
    for view in standardWindowButtons {
      view.alphaValue = 1
      view.isHidden = false
    }
  }

  private func removeTitlebarViewFromFadeableViews() {
    if let index = (self.fadeableViews.firstIndex { $0 === titleBarView }) {
      self.fadeableViews.remove(at: index)
    }
  }

  private func addBackStandardButtonsToFadeableViews() {
    fadeableViews.append(contentsOf: standardWindowButtons as [NSView])
  }

  private func addBackTitlebarViewToFadeableViews() {
    fadeableViews.append(titleBarView)
  }

  // Sometimes the doc icon may not be available, eg. when opened an online video.
  // We should try to add it every time when window title changed.
  private func addDocIconToFadeableViews() {
    if let docIcon = window?.standardWindowButton(.documentIconButton), !fadeableViews.contains(docIcon) {
      fadeableViews.append(docIcon)
    }
  }

  // MARK: - UI: Interactive mode

  func enterInteractiveMode(_ mode: InteractiveMode, selectWholeVideoByDefault: Bool = false) {
    // prerequisites
    guard let window = window else { return }

    if #available(macOS 10.14, *) {
      window.backgroundColor = .windowBackgroundColor
    } else {
      window.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
    }

    let (ow, oh) = player.originalVideoSize
    guard ow != 0 && oh != 0 else {
      Utility.showAlert("no_video_track")
      return
    }

    isPausedPriorToInteractiveMode = player.info.isPaused
    player.pause()
    isInInteractiveMode = true
    hideUI()

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
      videoView.videoLayer.mpvGLQueue.async {
        DispatchQueue.main.sync {
          self.videoView.videoLayer.draw()
        }
      }
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
    window.contentView!.addSubview(controlView.cropBoxView)
    controlView.cropBoxView.selectedRect = selectedRect
    controlView.cropBoxView.actualSize = origVideoSize
    controlView.cropBoxView.resized(with: newVideoViewFrame)
    controlView.cropBoxView.isHidden = true
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": controlView.cropBoxView])

    self.cropSettingsView = controlView

    // show crop settings view
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = AccessibilityPreferences.adjustedDuration(CropAnimationDuration)
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      bottomBarBottomConstraint.animator().constant = 0
      ([.top, .bottom, .left, .right] as [NSLayoutConstraint.Attribute]).forEach { attr in
        videoViewConstraints[attr]!.animator().constant = newConstants[attr]!
      }
    }) {
      self.cropSettingsView?.cropBoxView.isHidden = false
      self.videoView.layer?.shadowColor = .black
      self.videoView.layer?.shadowOpacity = 1
      self.videoView.layer?.shadowOffset = .zero
      self.videoView.layer?.shadowRadius = 3
    }
  }

  func exitInteractiveMode(immediately: Bool = false, then: @escaping () -> Void = {}) {
    window?.backgroundColor = .black

    if !isPausedPriorToInteractiveMode {
      player.resume()
    }
    isInInteractiveMode = false
    cropSettingsView?.cropBoxView.isHidden = true

    // if exit without animation
    if immediately {
      bottomBarBottomConstraint.constant = -InteractiveModeBottomViewHeight
      ([.top, .bottom, .left, .right] as [NSLayoutConstraint.Attribute]).forEach { attr in
        videoViewConstraints[attr]!.constant = 0
      }
      self.cropSettingsView?.cropBoxView.removeFromSuperview()
      self.sideBarStatus = .hidden
      self.bottomView.subviews.removeAll()
      self.bottomView.isHidden = true
      return
    }

    // if with animation
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = AccessibilityPreferences.adjustedDuration(CropAnimationDuration)
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      bottomBarBottomConstraint.animator().constant = -InteractiveModeBottomViewHeight
      ([.top, .bottom, .left, .right] as [NSLayoutConstraint.Attribute]).forEach { attr in
        videoViewConstraints[attr]!.animator().constant = 0
      }
    }) {
      self.cropSettingsView?.cropBoxView.removeFromSuperview()
      self.sideBarStatus = .hidden
      self.bottomView.subviews.removeAll()
      self.bottomView.isHidden = true
      self.showUI()
      then()
    }
  }

  /// Determine if the thumbnail preview can be shown above the progress bar in the on screen controller..
  ///
  /// Normally the OSC's thumbnail preview is shown above the time preview. This is the preferred location. However the
  /// thumbnail preview extends beyond the frame of the OSC. If the OSC is near the top of the window this could result
  /// in the thumbnail extending outside of the window resulting in clipping. This method checks if there is room for the
  /// thumbnail to fully fit in the window. Otherwise the thumbnail must be displayed below the OSC's progress bar.
  /// - Parameters:
  ///   - timnePreviewYPos: The y-coordinate of the time preview `TextField`.
  ///   - thumbnailHeight: The height of the thumbnail.
  /// - Returns: `true` if the thumbnail can be shown above the slider, `false` otherwise.
  private func canShowThumbnailAbove(timnePreviewYPos: Double, thumbnailHeight: Double) -> Bool {
    guard oscPosition != .bottom else { return true }
    guard oscPosition != .top else { return false }
    // The layout preference for the on screen controller is set to the default floating layout.
    // Must insure the top of the thumbnail would be below the top of the window.
    let topOfThumbnail = timnePreviewYPos + timePreviewWhenSeek.frame.height + thumbnailHeight
    // Normally the height of the usable area of the window can be obtained from the content
    // layout. But when the legacy full screen preference is enabled the layout height may be
    // larger than the content view if the display contains a camera housing. Use the lower of
    // the two heights.
    let windowContentHeight = min(window!.contentLayoutRect.height, window!.contentView!.frame.height)
    return topOfThumbnail <= windowContentHeight
  }

  /** Display time label when mouse over slider */
  private func updateTimeLabel(_ mouseXPos: CGFloat, originalPos: NSPoint) {
    let timeLabelXPos = round(mouseXPos + playSlider.frame.origin.x - timePreviewWhenSeek.frame.width / 2)
    let timeLabelYPos = playSlider.frame.origin.y + playSlider.frame.height
    timePreviewWhenSeek.frame.origin = NSPoint(x: timeLabelXPos, y: timeLabelYPos)
    let sliderFrame = playSlider.bounds
    let sliderFrameInWindow = playSlider.superview!.convert(playSlider.frame.origin, to: nil)
    var percentage = Double((mouseXPos - 3) / (sliderFrame.width - 6))
    if percentage < 0 {
      percentage = 0
    }

    if let duration = player.info.videoDuration {
      let previewTime = duration * percentage
      timePreviewWhenSeek.stringValue = previewTime.stringRepresentation

      if player.info.thumbnailsReady, let image = player.info.getThumbnail(forSecond: previewTime.second)?.image {
        thumbnailPeekView.imageView.image = image.rotate(rotation)
        thumbnailPeekView.isHidden = false
        let height = round(120 / thumbnailPeekView.imageView.image!.size.aspect)
        let timePreviewFrameInWindow = timePreviewWhenSeek.superview!.convert(timePreviewWhenSeek.frame.origin, to: nil)
        let showAbove = canShowThumbnailAbove(timnePreviewYPos: timePreviewFrameInWindow.y, thumbnailHeight: height)
        let yPos = showAbove ? timePreviewFrameInWindow.y + timePreviewWhenSeek.frame.height : sliderFrameInWindow.y - height
        thumbnailPeekView.frame.size = NSSize(width: 120, height: height)
        thumbnailPeekView.frame.origin = NSPoint(x: round(originalPos.x - thumbnailPeekView.frame.width / 2), y: yPos)
      } else {
        thumbnailPeekView.isHidden = true
      }
    }
  }

  func updateBufferIndicatorView() {
    guard loaded else { return }

    if player.info.isNetworkResource {
      bufferIndicatorView.isHidden = false
      bufferSpin.startAnimation(nil)
      bufferProgressLabel.stringValue = NSLocalizedString("main.opening_stream", comment:"Opening stream…")
      bufferDetailLabel.stringValue = ""
    } else {
      bufferIndicatorView.isHidden = true
    }
  }

  // MARK: - UI: Window size / aspect

  /** Calculate the window frame from a parsed struct of mpv's `geometry` option. */
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
      w = max(minSize.width, w)
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
      h = max(minSize.height, h)
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

  /** Set window size when info available, or video size changed. */
  func adjustFrameByVideoSize() {
    guard let window = window else { return }

    let (width, height) = player.videoSizeForDisplay

    // set aspect ratio
    let originalVideoSize = NSSize(width: width, height: height)
    window.aspectRatio = originalVideoSize
    if #available(macOS 10.12, *) {
      pip.aspectRatio = originalVideoSize
    }

    videoView.videoSize = window.convertToBacking(videoView.frame).size

    var rect: NSRect
    let needResizeWindow: Bool

    let frame = fsState.priorWindowedFrame ?? window.frame

    if player.info.justStartedFile {
      // resize option applies
      let resizeTiming = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
      switch resizeTiming {
      case .always:
        needResizeWindow = true
      case .onlyWhenOpen:
        needResizeWindow = player.info.justOpenedFile
      case .never:
        needResizeWindow = false
      }
    } else {
      // video size changed during playback
      needResizeWindow = true
    }

    if needResizeWindow {
      let resizeRatio = (Preference.enum(for: .resizeWindowOption) as Preference.ResizeWindowOption).ratio
      // get videoSize on screen
      var videoSize = originalVideoSize
      let screenRect = window.screen?.visibleFrame

      if Preference.bool(for: .usePhysicalResolution) {
        videoSize = window.convertFromBacking(
          NSMakeRect(window.frame.origin.x, window.frame.origin.y, CGFloat(width), CGFloat(height))).size
      }
      if player.info.justStartedFile {
        if resizeRatio < 0 {
          if let screenSize = screenRect?.size {
            videoSize = videoSize.shrink(toSize: screenSize)
          }
        } else {
          videoSize = videoSize.multiply(CGFloat(resizeRatio))
        }
      }
      // check screen size
      if let screenSize = screenRect?.size {
        videoSize = videoSize.satisfyMaxSizeWithSameAspectRatio(screenSize)
      }
      // guard min size
      // must be slightly larger than the min size, or it will crash when the min size is auto saved as window frame size.
      videoSize = videoSize.satisfyMinSizeWithSameAspectRatio(minSize)
      // check if have geometry set (initial window position/size)
      if shouldApplyInitialWindowSize, let wfg = windowFrameFromGeometry(newSize: videoSize) {
        rect = wfg
      } else {
        if player.info.justStartedFile, resizeRatio < 0, let screenRect = screenRect {
          rect = screenRect.centeredResize(to: videoSize)
        } else {
          rect = frame.centeredResize(to: videoSize)
        }
      }

    } else {
      // user is navigating in playlist. remain same window width.
      let newHeight = frame.width / CGFloat(width) * CGFloat(height)
      let newSize = NSSize(width: frame.width, height: newHeight).satisfyMinSizeWithSameAspectRatio(minSize)
      rect = NSRect(origin: frame.origin, size: newSize)
    }

    // maybe not a good position, consider putting these at playback-restart
    player.info.justOpenedFile = false
    player.info.justStartedFile = false
    shouldApplyInitialWindowSize = false

    if fsState.isFullscreen {
      fsState.priorWindowedFrame = rect
    } else {
      if let screenFrame = window.screen?.frame {
        rect = rect.constrain(in: screenFrame)
      }
      if player.disableWindowAnimation {
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
      player.mpv.setDouble(MPVProperty.windowScale, windowScale)
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
      newFrame = window.frame.centeredResize(to: finalSize.satisfyMinSizeWithSameAspectRatio(minSize)).constrain(in: screenFrame)
    }
    window.setFrame(newFrame, display: true, animate: true)
  }

  // MARK: - UI: Others

  private func blackOutOtherMonitors() {
    screens = NSScreen.screens.filter { $0 != window?.screen }

    blackWindows = []

    for screen in screens {
      var screenRect = screen.frame
      screenRect.origin = CGPoint(x: 0, y: 0)
      let blackWindow = NSWindow(contentRect: screenRect, styleMask: [], backing: .buffered, defer: false, screen: screen)
      blackWindow.backgroundColor = .black
      blackWindow.level = .iinaBlackScreen

      blackWindows.append(blackWindow)
      blackWindow.makeKeyAndOrderFront(nil)
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

  override func updatePlayButtonState(_ state: NSControl.StateValue) {
    super.updatePlayButtonState(state)
    if state == .off {
      speedValueIndex = AppData.availableSpeedValues.count / 2
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = true
    }
  }

  func updateNetworkState() {
    let needShowIndicator = player.info.pausedForCache || player.info.isSeeking

    if needShowIndicator {
      let usedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheUsed, prefixedBy: .ki)
      let speedStr = FloatingPointByteCountFormatter.string(fromByteCount: player.info.cacheSpeed)
      let bufferingState = player.info.bufferingState
      bufferIndicatorView.isHidden = false
      bufferProgressLabel.stringValue = String(format: NSLocalizedString("main.buffering_indicator", comment:"Buffering... %d%%"), bufferingState)
      bufferDetailLabel.stringValue = "\(usedStr)B (\(speedStr)/s)"
    } else {
      bufferIndicatorView.isHidden = true
    }
  }

  func updateArrowButtonImage() {
    if arrowBtnFunction == .playlist {
      leftArrowButton.image = #imageLiteral(resourceName: "nextl")
      rightArrowButton.image = #imageLiteral(resourceName: "nextr")
    } else {
      leftArrowButton.image = #imageLiteral(resourceName: "speedl")
      rightArrowButton.image = #imageLiteral(resourceName: "speed")
    }
  }

  // MARK: - IBActions

  @IBAction override func playButtonAction(_ sender: NSButton) {
    super.playButtonAction(sender)
    if (player.info.isPaused) {
      // speed is already reset by playerCore
      speedValueIndex = AppData.availableSpeedValues.count / 2
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = true
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

  @IBAction func leftButtonAction(_ sender: NSButton) {
    if arrowBtnFunction == .speed {
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
    } else {
      // trigger action only when released button
      if sender.intValue == 0 {
        arrowButtonAction(left: true)
      }
    }
  }

  @IBAction func rightButtonAction(_ sender: NSButton) {
    if arrowBtnFunction == .speed {
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
    } else {
      // trigger action only when released button
      if sender.intValue == 0 {
        arrowButtonAction(left: false)
      }
    }
  }

  /** handle action of both left and right arrow button */
  func arrowButtonAction(left: Bool) {
    switch arrowBtnFunction {
    case .speed:
      isFastforwarding = true
      let speedValue = AppData.availableSpeedValues[speedValueIndex]
      player.setSpeed(speedValue)
      if speedValueIndex == 5 {
        leftArrowLabel.isHidden = true
        rightArrowLabel.isHidden = true
      } else if speedValueIndex < 5 {
        leftArrowLabel.isHidden = false
        rightArrowLabel.isHidden = true
        leftArrowLabel.stringValue = String(format: "%.2fx", speedValue)
      } else if speedValueIndex > 5 {
        leftArrowLabel.isHidden = true
        rightArrowLabel.isHidden = false
        rightArrowLabel.stringValue = String(format: "%.0fx", speedValue)
      }
      // if is paused
      if playButton.state == .off {
        updatePlayButtonState(.on)
        player.resume()
      }

    case .playlist:
      player.mpv.command(left ? .playlistPrev : .playlistNext, checkError: false)

    case .seek:
      player.seek(relativeSecond: left ? -10 : 10, option: .relative)

    }
  }

  @IBAction func ontopButtonnAction(_ sender: NSButton) {
    setWindowFloatingOnTop(!isOntop)
  }

  func showSettingsSidebar(tab: QuickSettingViewController.TabViewType? = nil, force: Bool = false, hideIfAlreadyShown: Bool = true) {
    if !force && sidebarAnimationState == .willShow || sidebarAnimationState == .willHide {
      return  // do not interrput other actions while it is animating
    }
    let view = quickSettingView
    switch sideBarStatus {
    case .hidden:
      if let tab = tab {
        view.pleaseSwitchToTab(tab)
      }
      showSideBar(viewController: view, type: .settings)
    case .playlist:
      if let tab = tab {
        view.pleaseSwitchToTab(tab)
      }
      hideSideBar {
        self.showSideBar(viewController: view, type: .settings)
      }
    case .settings:
      if view.currentTab == tab || tab == nil {
        if hideIfAlreadyShown {
          hideSideBar()
        }
      } else if let tab = tab {
        view.pleaseSwitchToTab(tab)
      }
    }
  }

  func showPlaylistSidebar(tab: PlaylistViewController.TabViewType? = nil, force: Bool = false, hideIfAlreadyShown: Bool = true) {
    if !force && sidebarAnimationState == .willShow || sidebarAnimationState == .willHide {
      return  // do not interrput other actions while it is animating
    }
    let view = playlistView
    switch sideBarStatus {
    case .hidden:
      if let tab = tab {
        view.pleaseSwitchToTab(tab)
      }
      showSideBar(viewController: view, type: .playlist)
    case .settings:
      if let tab = tab {
        view.pleaseSwitchToTab(tab)
      }
      hideSideBar {
        self.showSideBar(viewController: view, type: .playlist)
      }
    case .playlist:
      if view.currentTab == tab || tab == nil {
        if hideIfAlreadyShown {
          hideSideBar()
        }
      } else if let tab = tab {
        view.pleaseSwitchToTab(tab)
      }
    }
  }

  /** When slider changes */
  @IBAction override func playSliderChanges(_ sender: NSSlider) {
    // guard let event = NSApp.currentEvent else { return }
    guard !player.info.fileLoading else { return }
    super.playSliderChanges(sender)

    // seek and update time
    let percentage = 100 * sender.doubleValue / sender.maxValue
    // label
    timePreviewWhenSeek.frame.origin = CGPoint(
      x: round(sender.knobPointPosition() - timePreviewWhenSeek.frame.width / 2),
      y: playSlider.frame.origin.y + playSlider.frame.height)
    timePreviewWhenSeek.stringValue = (player.info.videoDuration! * percentage * 0.01).stringRepresentation
  }

  @objc func toolBarButtonAction(_ sender: NSButton) {
    guard let buttonType = Preference.ToolBarButton(rawValue: sender.tag) else { return }
    switch buttonType {
    case .fullScreen:
      toggleWindowFullScreen()
    case .musicMode:
      player.switchToMiniPlayer()
    case .pip:
      if #available(macOS 10.12, *) {
        if pipStatus == .inPIP {
          exitPIP()
        } else if pipStatus == .notInPIP {
          enterPIP()
        }
      }
    case .playlist:
      showPlaylistSidebar()
    case .settings:
      showSettingsSidebar()
    case .subTrack:
      quickSettingView.showSubChooseMenu(forView: sender, showLoadedSubs: true)
    }
  }

  // MARK: - Utility

  internal override func handleIINACommand(_ cmd: IINACommand) {
    super.handleIINACommand(cmd)
    switch cmd {
    case .togglePIP:
      if #available(macOS 10.12, *) {
        menuTogglePIP(.dummy)
      }
    case .videoPanel:
      menuShowVideoQuickSettings(.dummy)
    case .audioPanel:
      menuShowAudioQuickSettings(.dummy)
    case .subPanel:
      menuShowSubQuickSettings(.dummy)
    case .playlistPanel:
      menuShowPlaylistPanel(.dummy)
    case .chapterPanel:
      menuShowChaptersPanel(.dummy)
    case .toggleMusicMode:
      menuSwitchToMiniPlayer(.dummy)
    case .deleteCurrentFileHard:
      menuActionHandler.menuDeleteCurrentFileHard(.dummy)
    case .biggerWindow:
      let item = NSMenuItem()
      item.tag = 11
      menuChangeWindowSize(item)
    case .smallerWindow:
      let item = NSMenuItem()
      item.tag = 10
      menuChangeWindowSize(item)
    case .fitToScreen:
      let item = NSMenuItem()
      item.tag = 3
      menuChangeWindowSize(item)
    default:
      break
    }
  }

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

@available(macOS 10.12, *)
extension MainWindowController: PIPViewControllerDelegate {

  func enterPIP() {
    guard pipStatus != .inPIP else { return }
    pipStatus = .inPIP
    showUI()

    pipVideo = NSViewController()
    pipVideo.view = videoView
    pip.playing = player.info.isPlaying
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
    player.events.emit(.pipChanged, data: false)
  }

  func doneExitingPIP() {
    if isWindowHidden {
      window?.makeKeyAndOrderFront(self)
    }

    pipStatus = .notInPIP

    addVideoViewToWindow()

    // Similarly, we need to run a redraw here as well. We check to make sure we
    // are paused, because this causes a janky animation in either case but as
    // it's not necessary while the video is playing and significantly more
    // noticeable, we only redraw if we are paused.
    let currentTrackIsAlbumArt = player.info.currentTrack(.video)?.isAlbumart ?? false
    if player.info.isPaused || currentTrackIsAlbumArt {
      videoView.videoLayer.draw(forced: true)
    }

    updateTimer()

    isWindowMiniaturizedDueToPip = false
    isWindowHidden = false
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

protocol SidebarViewController {
  var downShift: CGFloat { get set }
}
