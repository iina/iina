//
//  MainWindowController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Mustache

fileprivate typealias PK = Preference.Key

fileprivate let TitleBarHeightNormal: CGFloat = 22
fileprivate let TitleBarHeightWithOSC: CGFloat = 22 + 24 + 10
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


class MainWindowController: NSWindowController, NSWindowDelegate {

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

  unowned var player: PlayerCore

  lazy var videoView: VideoView = {
    let view = VideoView(frame: self.window!.contentView!.bounds)
    view.player = self.player
    return view
  }()

  /** A responder handling general menu actions. */
  var menuActionHandler: MainMenuActionHandler!

  /** The quick setting sidebar (video, audio, subtitles). */
  lazy var quickSettingView: QuickSettingViewController = {
    let quickSettingView = QuickSettingViewController()
    quickSettingView.mainWindow = self
    return quickSettingView
  }()

  /** The playlist and chapter sidebar. */
  lazy var playlistView: PlaylistViewController = {
    let playListView = PlaylistViewController()
    playListView.mainWindow = self
    return playListView
  }()

  /** The control view for interactive mode. */
  var cropSettingsView: CropBoxViewController?

  private lazy var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = {
    return NSMagnificationGestureRecognizer(target: self, action: #selector(MainWindowController.handleMagnifyGesture(recognizer:)))
  }()

  /** Differentiate between single clicks and double clicks. */
  private var singleClickTimer: Timer?

  /** For auto hiding UI after a timeout. */
  var hideControlTimer: Timer?
  var hideOSDTimer: Timer?

  /** For blacking out other screens. */
  var screens: [NSScreen] = []
  var cachedScreenCount = 0
  var blackWindows: [NSWindow] = []
  
  // MARK: - Status

  /** For mpv's `geometry` option. We cache the parsed structure
   so never need to parse it every time. */
  var cachedGeometry: GeometryDef?

  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  var isResizingSidebar: Bool = false

  enum ScreenState: Equatable {
    case windowed
    case animating(toFullscreen: Bool, legacy: Bool, priorWindowedFrame: NSRect)
    case fullscreen(legacy: Bool, priorWindowedFrame: NSRect)

    var isFullscreen: Bool {
      switch self {
      case .fullscreen: return true
      case .windowed, .animating: return false
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
        case .windowed:
          fatalError("too much caching. Lets be more efficient and only write to this when necessary")
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

  var screenState: ScreenState = .windowed {
    didSet {
      switch screenState {
      case .fullscreen: player.mpv.setFlag(MPVOption.Window.fullscreen, true)
      case .animating:  break
      case .windowed:   player.mpv.setFlag(MPVOption.Window.fullscreen, false)
      }
    }
  }

  var isOntop: Bool = false {
    didSet {
      player.mpv.setFlag(MPVOption.Window.ontop, isOntop)
    }
  }

  var pipStatus = PIPStatus.notInPIP
  var isInInteractiveMode: Bool = false
  var isVideoLoaded: Bool = false

  // might use another obj to handle slider?
  var isMouseInWindow: Bool = false
  var isMouseInSlider: Bool = false

  var isFastforwarding: Bool = false

  var isPausedDueToInactive: Bool = false
  var isPausedDueToMiniaturization: Bool = false

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

  /** We need to pause the video when a user starts seeking by scrolling.
   This property records whether the video is paused initially so we can
   recover the status when scrolling finished. */
  var wasPlayingWhenSeekBegan: Bool?
  
  var mouseExitEnterCount = 0

  /** For force touch action */
  var isCurrentPressInSecondStage = false

  /** Whether current osd needs user interaction to be dismissed */
  var isShowingPersistentOSD = false

  // MARK: - Enums

  // Animation state

  /// Animation state of he hide/show part
  enum UIAnimationState {
    case shown, hidden, willShow, willHide
  }

  var animationState: UIAnimationState = .shown
  var osdAnimationState: UIAnimationState = .hidden
  var sidebarAnimationState: UIAnimationState = .hidden

  // Scroll direction

  /** The direction of current scrolling event. */
  enum ScrollDirection {
    case horizontal
    case vertical
  }

  var scrollDirection: ScrollDirection?

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

  /** Observers added to `UserDefauts.standard`. */
  private var notificationObservers: [NotificationCenter: [NSObjectProtocol]] = [:]

  /** Cached user default values */
  private var oscPosition: Preference.OSCPosition
  private var oscIsInitialized = false
  private var useExtractSeek: Preference.SeekOption
  private var relativeSeekAmount: Int
  private var volumeScrollAmount: Int
  private var horizontalScrollAction: Preference.ScrollAction
  private var verticalScrollAction: Preference.ScrollAction
  private var arrowBtnFunction: Preference.ArrowButtonAction
  private var singleClickAction: Preference.MouseClickAction
  private var doubleClickAction: Preference.MouseClickAction
  private var pinchAction: Preference.PinchAction
  private var followGlobalSeekTypeWhenAdjustSlider: Bool
  var displayTimeAndBatteryInFullScreen: Bool

  /** A list of observed preference keys. */
  private let observedPrefKeys: [Preference.Key] = [
    .themeMaterial,
    .oscPosition,
    .showChapterPos,
    .useExactSeek,
    .relativeSeekAmount,
    .volumeScrollAmount,
    .horizontalScrollAction,
    .verticalScrollAction,
    .arrowButtonAction,
    .singleClickAction,
    .doubleClickAction,
    .pinchAction,
    .showRemainingTime,
    .blackOutMonitor,
    .alwaysFloatOnTop,
    .useLegacyFullScreen,
    .maxVolume,
    .displayTimeAndBatteryInFullScreen,
    .controlBarToolbarButtons
  ]

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    switch keyPath {

    case PK.themeMaterial.rawValue:
      if let newValue = change[.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
      }

    case PK.oscPosition.rawValue:
      if let newValue = change[.newKey] as? Int {
        setupOnScreenController(withPosition: Preference.OSCPosition(rawValue: newValue) ?? .floating)
      }

    case PK.showChapterPos.rawValue:
      if let newValue = change[.newKey] as? Bool {
        (playSlider.cell as! PlaySliderCell).drawChapters = newValue
      }

    case PK.useExactSeek.rawValue:
      if let newValue = change[.newKey] as? Int {
        useExtractSeek = Preference.SeekOption(rawValue: newValue)!
      }

    case PK.relativeSeekAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        relativeSeekAmount = newValue.clamped(to: 1...5)
      }

    case PK.volumeScrollAmount.rawValue:
      if let newValue = change[.newKey] as? Int {
        volumeScrollAmount = newValue.clamped(to: 1...4)
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

    case PK.singleClickAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        singleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }

    case PK.doubleClickAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        doubleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }

    case PK.pinchAction.rawValue:
      if let newValue = change[.newKey] as? Int {
        pinchAction = Preference.PinchAction(rawValue: newValue)!
      }

    case PK.showRemainingTime.rawValue:
      if let newValue = change[.newKey] as? Bool {
        rightLabel.mode = newValue ? .remaining : .duration
      }

    case PK.blackOutMonitor.rawValue:
      if let newValue = change[.newKey] as? Bool {
        if screenState.isFullscreen {
          newValue ? blackOutOtherMonitors() : removeBlackWindow()
        }
      }

    case PK.alwaysFloatOnTop.rawValue:
      if let newValue = change[.newKey] as? Bool {
        if !player.info.isPaused {
          self.isOntop = newValue
          setWindowFloatingOnTop(newValue)
        }
      }

    case PK.useLegacyFullScreen.rawValue:
      resetCollectionBehavior()

    case PK.maxVolume.rawValue:
      if let newValue = change[.newKey] as? Int {
        volumeSlider.maxValue = Double(newValue)
        if player.mpv.getDouble(MPVOption.Audio.volume) > Double(newValue) {
          player.mpv.setDouble(MPVOption.Audio.volume, Double(newValue))
        }
      }

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

  @IBOutlet weak var sideBarRightConstraint: NSLayoutConstraint!
  @IBOutlet weak var sideBarWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var bottomBarBottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var titleBarHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var oscTopMainViewTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var fragControlViewMiddleButtons1Constraint: NSLayoutConstraint!
  @IBOutlet weak var fragControlViewMiddleButtons2Constraint: NSLayoutConstraint!

  var osdProgressBarWidthConstraint: NSLayoutConstraint!

  @IBOutlet weak var titleBarView: NSVisualEffectView!
  @IBOutlet weak var titleBarBottomBorder: NSBox!

  @IBOutlet weak var controlBarFloating: ControlBarView!
  @IBOutlet weak var controlBarBottom: NSVisualEffectView!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var playSlider: NSSlider!
  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var timePreviewWhenSeek: NSTextField!
  @IBOutlet weak var muteButton: NSButton!
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

  @IBOutlet weak var rightLabel: DurationDisplayTextField!
  @IBOutlet weak var leftLabel: NSTextField!
  @IBOutlet weak var leftArrowLabel: NSTextField!
  @IBOutlet weak var rightArrowLabel: NSTextField!

  @IBOutlet weak var osdVisualEffectView: NSVisualEffectView!
  @IBOutlet weak var osdStackView: NSStackView!
  @IBOutlet weak var osdLabel: NSTextField!
  @IBOutlet weak var osdAccessoryView: NSView!
  @IBOutlet weak var osdAccessoryText: NSTextField!
  @IBOutlet weak var osdAccessoryProgress: NSProgressIndicator!

  @IBOutlet weak var pipOverlayView: NSVisualEffectView!

  lazy var subPopoverView = playlistView.subPopover?.contentViewController?.view

  var videoViewConstraints: [NSLayoutConstraint.Attribute: NSLayoutConstraint] = [:]
  private var oscFloatingLeadingTrailingConstraint: [NSLayoutConstraint]?

  // MARK: - PIP

  @available(macOS 10.12, *)
  lazy var pip: PIPViewController = {
    let pip = PIPViewController()
    pip.delegate = self
    return pip
  }()

  var pipVideo: NSViewController!

  // MARK: - Initialization

  init(playerCore: PlayerCore) {
    self.player = playerCore

    oscPosition = Preference.enum(for: .oscPosition)
    relativeSeekAmount = Preference.integer(for: .relativeSeekAmount)
    volumeScrollAmount = Preference.integer(for: .volumeScrollAmount)
    horizontalScrollAction = Preference.enum(for: .horizontalScrollAction)
    verticalScrollAction = Preference.enum(for: .verticalScrollAction)
    useExtractSeek = Preference.enum(for: .useExactSeek)
    relativeSeekAmount = Preference.integer(for: .relativeSeekAmount)
    volumeScrollAmount = Preference.integer(for: .volumeScrollAmount)
    arrowBtnFunction = Preference.enum(for: .arrowButtonAction)
    singleClickAction = Preference.enum(for: .singleClickAction)
    doubleClickAction = Preference.enum(for: .doubleClickAction)
    pinchAction = Preference.enum(for: .pinchAction)
    followGlobalSeekTypeWhenAdjustSlider = Preference.bool(for: .followGlobalSeekTypeWhenAdjustSlider)
    displayTimeAndBatteryInFullScreen = Preference.bool(for: .displayTimeAndBatteryInFullScreen)

    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {

    super.windowDidLoad()

    guard let w = self.window else { return }

    w.initialFirstResponder = nil

    // Insert `menuActionHandler` into the responder chain
    menuActionHandler = MainMenuActionHandler(playerCore: player)
    let responder = w.nextResponder
    w.nextResponder = menuActionHandler
    menuActionHandler.nextResponder = responder

    w.styleMask.insert(.fullSizeContentView)
    w.titlebarAppearsTransparent = true

    // need to deal with control bar, so we handle it manually
    // w.isMovableByWindowBackground  = true

    // set background color to black
    w.backgroundColor = .black

    titleBarView.layerContentsRedrawPolicy = .onSetNeedsDisplay

    updateTitle()

    // set material
    setMaterial(Preference.enum(for: .themeMaterial))

    // size
    w.minSize = minSize
    if let wf = windowFrameFromGeometry() {
      w.setFrame(wf, display: false)
    }

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

    guard let cv = w.contentView else { return }

    // video view
    cv.autoresizesSubviews = false
    cv.addSubview(videoView, positioned: .below, relativeTo: nil)
    videoView.translatesAutoresizingMaskIntoConstraints = false
    // add constraints
    ([.top, .bottom, .left, .right] as [NSLayoutConstraint.Attribute]).forEach { attr in
      videoViewConstraints[attr] = NSLayoutConstraint(item: videoView, attribute: attr, relatedBy: .equal, toItem: cv, attribute: attr, multiplier: 1, constant: 0)
      videoViewConstraints[attr]!.isActive = true
    }

    w.setIsVisible(true)
    videoView.videoLayer.display()

    // gesture recognizer
    cv.addGestureRecognizer(magnificationGestureRecognizer)

    // start mpv opengl_cb
    player.startMPVOpenGLCB(videoView)

    // init quick setting view now
    let _ = quickSettingView

    // buffer indicator view
    bufferIndicatorView.layer?.cornerRadius = 10
    updateBufferIndicatorView()

    // thumbnail peek view
    w.contentView?.addSubview(thumbnailPeekView)
    thumbnailPeekView.isHidden = true

    // other initialization
    cachedScreenCount = NSScreen.screens.count
    [titleBarView, osdVisualEffectView, controlBarBottom, controlBarFloating, sideBarView, osdVisualEffectView, pipOverlayView].forEach {
      $0?.state = .active
    }
    // hide other views
    osdVisualEffectView.isHidden = true
    osdVisualEffectView.layer?.cornerRadius = 10
    additionalInfoView.layer?.cornerRadius = 10
    leftArrowLabel.isHidden = true
    rightArrowLabel.isHidden = true
    timePreviewWhenSeek.isHidden = true
    bottomView.isHidden = true
    pipOverlayView.isHidden = true
    rightLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    osdProgressBarWidthConstraint = NSLayoutConstraint(item: osdAccessoryProgress, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 150)

    // add user default observers
    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    // add notification observers

    notificationCenter(.default, addObserverfor: .iinaFileLoaded, object: player) { [unowned self] _ in
      self.updateTitle()
      self.quickSettingView.reload()
    }

    notificationCenter(.default, addObserverfor: .iinaMediaTitleChanged, object: player) { [unowned self] _ in
      self.updateTitle()
    }

    notificationCenter(.default, addObserverfor: NSApplication.didChangeScreenParametersNotification) { [unowned self] _ in
      // This observer handles a situation that the user connected a new screen or removed a screen
      let screenCount = NSScreen.screens.count
      if self.screenState.isFullscreen && Preference.bool(for: .blackOutMonitor) && self.cachedScreenCount != screenCount {
        self.removeBlackWindow()
        self.blackOutOtherMonitors()
      }
      // Update the cached value
      self.cachedScreenCount = screenCount
    }

  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
      for (center, observers) in self.notificationObservers {
        for observer in observers {
          center.removeObserver(observer)
        }
      }
    }
  }

  private func notificationCenter(_ center: NotificationCenter, addObserverfor name: NSNotification.Name, object: Any? = nil, using block: @escaping (Notification) -> Void) {
    let observer = center.addObserver(forName: name, object: object, queue: .main, using: block)
    if notificationObservers[center] == nil {
      notificationObservers[center] = []
    }
    notificationObservers[center]!.append(observer)
  }

  private func setupOSCToolbarButtons(_ buttons: [Preference.ToolBarButton]) {
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
      let buttonWidth = buttons.count == 5 ? "20" : "24"
      Utility.quickConstraints(["H:[btn(\(buttonWidth))]", "V:[btn(24)]"], ["btn": button])
      fragToolbarView.addView(button, in: .trailing)
    }
  }

  private func setupOnScreenController(withPosition newPosition: Preference.OSCPosition) {

    guard !oscIsInitialized || oscPosition != newPosition else { return }
    oscIsInitialized = true

    var isCurrentControlBarHidden = false

    let isSwitchingToTop = newPosition == .top
    let isSwitchingFromTop = oscPosition == .top
    let isFloating = newPosition == .floating

    if let cb = currentControlBar {
      // remove current osc view from fadeable views
      fadeableViews = fadeableViews.filter { $0 != cb }
      // record hidden status
      isCurrentControlBarHidden = cb.isHidden
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

    let isInFullScreen = screenState.isFullscreen

    if isSwitchingToTop {
      if isInFullScreen {
        addBackTitlebarViewToFadeableViews()
        oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTopInFullScreen
        titleBarHeightConstraint.constant = TitleBarHeightWithOSCInFullScreen
      } else {
        oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTop
        titleBarHeightConstraint.constant = TitleBarHeightWithOSC
      }
      titleBarBottomBorder.isHidden = true
    } else {
      titleBarBottomBorder.isHidden = false
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
      oscFloatingTopView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragVolumeView)
      oscFloatingTopView.setVisibilityPriority(.detachOnlyIfNecessary, for: fragToolbarView)
      oscFloatingTopView.setClippingResistancePriority(.defaultLow, for: .horizontal)
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
      currentControlBar!.isHidden = isCurrentControlBarHidden
    }

    if isFloating {
      fragControlViewMiddleButtons1Constraint.constant = 24
      fragControlViewMiddleButtons2Constraint.constant = 24
      oscFloatingLeadingTrailingConstraint = NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=10)-[v]-(>=10)-|",
                                                                            options: [], metrics: nil, views: ["v": controlBarFloating])
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

  // MARK: - Mouse / Trackpad event

  override func keyDown(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    if let kb = PlayerCore.keyBindings[keyCode] {
      handleKeyBinding(kb)
    } else {
      super.keyDown(with: event)
    }
  }

  func handleKeyBinding(_ keyBinding: KeyMapping) {
    if keyBinding.isIINACommand {
      // - IINA command
      if let iinaCommand = IINACommand(rawValue: keyBinding.rawAction) {
        handleIINACommand(iinaCommand)
      } else {
        Logger.log("Unknown iina command \(keyBinding.rawAction)", level: .error)
      }
    } else {
      // - mpv command
      let returnValue: Int32
      // execute the command
      switch keyBinding.action[0] {
      case MPVCommand.abLoop.rawValue:
        player.abLoop()
        returnValue = 0
      default:
        returnValue = player.mpv.command(rawString: keyBinding.rawAction)
      }
      // handle return value, display osd if needed
      if returnValue == 0 {
        // screenshot
        if keyBinding.action[0] == MPVCommand.screenshot.rawValue {
          displayOSD(.screenshot)
        }
      } else {
        Logger.log("Return value \(returnValue) when executing key command \(keyBinding.rawAction)", level: .error)
      }
    }
  }

  override func pressureChange(with event: NSEvent) {
    if isCurrentPressInSecondStage == false && event.stage == 2 {
      performMouseAction(Preference.enum(for: .forceTouchAction))
      isCurrentPressInSecondStage = true
    } else if event.stage == 1 {
      isCurrentPressInSecondStage = false
    }
  }

  override func mouseDown(with event: NSEvent) {
    // do nothing if it's related to floating OSC
    guard !controlBarFloating.isDragging else { return }
    // record current mouse pos
    mousePosRelatedToWindow = event.locationInWindow
    // playlist resizing
    if sideBarStatus == .playlist {
      let sf = sideBarView.frame
      if NSPointInRect(mousePosRelatedToWindow!, NSMakeRect(sf.origin.x-4, sf.origin.y, 4, sf.height)) {
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
    } else if !screenState.isFullscreen {
      // move the window by dragging
      isDragging = true
      guard !controlBarFloating.isDragging else { return }
      if mousePosRelatedToWindow != nil {
        window?.performDrag(with: event)
      }
    }
  }

  override func mouseUp(with event: NSEvent) {
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
      if !isMouseEvent(event, inAnyOf: [sideBarView, subPopoverView]) && sideBarStatus != .hidden {
        // if sidebar is shown, hide it first
        hideSideBar()
      } else {
        if event.clickCount == 1 {
          // single click or first click of a double click
          // disable single click for sideBar / OSC / titleBar
          guard !isMouseEvent(event, inAnyOf: [sideBarView, currentControlBar, titleBarView, subPopoverView]) else { return }
          // single click
          if doubleClickAction == .none {
            // if double click action is none, it's safe to perform action immediately
            performMouseAction(singleClickAction)
          } else {
            // else start a timer to check for double clicking
            singleClickTimer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval, target: self, selector: #selector(self.performMouseActionLater(_:)), userInfo: singleClickAction, repeats: false)
            mouseExitEnterCount = 0
          }
        } else if event.clickCount == 2 {
          // double click
          // disable double click for sideBar / OSC
          guard !isMouseEvent(event, inAnyOf: [sideBarView, currentControlBar, titleBarView, subPopoverView]) else { return }
          // double click
          guard doubleClickAction != .none else { return }
          // if already scheduled a single click timer, invalidate it
          if let timer = singleClickTimer {
            timer.invalidate()
            singleClickTimer = nil
          }
          performMouseAction(doubleClickAction)
        } else {
          return
        }
      }
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    // Disable mouseUp for sideBar / OSC / titleBar
    guard !isMouseEvent(event, inAnyOf: [sideBarView, currentControlBar, titleBarView, subPopoverView]) else { return }
    
    performMouseAction(Preference.enum(for: .rightClickAction))
  }

  override func otherMouseUp(with event: NSEvent) {
    if event.buttonNumber == 2 {
      performMouseAction(Preference.enum(for: .middleClickAction))
    } else {
      super.otherMouseUp(with: event)
    }
  }

  /**
   Being called to perform single click action after timeout.

   - SeeAlso:
   mouseUp(with:)
   */
  @objc private func performMouseActionLater(_ timer: Timer) {
    guard let action = timer.userInfo as? Preference.MouseClickAction else { return }
    if mouseExitEnterCount >= 2 && action == .hideOSC {
      // the counter being greater than or equal to 2 means that the mouse re-entered the window
      // `showUI()` must be called due to the movement in the window, thus `hideOSC` action should be cancelled
      return
    }
    performMouseAction(action)
  }

  private func performMouseAction(_ action: Preference.MouseClickAction) {
    switch action {
    case .none:
      break
    case .fullscreen:
      toggleWindowFullScreen()
    case .pause:
      player.togglePause(nil)
    case .hideOSC:
      hideUI()
    }
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

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard !isMouseEvent(event, inAnyOf: [sideBarView, titleBarView, subPopoverView]) else { return }
    if isMouseEvent(event, inAnyOf: [currentControlBar]) && !isMouseEvent(event, inAnyOf: [fragVolumeView, fragSliderView]) { return }

    let isMouse = event.phase.isEmpty
    let isTrackpadBegan = event.phase.contains(.began)
    let isTrackpadEnd = event.phase.contains(.ended)

    // determine direction

    if isMouse || isTrackpadBegan {
      if event.scrollingDeltaX != 0 {
        scrollDirection = .horizontal
      } else if event.scrollingDeltaY != 0 {
        scrollDirection = .vertical
      }
    } else if isTrackpadEnd {
      scrollDirection = nil
    }

    let scrollAction = scrollDirection == .horizontal ? horizontalScrollAction : verticalScrollAction

    // pause video when seek begins.

    if scrollAction == .seek && isTrackpadBegan {
      // record pause status
      wasPlayingWhenSeekBegan = !player.info.isPaused
      if wasPlayingWhenSeekBegan! {
        player.togglePause(true)
      }
    }

    if isTrackpadEnd && wasPlayingWhenSeekBegan != nil {
      // only resume playback when it was playing when began
      if wasPlayingWhenSeekBegan! {
        player.togglePause(false)
      }
      wasPlayingWhenSeekBegan = nil
    }

    // handle the delta value

    let isPrecise = event.hasPreciseScrollingDeltas
    let isNatural = event.isDirectionInvertedFromDevice

    var deltaX = isPrecise ? Double(event.scrollingDeltaX) : event.scrollingDeltaX.unifiedDouble
    var deltaY = isPrecise ? Double(event.scrollingDeltaY) : event.scrollingDeltaY.unifiedDouble * 2

    if isNatural {
      deltaY = -deltaY
    } else {
      deltaX = -deltaX
    }

    let delta = scrollDirection == .horizontal ? deltaX : deltaY

    // perform action

    if (isMouseEvent(event, inAnyOf: [fragSliderView]) && playSlider.isEnabled) || scrollAction == .seek {
      let seekAmount = (isMouse ? AppData.seekAmountMapMouse : AppData.seekAmountMap)[relativeSeekAmount] * delta
      player.seek(relativeSecond: seekAmount, option: useExtractSeek)
    } else if (isMouseEvent(event, inAnyOf: [fragVolumeView]) && volumeSlider.isEnabled) || scrollAction == .volume {
      // don't use precised delta for mouse
      let newVolume = player.info.volume + (isMouse ? delta : AppData.volumeMap[volumeScrollAmount] * delta)
      player.setVolume(newVolume)
      volumeSlider.doubleValue = newVolume
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
        if !isEnlarge {
          recognizer.state = .recognized
          self.toggleWindowFullScreen()
        }
      }
    case .windowSize:
      if screenState.isFullscreen { return }

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

  /** A method being called when window open. Pretend to be a window delegate. */
  func windowDidOpen() {
    window!.makeMain()
    window!.makeKeyAndOrderFront(nil)
    resetCollectionBehavior()
    // update buffer indicator view
    updateBufferIndicatorView()
    // start tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
    if cv.trackingAreas.isEmpty {
      cv.addTrackingArea(NSTrackingArea(rect: cv.bounds,
                                        options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                        owner: self, userInfo: ["obj": 0]))
    }
    if playSlider.trackingAreas.isEmpty {
      playSlider.addTrackingArea(NSTrackingArea(rect: playSlider.bounds,
                                                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                                owner: self, userInfo: ["obj": 1]))
    }

    // update timer
    updateTimer()
    // always on top
    if Preference.bool(for: .alwaysFloatOnTop) {
      isOntop = true
      setWindowFloatingOnTop(true)
    }
    // truncate middle for title
    if let attrTitle = titleTextField?.attributedStringValue.mutableCopy() as? NSMutableAttributedString, attrTitle.length > 0 {
      let p = attrTitle.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSMutableParagraphStyle
      p.lineBreakMode = .byTruncatingMiddle
      attrTitle.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: attrTitle.length))
    }
  }

  func windowWillClose(_ notification: Notification) {
    // Close PIP
    if pipStatus == .inPIP {
      if #available(macOS 10.12, *) {
        exitPIP()
      }
    }
    // stop playing
    if !player.isMpvTerminated {
      player.savePlaybackPosition()
      player.stop()
      // videoView.stopDisplayLink()
    }
    player.info.currentFolder = nil
    player.info.matchedSubs.removeAll()
    // stop tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
    cv.trackingAreas.forEach(cv.removeTrackingArea)
    playSlider.trackingAreas.forEach(playSlider.removeTrackingArea)
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
      window.animator().setFrame(screen.frame, display: true)
    }, completionHandler: .none)

  }

  func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
    if NSMenu.menuBarVisible() {
      NSMenu.setMenuBarVisible(false)
    }
    let priorWindowedFrame = screenState.priorWindowedFrame!

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = duration
      window.animator().setFrame(priorWindowedFrame, display: true)
    }, completionHandler: nil)

    NSMenu.setMenuBarVisible(true)
  }

  func windowWillEnterFullScreen(_ notification: Notification) {
    if isInInteractiveMode {
      exitInteractiveMode(immediately: true)
    }

    // Let mpv decide the correct render region in full screen
    player.mpv.setFlag(MPVOption.Window.keepaspect, true)

    // Set the appearance to match the theme so the titlebar matches the theme
    switch(Preference.enum(for: .themeMaterial) as Preference.Theme) {
    case .dark, .ultraDark: window!.appearance = NSAppearance(named: .vibrantDark)
    case .light, .mediumLight: window!.appearance = NSAppearance(named: .vibrantLight)
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
    removeStandardButtonsFromFadeableViews()
    
    setWindowFloatingOnTop(false)

    thumbnailPeekView.isHidden = true
    timePreviewWhenSeek.isHidden = true
    isMouseInSlider = false

    let isLegacyFullScreen = notification.name == .iinaLegacyFullScreen
    screenState.startAnimatingToFullScreen(legacy: isLegacyFullScreen, priorWindowedFrame: window!.frame)

    // Exit PIP if necessary
    if pipStatus == .inPIP,
      #available(macOS 10.12, *) {
      exitPIP()
    }

    videoView.videoLayer.mpvGLQueue.suspend()
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    screenState.finishAnimating()

    videoView.videoLayer.mpvGLQueue.resume()

    // we must block the mpv rendering queue to do the following atomically
    videoView.videoLayer.mpvGLQueue.async {
      DispatchQueue.main.sync {
        for (_, constraint) in self.videoViewConstraints {
          constraint.constant = 0
        }
        self.videoView.needsLayout = true
        self.videoView.layoutSubtreeIfNeeded()
        self.videoView.videoLayer.display()
      }
    }

    if Preference.bool(for: .blackOutMonitor) {
      blackOutOtherMonitors()
    }

    if Preference.bool(for: .displayTimeAndBatteryInFullScreen) {
      fadeableViews.append(additionalInfoView)
    }

    if Preference.bool(for: .playWhenEnteringFullScreen) && player.info.isPaused {
      player.togglePause(false)
    }

    if #available(macOS 10.12.2, *) {
      player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: true)
    }
    
    updateWindowParametersForMPV()
  }

  func windowWillExitFullScreen(_ notification: Notification) {
    if isInInteractiveMode {
      exitInteractiveMode(immediately: true)
    }

    // show titleBarView
    if oscPosition == .top {
      oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTop
      titleBarHeightConstraint.constant = TitleBarHeightWithOSC
    } else {
      addBackTitlebarViewToFadeableViews()
      titleBarView.isHidden = false
      animationState = .shown
    }
    addBackStandardButtonsToFadeableViews()

    thumbnailPeekView.isHidden = true
    timePreviewWhenSeek.isHidden = true
    additionalInfoView.isHidden = true
    isMouseInSlider = false

    screenState.startAnimatingToWindow()

    videoView.videoLayer.mpvGLQueue.suspend()
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    videoView.videoLayer.mpvGLQueue.resume()

    videoView.videoLayer.mpvGLQueue.async {
      // reset `keepaspect`
      self.player.mpv.setFlag(MPVOption.Window.keepaspect, false)
      DispatchQueue.main.sync {
        for (_, constraint) in self.videoViewConstraints {
          constraint.constant = 0
        }
        self.videoView.needsLayout = true
        self.videoView.layoutSubtreeIfNeeded()
        self.videoView.videoLayer.display()
      }
    }

    screenState.finishAnimating()

    if Preference.bool(for: .blackOutMonitor) {
      removeBlackWindow()
    }

    if Preference.bool(for: .pauseWhenLeavingFullScreen) && !player.info.isPaused {
      player.togglePause(true)
    }

    if #available(macOS 10.12.2, *) {
      player.touchBarSupport.toggleTouchBarEsc(enteringFullScr: false)
    }

    // restore ontop status
    if !player.info.isPaused {
      setWindowFloatingOnTop(isOntop)
    }

    if let index = fadeableViews.index(of: additionalInfoView) {
      fadeableViews.remove(at: index)
    }

    resetCollectionBehavior()
    updateWindowParametersForMPV()
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
    if case let .animating(toFullScreen, _, _) = screenState {
      let aspect: NSSize
      let targetFrame: NSRect
      if toFullScreen {
        aspect = window.aspectRatio == .zero ? window.frame.size : window.aspectRatio
        targetFrame = aspect.shrink(toSize: window.frame.size).centeredRect(in: window.frame)
      } else {
        aspect = window.screen?.frame.size ?? NSScreen.main!.frame.size
        targetFrame = aspect.grow(toSize: window.frame.size).centeredRect(in: window.frame)
      }

      setConstraintsForVideoView([
        .left: targetFrame.minX,
        .right:  targetFrame.maxX - window.frame.width,
        .bottom: -targetFrame.minY,
        .top: window.frame.height - targetFrame.maxY
      ])
    }

    // is paused or very low fps (assume audio file), draw new frame
    if player.info.isPaused || player.currentMediaIsAudio == .isAudio {
      videoView.videoLayer.draw()
    }

    // interactive mode
    if (isInInteractiveMode) {
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
  }

  // resize framebuffer in videoView after resizing.
  func windowDidEndLiveResize(_ notification: Notification) {
    videoView.videoSize = window!.convertToBacking(videoView.bounds).size
    updateWindowParametersForMPV()
  }

  func windowDidChangeBackingProperties(_ notification: Notification) {
    if let oldScale = (notification.userInfo?[NSWindow.oldScaleFactorUserInfoKey] as? NSNumber)?.doubleValue,
      oldScale != Double(window!.backingScaleFactor) {
      videoView.videoLayer.contentsScale = window!.backingScaleFactor
    }

  }

  // MARK: - Window delegate: Active status

  func windowDidBecomeKey(_ notification: Notification) {
    window!.makeFirstResponder(window!)
    if Preference.bool(for: .pauseWhenInactive) && isPausedDueToInactive {
      player.togglePause(false)
      isPausedDueToInactive = false
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    // keyWindow is nil: The whole app is inactive
    // keyWindow is another MainWindow: Switched to another video window
    if NSApp.keyWindow == nil ||
      (NSApp.keyWindow?.windowController is MainWindowController ||
        (NSApp.keyWindow?.windowController is MiniPlayerWindowController && NSApp.keyWindow?.windowController != player.miniPlayer)) {
      if Preference.bool(for: .pauseWhenInactive), !player.info.isPaused {
        player.togglePause(true)
        isPausedDueToInactive = true
      }
    }
  }

  func windowDidBecomeMain(_ notification: Notification) {
    PlayerCore.lastActive = player
    if screenState.isFullscreen && Preference.bool(for: .blackOutMonitor) {
      blackOutOtherMonitors()
    }
    NotificationCenter.default.post(name: .iinaMainWindowChanged, object: nil)
  }

  func windowDidResignMain(_ notification: Notification) {
    if Preference.bool(for: .blackOutMonitor) {
      removeBlackWindow()
    }
    NotificationCenter.default.post(name: .iinaMainWindowChanged, object: nil)
  }

  func windowWillMiniaturize(_ notification: Notification) {
    if Preference.bool(for: .pauseWhenMinimized), !player.info.isPaused {
      isPausedDueToMiniaturization = true
      player.togglePause(true)
    }
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    if Preference.bool(for: .pauseWhenMinimized) && isPausedDueToMiniaturization {
      player.togglePause(false)
      isPausedDueToMiniaturization = false
    }
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
    fadeableViews.forEach { (v) in
      v.isHidden = false
    }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = UIAnimationDuration
      fadeableViews.forEach { (v) in
        v.animator().alphaValue = 0
      }
      if !self.screenState.isFullscreen {
        titleTextField?.animator().alphaValue = 0
      }
    }) {
      // if no interrupt then hide animation
      if self.animationState == .willHide {
        self.fadeableViews.forEach { (v) in
          v.isHidden = true
        }
        self.animationState = .hidden
      }
    }
  }

  private func showUI() {
    animationState = .willShow
    fadeableViews.forEach { (v) in
      v.isHidden = false
    }
    if !player.isInMiniPlayer && screenState.isFullscreen && displayTimeAndBatteryInFullScreen {
      player.syncUI(.additionalInfo)
    }
    standardWindowButtons.forEach { $0.isEnabled = true }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = UIAnimationDuration
      fadeableViews.forEach { (v) in
        v.animator().alphaValue = 1
      }
      if !screenState.isFullscreen {
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

  func updateTitle() {
    if player.info.isNetworkResource {
      window?.title = player.getMediaTitle()
    } else {
      window?.representedURL = player.info.currentURL
      window?.setTitleWithRepresentedFilename(player.info.currentURL?.path ?? "")
    }
    addDocIconToFadeableViews()
  }

  // MARK: - UI: OSD

  func displayOSD(_ message: OSDMessage, autoHide: Bool = true, accessoryView: NSView? = nil) {
    guard player.displayOSD && !isShowingPersistentOSD else { return }

    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    osdAnimationState = .shown
    [osdAccessoryText, osdAccessoryProgress].forEach { $0.isHidden = true }

    let (osdString, osdType) = message.message()

    let osdTextSize = Preference.float(for: .osdTextSize)
    osdLabel.font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(osdTextSize), weight: .regular)
    osdLabel.stringValue = osdString

    switch osdType {
    case .normal:
      osdStackView.setVisibilityPriority(.notVisible, for: osdAccessoryView)
    case .withProgress(let value):
      NSLayoutConstraint.activate([osdProgressBarWidthConstraint])
      osdStackView.setVisibilityPriority(.mustHold, for: osdAccessoryView)
      osdAccessoryProgress.isHidden = false
      osdAccessoryProgress.doubleValue = value
    case .withText(let text):
      NSLayoutConstraint.deactivate([osdProgressBarWidthConstraint])

      // data for mustache redering
      let osdData: [String: String] = [
        "duration": player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "position": player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).description,
        "chapterCount": player.info.chapters.count.description
      ]

      osdStackView.setVisibilityPriority(.mustHold, for: osdAccessoryView)
      osdAccessoryText.isHidden = false
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
      
      accessoryView.appearance = NSAppearance(named: .vibrantDark)
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
      let timeout = Preference.float(for: .osdAutoHideTimeout)
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
      }
    }
    isShowingPersistentOSD = false
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
      context.duration = SideBarAnimationDuration
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
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
      context.duration = animate ? SideBarAnimationDuration : 0
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
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
    if let index = (self.fadeableViews.index { $0 === titleBarView }) {
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
  // We should try to add it everytime when window title changed.
  private func addDocIconToFadeableViews() {
    if let docIcon = window?.standardWindowButton(.documentIconButton), !fadeableViews.contains(docIcon) {
      fadeableViews.append(docIcon)
    }
  }

  // MARK: - UI: Interactive mode

  func enterInteractiveMode(_ mode: InteractiveMode, selectWholeVideoByDefault: Bool = false) {
    // prerequisites
    guard let window = window else { return }

    window.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)

    let (ow, oh) = player.originalVideoSize
    guard ow != 0 && oh != 0 else {
      Utility.showAlert("no_video_track")
      return
    }

    player.togglePause(true)
    isInInteractiveMode = true
    hideUI()

    if screenState.isFullscreen {
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
          self.videoView.videoLayer.display()
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
      context.duration = CropAnimationDuration
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
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

    player.togglePause(false)
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
      context.duration = CropAnimationDuration
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
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

  /** Display time label when mouse over slider */
  private func updateTimeLabel(_ mouseXPos: CGFloat, originalPos: NSPoint) {
    let timeLabelXPos = playSlider.frame.origin.y + 15
    timePreviewWhenSeek.frame.origin = NSPoint(x: round(mouseXPos + playSlider.frame.origin.x - timePreviewWhenSeek.frame.width / 2),
                                               y: timeLabelXPos + 1)
    let sliderFrame = playSlider.bounds
    let sliderFrameInWindow = playSlider.superview!.convert(playSlider.frame.origin, to: nil)
    var percentage = Double((mouseXPos - 3) / (sliderFrame.width - 6))
    if percentage < 0 {
      percentage = 0
    }

    if let duration = player.info.videoDuration {
      let previewTime = duration * percentage
      timePreviewWhenSeek.stringValue = previewTime.stringRepresentation

      if player.info.thumbnailsReady, let tb = player.info.getThumbnail(forSecond: previewTime.second) {
        thumbnailPeekView.isHidden = false
        thumbnailPeekView.imageView.image = tb.image
        let height = round(120 / thumbnailPeekView.imageView.image!.size.aspect)
        let yPos = (oscPosition == .top || (oscPosition == .floating && sliderFrameInWindow.y + 52 + height >= window!.frame.height)) ?
          sliderFrameInWindow.y - height : sliderFrameInWindow.y + 32
        thumbnailPeekView.frame.size = NSSize(width: 120, height: height)
        thumbnailPeekView.frame.origin = NSPoint(x: round(originalPos.x - thumbnailPeekView.frame.width / 2), y: yPos)
      } else {
        thumbnailPeekView.isHidden = true
      }
    }
  }

  /** Set material for OSC and title bar */
  private func setMaterial(_ theme: Preference.Theme?) {
    guard let theme = theme else {
      Logger.log("Nil material in setMaterial()", level: .warning)
      return
    }

    var appearance: NSAppearance? = nil
    var material: NSVisualEffectView.Material
    var isDarkTheme: Bool
    let sliderCell = playSlider.cell as? PlaySliderCell
    let volumeCell = volumeSlider.cell as? VolumeSliderCell

    switch theme {

    case .dark:
      appearance = NSAppearance(named: .vibrantDark)
      material = .dark
      isDarkTheme = true

    case .ultraDark:
      appearance = NSAppearance(named: .vibrantDark)
      material = .ultraDark
      isDarkTheme = true

    case .light:
      appearance = NSAppearance(named: .vibrantLight)
      material = .light
      isDarkTheme = false

    case .mediumLight:
      appearance = NSAppearance(named: .vibrantLight)
      material = .mediumLight
      isDarkTheme = false

    }

    sliderCell?.isInDarkTheme = isDarkTheme
    volumeCell?.isInDarkTheme = isDarkTheme

    [titleBarView, controlBarFloating, controlBarBottom, osdVisualEffectView, pipOverlayView, additionalInfoView].forEach {
      $0?.material = material
      $0?.appearance = appearance
    }

    window?.appearance = appearance
  }

  func updateBufferIndicatorView() {
    guard isWindowLoaded else { return }

    if player.info.isNetworkResource {
      bufferIndicatorView.isHidden = false
      bufferSpin.startAnimation(nil)
      bufferProgressLabel.stringValue = "Opening stream..."
      bufferDetailLabel.stringValue = ""
    } else {
      bufferIndicatorView.isHidden = true
    }
  }

  // MARK: - Window size / aspect

  /** Calculate the window frame from a parsed struct of mpv's `geometry` option. */
  func windowFrameFromGeometry(newSize: NSSize? = nil) -> NSRect? {
    // set geometry. using `!` should be safe since it passed the regex.
    if let geometry = cachedGeometry ?? player.getGeometry(), let screenFrame = NSScreen.main?.visibleFrame {
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
        winFrame.origin.x = (xSign == "+" ? x : screenFrame.width - x) + screenFrame.origin.x
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
        winFrame.origin.y = (ySign == "+" ? y : screenFrame.height - y) + screenFrame.origin.y
        if (ySign == "-") {
          winFrame.origin.y -= winFrame.height
        }
      }
      // if x and y not specified
      if geometry.x == nil && geometry.y == nil && widthOrHeightIsSet {
        winFrame.origin.x = (screenFrame.width - winFrame.width) / 2
        winFrame.origin.y = (screenFrame.height - winFrame.height) / 2
      }
      // return
      return winFrame
    } else {
      return nil
    }
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

    let frame = screenState.priorWindowedFrame ?? window.frame

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
      if Preference.bool(for: .usePhysicalResolution) {
        videoSize = window.convertFromBacking(
          NSMakeRect(window.frame.origin.x, window.frame.origin.y, CGFloat(width), CGFloat(height))).size
      }
      if player.info.justStartedFile {
        if resizeRatio < 0 {
          if let screenSize = NSScreen.main?.visibleFrame.size {
            videoSize = videoSize.shrink(toSize: screenSize)
          }
        } else {
          videoSize = videoSize.multiply(CGFloat(resizeRatio))
        }
      }
      // check screen size
      if let screenSize = NSScreen.main?.visibleFrame.size {
        videoSize = videoSize.satisfyMaxSizeWithSameAspectRatio(screenSize)
      }
      // guard min size
      videoSize = videoSize.satisfyMinSizeWithSameAspectRatio(minSize)
      // check if have geometry set
      if let wfg = windowFrameFromGeometry(newSize: videoSize) {
        rect = wfg
      } else {
        if player.info.justStartedFile, resizeRatio < 0, let screenRect = NSScreen.main?.visibleFrame {
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

    if screenState.isFullscreen {
      screenState.priorWindowedFrame = rect
    } else {
      // animated `setFrame` can be inaccurate!
      window.setFrame(rect, display: true, animate: true)
      window.setFrame(rect, display: true)
      updateWindowParametersForMPV(withFrame: rect)
    }

    // generate thumbnails after video loaded if it's the first time
    if !isVideoLoaded {
      player.generateThumbnails()
      isVideoLoaded = true
    }

    // UI and slider
    updatePlayTime(withDuration: true, andProgressBar: true)
    updateVolume()
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
    guard let window = window, screenState == .windowed else { return }
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

  func toggleWindowFullScreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    switch screenState {
    case .windowed:
      guard !player.isInMiniPlayer else { return }
      if Preference.bool(for: .useLegacyFullScreen) {
        self.legacyAnimateToFullscreen()
      } else {
        window.toggleFullScreen(self)
      }
    case let .fullscreen(_, oldFrame):
      if Preference.bool(for: .useLegacyFullScreen) {
        self.legacyAnimateToWindowed(framePriorToBeingInFullscreen: oldFrame)
      } else {
        window.toggleFullScreen(self)
      }
    default:
      return
    }
  }

  private func legacyAnimateToWindowed(framePriorToBeingInFullscreen: NSRect) {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }

    // call delegate
    windowWillExitFullScreen(Notification(name: .iinaLegacyFullScreen))
    // stylemask
    window.styleMask.remove(.borderless)
    window.styleMask.remove(.fullScreen)
    // cancel auto hide for menu and dock
    NSApp.presentationOptions.remove(.autoHideMenuBar)
    NSApp.presentationOptions.remove(.autoHideDock)
    // restore window frame ans aspect ratio
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

  private func legacyAnimateToFullscreen() {
    guard let window = self.window else { fatalError("make sure the window exists before animating") }
    // call delegate
    windowWillEnterFullScreen(Notification(name: .iinaLegacyFullScreen))
    // stylemask
    window.styleMask.insert(.borderless)
    window.styleMask.insert(.fullScreen)
    // cancel aspect ratio
    window.resizeIncrements = NSSize(width: 1, height: 1)
    // auto hide menubar and dock
    NSApp.presentationOptions.insert(.autoHideMenuBar)
    NSApp.presentationOptions.insert(.autoHideDock)
    // set frame
    let screen = window.screen ?? NSScreen.main!
    window.setFrame(NSRect(origin: .zero, size: screen.frame.size), display: true, animate: true)
    // call delegate
    windowDidEnterFullScreen(Notification(name: .iinaLegacyFullScreen))
  }

  /** This method will not set `isOntop`! */
  func setWindowFloatingOnTop(_ onTop: Bool) {
    guard let window = window else { return }
    guard !screenState.isFullscreen else { return }
    if onTop {
      window.level = .iinaFloating
    } else {
      window.level = .normal
    }

    resetCollectionBehavior()

    // don't know why they will be disabled
    standardWindowButtons.forEach { $0.isEnabled = true }
  }

  // MARK: - Sync UI with playback

  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    guard let duration = player.info.videoDuration, let pos = player.info.videoPosition else {
      Logger.fatal("video info not available")
    }
    let percentage = (pos.second / duration.second) * 100
    leftLabel.stringValue = pos.stringRepresentation
    rightLabel.updateText(with: duration, given: pos)
    if andProgressBar {
      playSlider.doubleValue = percentage
      if #available(macOS 10.12.2, *) {
        player.touchBarSupport.touchBarPlaySlider?.setDoubleValueSafely(percentage)
        player.touchBarSupport.touchBarPosLabels.forEach { $0.updateText(with: duration, given: pos) }
      }
    }
  }

  func updateVolume() {
    volumeSlider.doubleValue = player.info.volume
    muteButton.state = player.info.isMuted ? .on : .off
  }

  func updatePlayButtonState(_ state: NSControl.StateValue) {
    playButton.state = state
    if state == .off {
      speedValueIndex = AppData.availableSpeedValues.count / 2
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = true
    }
  }

  func updateNetworkState() {
    let needShowIndicator = player.info.pausedForCache || player.info.isSeeking

    if needShowIndicator {
      let sizeStr = FileSize.format(player.info.cacheSize, unit: .kb)
      let usedStr = FileSize.format(player.info.cacheUsed, unit: .kb)
      let speedStr = FileSize.format(player.info.cacheSpeed, unit: .b)
      let bufferingState = player.info.bufferingState
      bufferIndicatorView.isHidden = false
      bufferProgressLabel.stringValue = String(format: NSLocalizedString("main.buffering_indicator", comment:"Buffering... %d%%"), bufferingState)
      bufferDetailLabel.stringValue = "\(usedStr)/\(sizeStr) (\(speedStr)/s)"
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

  // MARK: - IBAction

  /** Play button: pause & resume */
  @IBAction func playButtonAction(_ sender: NSButton) {
    if sender.state == .on {
      player.togglePause(false)
    }
    if sender.state == .off {
      player.togglePause(true)
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

  /** mute button */
  @IBAction func muteButtonAction(_ sender: NSButton) {
    player.toogleMute(nil)
    if player.info.isMuted {
      displayOSD(.mute)
    } else {
      displayOSD(.unMute)
    }
  }

  /** left btn */
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
        player.togglePause(false)
      }

    case .playlist:
      player.mpv.command(left ? .playlistPrev : .playlistNext, checkError: false)

    case .seek:
      player.seek(relativeSecond: left ? -10 : 10, option: .relative)

    }
  }

  /// Legacy IBAction, but still in use.
  func settingsButtonAction(_ sender: AnyObject) {
    if sidebarAnimationState == .willShow || sidebarAnimationState == .willHide {
      return  // do not interrput other actions while it is animating
    }
    let view = quickSettingView
    switch sideBarStatus {
    case .hidden:
      showSideBar(viewController: view, type: .settings)
    case .playlist:
      hideSideBar {
        self.showSideBar(viewController: view, type: .settings)
      }
    case .settings:
      hideSideBar()
    }
  }

  /// Legacy IBAction, but still in use.
  func playlistButtonAction(_ sender: AnyObject) {
    if sidebarAnimationState == .willShow || sidebarAnimationState == .willHide {
      return  // do not interrput other actions while it is animating
    }
    let view = playlistView
    switch sideBarStatus {
    case .hidden:
      showSideBar(viewController: view, type: .playlist)
    case .playlist:
      hideSideBar()
    case .settings:
      hideSideBar {
        self.showSideBar(viewController: view, type: .playlist)
      }
    }
  }


  /** When slider changes */
  @IBAction func playSliderChanges(_ sender: NSSlider) {
    // guard let event = NSApp.currentEvent else { return }
    guard !player.info.fileLoading else { return }

    // seek and update time
    let percentage = 100 * sender.doubleValue / sender.maxValue
    // label
    timePreviewWhenSeek.frame.origin = CGPoint(
      x: round(sender.knobPointPosition() - timePreviewWhenSeek.frame.width / 2),
      y: playSlider.frame.origin.y + 16)
    timePreviewWhenSeek.stringValue = (player.info.videoDuration! * percentage * 0.01).stringRepresentation
    player.seek(percent: percentage, forceExact: !followGlobalSeekTypeWhenAdjustSlider)
  }


  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.doubleValue
    if Preference.double(for: .maxVolume) > 100, abs(value - 100) < 0.5 {
      NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    player.setVolume(value)
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
      playlistButtonAction(sender)
    case .settings:
      settingsButtonAction(sender)
    case .subTrack:
      quickSettingView.showSubChooseMenu(forView: sender, showLoadedSubs: true)
    }
  }

  // MARK: - Utility

  func handleIINACommand(_ cmd: IINACommand) {
    let appDeletate = (NSApp.delegate! as! AppDelegate)
    switch cmd {
    case .openFile:
      appDeletate.openFile(self)
    case .openURL:
      appDeletate.openURL(self)
    case .togglePIP:
      if #available(macOS 10.12, *) {
        self.menuTogglePIP(.dummy)
      }
    case .videoPanel:
      self.menuShowVideoQuickSettings(.dummy)
    case .audioPanel:
      self.menuShowAudioQuickSettings(.dummy)
    case .subPanel:
      self.menuShowSubQuickSettings(.dummy)
    case .playlistPanel:
      self.menuShowPlaylistPanel(.dummy)
    case .chapterPanel:
      self.menuShowChaptersPanel(.dummy)
    case .toggleMusicMode:
      self.menuSwitchToMiniPlayer(.dummy)
    case .flip:
      self.menuActionHandler.menuToggleFlip(.dummy)
    case .mirror:
      self.menuActionHandler.menuToggleMirror(.dummy)
    case .saveCurrentPlaylist:
      self.menuActionHandler.menuSavePlaylist(.dummy)
    case .deleteCurrentFile:
      self.menuActionHandler.menuDeleteCurrentFile(.dummy)
    case .findOnlineSubs:
      self.menuActionHandler.menuFindOnlineSub(.dummy)
    case .saveDownloadedSub:
      self.menuActionHandler.saveDownloadedSub(.dummy)
    case .biggerWindow:
      let item = NSMenuItem()
      item.tag = 11
      self.menuChangeWindowSize(item)
    case .smallerWindow:
      let item = NSMenuItem()
      item.tag = 10
      self.menuChangeWindowSize(item)
    case .fitToScreen:
      let item = NSMenuItem()
      item.tag = 3
      self.menuChangeWindowSize(item)
    }
  }

  private func resetCollectionBehavior() {
    guard !screenState.isFullscreen else { return }
    if Preference.bool(for: .useLegacyFullScreen) {
      window?.collectionBehavior = [.managed, .fullScreenAuxiliary]
    } else {
      window?.collectionBehavior = [.managed, .fullScreenPrimary]
    }
  }
  
  func isMouseEvent(_ event: NSEvent, inAnyOf views: [NSView?]) -> Bool {
    return views.filter { $0 != nil }.reduce(false, { (result, view) in
      return result || view!.mouse(view!.convert(event.locationInWindow, from: nil), in: view!.bounds)
    })
  }
  
}

// MARK: - Picture in Picture

@available(macOS 10.12, *)
extension MainWindowController: PIPViewControllerDelegate {

  func enterPIP() {
    // Exit fullscreen if necessary
    if screenState.isFullscreen {
      toggleWindowFullScreen()
    }
    
    pipStatus = .inPIP
    
    pipVideo = NSViewController()
    pipVideo.view = videoView
    pip.playing = !player.info.isPaused
    pip.title = window?.title
    
    pip.presentAsPicture(inPicture: pipVideo)
    pipOverlayView.isHidden = false
  }
  
  func exitPIP() {
    if pipShouldClose(pip) {
      pip.dismissViewController(pipVideo)
    }
  }

  func doneExitingPIP() {
    pipStatus = .notInPIP
    
    pipOverlayView.isHidden = true
    window?.contentView?.addSubview(videoView, positioned: .below, relativeTo: nil)
    videoView.frame = window?.contentView?.frame ?? .zero
  }

  func pipShouldClose(_ pip: PIPViewController) -> Bool {
    // This is called right before we're about to close the PIP
    pipStatus = .intermediate
    
    // Set frame to animate back to
    pip.replacementRect = window?.contentView?.frame ?? .zero
    pip.replacementWindow = window
    
    // Bring the window to the front and deminiaturize it
    NSApp.activate(ignoringOtherApps: true)
    window?.deminiaturize(pip)
    
    return true
  }

  func pipDidClose(_ pip: PIPViewController) {
    doneExitingPIP()
  }

  func pipActionPlay(_ pip: PIPViewController) {
    player.togglePause(false)
  }

  func pipActionPause(_ pip: PIPViewController) {
    player.togglePause(true)
  }

  func pipActionStop(_ pip: PIPViewController) {
    // Stopping PIP pauses playback
    player.togglePause(true)
  }
}

protocol SidebarViewController {
  var downShift: CGFloat { get set }
}
