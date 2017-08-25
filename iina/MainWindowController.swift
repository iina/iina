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


class MainWindowController: NSWindowController, NSWindowDelegate {

  override var windowNibName: String {
    return "MainWindowController"
  }

  // MARK: - Constants

  /** Minimum window size. */
  let minSize = NSMakeSize(500, 300)

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

  /** The view for interactive cropping. */
  lazy var cropSettingsView: CropSettingsViewController = {
    let cropView = CropSettingsViewController()
    cropView.mainWindow = self
    return cropView
  }()

  /** The current/remaining time label in Touch Bar. */
  lazy var sizingTouchBarTextField: NSTextField = {
    return NSTextField()
  }()

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
  var cachedGeometry: PlayerCore.GeometryDef?

  var touchBarPosLabelWidthLayout: NSLayoutConstraint?

  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  var isResizingSidebar: Bool = false

  var isInFullScreen: Bool = false {
    didSet {
      player.mpv.setFlag(MPVOption.Window.fullscreen, isInFullScreen)
    }
  }
  var isEnteringFullScreen: Bool = false

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

  var lastMagnification: CGFloat = 0.0

  /** Views that will show/hide when cursor moving in/out the window. */
  var fadeableViews: [NSView] = []

  /** Cache current crop applied to video. */
  var currentCrop: NSRect = NSRect()

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
        return CGFloat(Preference.integer(for: .playlistWidth)).constrain(min: PlaylistMinWidth, max: PlaylistMaxWidth)
      default:
        Utility.fatal("SideBarViewType.width shouldn't be called here")
      }
    }
  }

  var sideBarStatus: SideBarViewType = .hidden
  
  enum PIPStatus {
    case notInPIP
    case inPIP
    case intermediate
  }

  // MARK: - Observed user defaults

  /** Observers added to `UserDefauts.standard`. */
  private var notificationObservers: [NotificationCenter: [NSObjectProtocol]] = [:]

  /** Cached user default values */
  private var oscPosition: Preference.OSCPosition
  private var useExtractSeek: Preference.SeekOption
  private var relativeSeekAmount: Int = 3
  private var volumeScrollAmount: Int = 4
  private var horizontalScrollAction: Preference.ScrollAction
  private var verticalScrollAction: Preference.ScrollAction
  private var arrowBtnFunction: Preference.ArrowButtonAction
  private var singleClickAction: Preference.MouseClickAction
  private var doubleClickAction: Preference.MouseClickAction
  private var rightClickAction: Preference.MouseClickAction
  private var pinchAction: Preference.PinchAction

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
    .rightClickAction,
    .pinchAction,
    .showRemainingTime,
    .blackOutMonitor,
    .alwaysFloatOnTop
  ]

  // MARK: - Outlets

  var standardWindowButtons: [NSButton] {
    get {
      return ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindowButton]).flatMap {
        window?.standardWindowButton($0)
      }
    }
  }

  /** Get the `NSTextField` of widow's title. */
  var titleTextField: NSTextField? {
    get {
      return window?.standardWindowButton(.documentIconButton)?.superview?.subviews.flatMap({ $0 as? NSTextField }).first
    }
  }

  /** Current OSC view. */
  var currentControlBar: NSView?

  @IBOutlet weak var sideBarRightConstraint: NSLayoutConstraint!
  @IBOutlet weak var sideBarWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var bottomBarBottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var titleBarHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var oscTopMainViewTopConstraint: NSLayoutConstraint!
  var osdProgressBarWidthConstraint: NSLayoutConstraint!

  @IBOutlet weak var titleBarView: NSVisualEffectView!

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
  @IBOutlet weak var bottomView: NSVisualEffectView!
  @IBOutlet weak var bufferIndicatorView: NSVisualEffectView!
  @IBOutlet weak var bufferProgressLabel: NSTextField!
  @IBOutlet weak var bufferSpin: NSProgressIndicator!
  @IBOutlet weak var bufferDetailLabel: NSTextField!
  @IBOutlet var thumbnailPeekView: ThumbnailPeekView!

  @IBOutlet weak var oscFloatingTopView: NSStackView!
  @IBOutlet weak var oscFloatingBottomView: NSView!
  @IBOutlet weak var oscBottomMainView: NSStackView!
  @IBOutlet weak var oscTopMainView: NSStackView!

  @IBOutlet var fragControlView: NSStackView!
  @IBOutlet var fragToolbarView: NSView!
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

  weak var touchBarPlaySlider: TouchBarPlaySlider?
  weak var touchBarPlayPauseBtn: NSButton?
  weak var touchBarCurrentPosLabel: DurationDisplayTextField?

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
    arrowBtnFunction = Preference.enum(for: .arrowButtonAction)
    singleClickAction = Preference.enum(for: .singleClickAction)
    doubleClickAction = Preference.enum(for: .doubleClickAction)
    rightClickAction = Preference.enum(for: .rightClickAction)
    pinchAction = Preference.enum(for: .pinchAction)

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
    w.backgroundColor = NSColor.black

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
    setupOnScreenController(position: oscPosition)

    // fade-able views
    fadeableViews.append(contentsOf: standardWindowButtons as [NSView])
    fadeableViews.append(titleBarView)

    guard let cv = w.contentView else { return }

    // video view
    // note that don't use auto resize for it (handle in windowDidResize)
    cv.autoresizesSubviews = false
    cv.addSubview(videoView, positioned: .below, relativeTo: nil)

    w.setIsVisible(true)

    videoView.translatesAutoresizingMaskIntoConstraints = true
    //quickConstrants(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": videoView])

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
    [titleBarView, osdVisualEffectView, controlBarBottom, controlBarFloating, sideBarView, osdVisualEffectView, pipOverlayView].forEach {
      $0?.state = .active
    }
    // hide other views
    osdVisualEffectView.isHidden = true
    osdVisualEffectView.layer?.cornerRadius = 10
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
    notificationCenter(.default, addObserverfor: Constants.Noti.fsChanged) { [unowned self] _ in
      let fs = self.player.mpv.getFlag(MPVOption.Window.fullscreen)
      if fs != self.isInFullScreen {
        self.toggleWindowFullScreen()
      }
    }
    notificationCenter(.default, addObserverfor: Constants.Noti.ontopChanged) { [unowned self] _ in
      let ontop = self.player.mpv.getFlag(MPVOption.Window.ontop)
      if ontop != self.isOntop {
        self.isOntop = ontop
        self.setWindowFloatingOnTop(ontop)
      }
    }
    notificationCenter(.default, addObserverfor: Constants.Noti.windowScaleChanged) { [unowned self] _ in
      let windowScale = self.player.mpv.getDouble(MPVOption.Window.windowScale)
      self.setWindowScale(windowScale)
    }
    notificationCenter(.default, addObserverfor: .NSApplicationDidChangeScreenParameters) { [unowned self] _ in
      // This observer handles a situation that the user connected a new screen or removed a screen
      if self.isInFullScreen && Preference.bool(for: .blackOutMonitor) {
        if NSScreen.screens()?.count ?? 0 != self.cachedScreenCount {
          self.removeBlackWindow()
          self.blackOutOtherMonitors()
        }
      }
    }
    notificationCenter(NSWorkspace.shared().notificationCenter, addObserverfor: .NSWorkspaceActiveSpaceDidChange) { [unowned self] _ in
      if self.isInFullScreen && Preference.bool(for: .blackOutMonitor) {
        if self.window?.isOnActiveSpace ?? false {
          self.removeBlackWindow()
          self.blackOutOtherMonitors()
        } else {
          self.removeBlackWindow()
        }
      }
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

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    switch keyPath {

    case PK.themeMaterial.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
      }

    case PK.oscPosition.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        setupOnScreenController(position: Preference.OSCPosition(rawValue: newValue) ?? .floating)
      }

    case PK.showChapterPos.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        (playSlider.cell as! PlaySliderCell).drawChapters = newValue
      }

    case PK.useExactSeek.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        useExtractSeek = Preference.SeekOption(rawValue: newValue)!
      }

    case PK.relativeSeekAmount.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        relativeSeekAmount = newValue.constrain(min: 1, max: 5)
      }

    case PK.volumeScrollAmount.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        volumeScrollAmount = newValue.constrain(min: 1, max: 4)
      }

    case PK.verticalScrollAction.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }

    case PK.horizontalScrollAction.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)!
      }

    case PK.arrowButtonAction.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        arrowBtnFunction = Preference.ArrowButtonAction(rawValue: newValue)!
      }

    case PK.arrowButtonAction.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        arrowBtnFunction = Preference.ArrowButtonAction(rawValue: newValue)!
      }

    case PK.singleClickAction.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        singleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }

    case PK.doubleClickAction.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        doubleClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }

    case PK.rightClickAction.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        rightClickAction = Preference.MouseClickAction(rawValue: newValue)!
      }

    case PK.pinchAction.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        pinchAction = Preference.PinchAction(rawValue: newValue)!
      }

    case PK.showRemainingTime.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        rightLabel.mode = newValue ? .remaining : .duration
        touchBarCurrentPosLabel?.mode = newValue ? .remaining : .current
      }
    
    case PK.blackOutMonitor.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        if isInFullScreen {
          if newValue {
            blackOutOtherMonitors()
          } else {
            removeBlackWindow()
          }
        }
      }

    case PK.alwaysFloatOnTop.rawValue:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        if !player.info.isPaused {
          self.isOntop = newValue
          setWindowFloatingOnTop(newValue)
        }
      }

    default:
      return
    }
  }

  private func setupOnScreenController(position newPosition: Preference.OSCPosition) {

    var isCurrentControlBarHidden = false

    let isSwitchingToTop = newPosition == .top
    let isSwitchingFromTop = oscPosition == .top

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
    [fragSliderView, fragControlView, fragToolbarView, fragVolumeView].forEach { $0?.removeFromSuperview() }

    if isSwitchingToTop {
      if isInFullScreen {
        addBackTitlebarViewToFadeableViews()
        oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTopInFullScreen
        titleBarHeightConstraint.constant = TitleBarHeightWithOSCInFullScreen
      } else {
        oscTopMainViewTopConstraint.constant = OSCTopMainViewMarginTop
        titleBarHeightConstraint.constant = TitleBarHeightWithOSC
      }
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
      fragControlView.setVisibilityPriority(NSStackViewVisibilityPriorityMustHold, for: fragControlViewLeftView)
      fragControlView.setVisibilityPriority(NSStackViewVisibilityPriorityMustHold, for: fragControlViewRightView)
      oscFloatingTopView.addView(fragVolumeView, in: .leading)
      oscFloatingTopView.addView(fragToolbarView, in: .trailing)
      oscFloatingTopView.addView(fragControlView, in: .center)
      oscFloatingBottomView.addSubview(fragSliderView)
      Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": fragSliderView])
      // center control bar
      let cph = Preference.float(for: .controlBarPositionHorizontal)
      let cpv = Preference.float(for: .controlBarPositionVertical)
      controlBarFloating.setFrameOrigin(NSMakePoint(
        (window!.frame.width * CGFloat(cph) - controlBarFloating.frame.width * 0.5).constrain(min: 0, max: window!.frame.width),
        window!.frame.height * CGFloat(cpv)
      ))
    case .top:
      oscTopMainView.isHidden = false
      currentControlBar = nil
      fragControlView.setVisibilityPriority(NSStackViewVisibilityPriorityNotVisible, for: fragControlViewLeftView)
      fragControlView.setVisibilityPriority(NSStackViewVisibilityPriorityNotVisible, for: fragControlViewRightView)
      oscTopMainView.addView(fragVolumeView, in: .trailing)
      oscTopMainView.addView(fragToolbarView, in: .trailing)
      oscTopMainView.addView(fragControlView, in: .leading)
      oscTopMainView.addView(fragSliderView, in: .leading)
      oscTopMainView.setClippingResistancePriority(NSLayoutPriorityDefaultLow, for: .horizontal)
      oscTopMainView.setVisibilityPriority(NSStackViewVisibilityPriorityDetachOnlyIfNecessary, for: fragVolumeView)
    case .bottom:
      currentControlBar = controlBarBottom
      fragControlView.setVisibilityPriority(NSStackViewVisibilityPriorityNotVisible, for: fragControlViewLeftView)
      fragControlView.setVisibilityPriority(NSStackViewVisibilityPriorityNotVisible, for: fragControlViewRightView)
      oscBottomMainView.addView(fragVolumeView, in: .trailing)
      oscBottomMainView.addView(fragToolbarView, in: .trailing)
      oscBottomMainView.addView(fragControlView, in: .leading)
      oscBottomMainView.addView(fragSliderView, in: .leading)
      oscBottomMainView.setClippingResistancePriority(NSLayoutPriorityDefaultLow, for: .horizontal)
      oscBottomMainView.setVisibilityPriority(NSStackViewVisibilityPriorityDetachOnlyIfNecessary, for: fragVolumeView)
    }

    if currentControlBar != nil {
      fadeableViews.append(currentControlBar!)
      currentControlBar!.isHidden = isCurrentControlBarHidden
    }
  }

  // MARK: - Mouse / Trackpad event

  override func keyDown(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    let keyCode = Utility.mpvKeyCode(from: event)
    if let kb = PlayerCore.keyBindings[keyCode] {
      if kb.isIINACommand {
        // - IINA command
        if let iinaCommand = IINACommand(rawValue: kb.rawAction) {
          handleIINACommand(iinaCommand)
        } else {
          Utility.log("Unknown iina command \(kb.rawAction)")
        }
      } else {
        // - MPV command
        let returnValue: Int32
        // execute the command
        switch kb.action[0] {
        case MPVCommand.abLoop.rawValue:
          player.abLoop()
          returnValue = 0
        default:
          returnValue = player.mpv.command(rawString: kb.rawAction)
        }
        // handle return value, display osd if needed
        if returnValue == 0 {
          // screenshot
          if kb.action[0] == MPVCommand.screenshot.rawValue {
            displayOSD(.screenShot)
          }
        } else {
          Utility.log("Return value \(returnValue) when executing key command \(kb.rawAction)")
        }
      }
    } else {
      super.keyDown(with: event)
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
      sideBarWidthConstraint.constant = newWidth.constrain(min: PlaylistMinWidth, max: PlaylistMaxWidth)
    } else {
      // move the window by dragging
      isDragging = true
      guard !controlBarFloating.isDragging else { return }
      if mousePosRelatedToWindow != nil {
        if #available(OSX 10.11, *) {
          window?.performDrag(with: event)
        } else {
          let currentLocation = NSEvent.mouseLocation()
          let newOrigin = CGPoint(
            x: currentLocation.x - mousePosRelatedToWindow!.x,
            y: currentLocation.y - mousePosRelatedToWindow!.y
          )
          window?.setFrameOrigin(newOrigin)
        }
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
      let mouseInSideBar = window!.contentView!.mouse(event.locationInWindow, in: sideBarView.frame)
      // if sidebar is shown, hide it first
      if !mouseInSideBar && sideBarStatus != .hidden {
        hideSideBar()
      } else {
        // handle mouse click
        if event.clickCount == 1 {
          // single click
          if doubleClickAction == .none {
            // if double click action is none, it's safe to perform action immediately
            performMouseAction(singleClickAction)
          } else {
            // else start a timer to check for double clicking
            singleClickTimer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval(), target: self, selector: #selector(self.performMouseActionLater(_:)), userInfo: singleClickAction, repeats: false)
            mouseExitEnterCount = 0
          }
        } else if event.clickCount == 2 {
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
    performMouseAction(rightClickAction)
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
      Utility.log("No data for tracking area")
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
      Utility.log("No data for tracking area")
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
    let osc = currentControlBar ?? titleBarView
    let mousePosInOSC = osc!.convert(event.locationInWindow, from: nil)
    let isMouseInOSC = osc!.mouse(mousePosInOSC, in: osc!.bounds)
    if isMouseInOSC {
      destroyTimer()
    } else {
      updateTimer()
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard !isInInteractiveMode else { return }

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

    if scrollAction == .seek {
      let seekAmount = (isMouse ? AppData.seekAmountMapMouse : AppData.seekAmountMap)[relativeSeekAmount] * delta
      player.seek(relativeSecond: seekAmount, option: useExtractSeek)
    } else if scrollAction == .volume {
      // don't use precised delta for mouse
      let newVolume = player.info.volume + (isMouse ? delta : AppData.volumeMap[volumeScrollAmount] * delta)
      player.setVolume(newVolume)
      volumeSlider.doubleValue = newVolume
    }
  }

  func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard pinchAction != .none else { return }
    guard !isInInteractiveMode, let window = window, let screenFrame = NSScreen.main()?.visibleFrame else { return }

    if pinchAction == .windowSize {
      if isInFullScreen { return }
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
      }

    } else if pinchAction == .fullscreen{
      // enter/exit fullscreen
      if recognizer.state == .began {
        let isEnlarge = recognizer.magnification > 0
        // xor
        if isEnlarge != isInFullScreen {
          recognizer.state = .recognized
          self.toggleWindowFullScreen()
        }
      }
    }
  }

  // MARK: - Window delegate

  /** A method being called when window open. Pretend to be a window delegate. */
  func windowDidOpen() {
    window!.makeMain()
    window!.makeKeyAndOrderFront(nil)
    window!.collectionBehavior = [.managed, .fullScreenPrimary]
    // update buffer indicator view
    updateBufferIndicatorView()
    // start tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
    cv.addTrackingArea(NSTrackingArea(rect: cv.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 0]))
    playSlider.addTrackingArea(NSTrackingArea(rect: playSlider.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 1]))
    // update timer
    updateTimer()
    // always on top
    if Preference.bool(for: .alwaysFloatOnTop) {
      isOntop = true
      setWindowFloatingOnTop(true)
    }
    // truncate middle for title
    if let attrTitle = titleTextField?.attributedStringValue.mutableCopy() as? NSMutableAttributedString, attrTitle.length > 0 {
      let p = attrTitle.attribute(NSParagraphStyleAttributeName, at: 0, effectiveRange: nil) as! NSMutableParagraphStyle
      p.lineBreakMode = .byTruncatingMiddle
      attrTitle.addAttribute(NSParagraphStyleAttributeName, value: p, range: NSRange(location: 0, length: attrTitle.length))
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

  func windowWillEnterFullScreen(_ notification: Notification) {
    isEnteringFullScreen = true

    player.mpv.setFlag(MPVOption.Window.keepaspect, true)

    // Set the appearance to match the theme so the titlebar matches the theme
    switch(Preference.enum(for: .themeMaterial) as Preference.Theme) {
      case .dark, .ultraDark: window!.appearance = NSAppearance(named: NSAppearanceNameVibrantDark);
      case .light, .mediumLight: window!.appearance = NSAppearance(named: NSAppearanceNameVibrantLight);
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

    isInFullScreen = true
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    isEnteringFullScreen = false
    // we must block the mpv rendering queue to do the following atomically
    videoView.videoLayer.mpvGLQueue.async {
      DispatchQueue.main.sync {
        self.videoView.frame = NSRect(x: 0, y: 0, width: self.window!.frame.width, height: self.window!.frame.height)
        self.videoView.videoLayer.display()
      }
    }
  }

  func windowWillExitFullScreen(_ notification: Notification) {
    player.mpv.setFlag(MPVOption.Window.keepaspect, false)

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
    isMouseInSlider = false

    isInFullScreen = false

    // set back frame of videoview, but only if not in PIP
    if pipStatus == .notInPIP {
      videoView.videoLayer.mpvGLQueue.sync {
        self.videoView.videoLayer.setNeedsDisplay()
      }
    }
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    if Preference.bool(for: .blackOutMonitor) {
      removeBlackWindow()
    }
    
    if !player.info.isPaused {
      setWindowFloatingOnTop(isOntop)
    }
  }

  func windowDidResize(_ notification: Notification) {
    guard let w = window else { return }
    let wSize = w.frame.size

    // is paused or very low fps (assume audio file), draw new frame
    if player.info.isPaused || player.currentMediaIsAudio == .isAudio {
      videoView.videoLayer.draw()
    }

    // update videoview size if in full screen, since aspect ratio may changed
    if (isInFullScreen && pipStatus == .notInPIP) {
      if isEnteringFullScreen {
        let aspectRatio = w.aspectRatio.width / w.aspectRatio.height
        let tryHeight = wSize.width / aspectRatio
        if tryHeight <= wSize.height {
          // should have black bar above and below
          let targetHeight = wSize.width / aspectRatio
          let yOffset = (wSize.height - targetHeight) / 2
          videoView.frame = NSMakeRect(0, yOffset, wSize.width, targetHeight)
        } else if tryHeight > wSize.height {
          // should have black bar left and right
          let targetWidth = wSize.height * aspectRatio
          let xOffset = (wSize.width - targetWidth) / 2
          videoView.frame = NSMakeRect(xOffset, 0, targetWidth, wSize.height)
        }
      } else {
        videoView.frame = NSRect(x: 0, y: 0, width: w.frame.width, height: w.frame.height)
      }
    } else if (pipStatus == .notInPIP) {
      let frame = NSRect(x: 0, y: 0, width: w.contentView!.frame.width, height: w.contentView!.frame.height)

      if isInInteractiveMode {
        let origWidth = CGFloat(player.info.videoWidth!)
        let origHeight = CGFloat(player.info.videoHeight!)
        let videoRect: NSRect, interactiveModeFrame: NSRect
        (videoRect, interactiveModeFrame) = videoViewSizeInInteractiveMode(frame, currentCrop: currentCrop, originalSize: NSMakeSize(origWidth, origHeight))
        cropSettingsView.cropBoxView.resized(with: videoRect)
        videoView.frame = interactiveModeFrame
      } else {
        videoView.frame = frame
      }

    }
    // update control bar position
    if oscPosition == .floating {
      let cph = Preference.float(for: .controlBarPositionHorizontal)
      let cpv = Preference.float(for: .controlBarPositionVertical)
      controlBarFloating.setFrameOrigin(NSMakePoint(
        (wSize.width * CGFloat(cph) - controlBarFloating.frame.width * 0.5).constrain(min: 0, max: wSize.width),
        wSize.height * CGFloat(cpv)
      ))
    }
  }

  // resize framebuffer in videoView after resizing.
  func windowDidEndLiveResize(_ notification: Notification) {
    videoView.videoSize = window!.convertToBacking(videoView.bounds).size
  }

  func windowDidChangeBackingProperties(_ notification: Notification) {
    if let oldScale = (notification.userInfo?[NSBackingPropertyOldScaleFactorKey] as? NSNumber)?.doubleValue,
      oldScale != Double(window!.backingScaleFactor) {
      videoView.videoLayer.contentsScale = window!.backingScaleFactor
    }

  }

  func windowDidBecomeKey(_ notification: Notification) {
    window!.makeFirstResponder(window!)
  }

  func windowDidBecomeMain(_ notification: Notification) {
    PlayerCore.lastActive = player
    NotificationCenter.default.post(name: Constants.Noti.mainWindowChanged, object: nil)
  }

  func windowDidResignMain(_ notification: Notification) {
    NotificationCenter.default.post(name: Constants.Noti.mainWindowChanged, object: nil)
  }

  // MARK: - Control UI

  func hideUIAndCursor() {
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
      if !isInFullScreen {
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
    standardWindowButtons.forEach { $0.isEnabled = true }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = UIAnimationDuration
      fadeableViews.forEach { (v) in
        v.animator().alphaValue = 1
      }
      if !isInFullScreen {
        titleTextField?.animator().alphaValue = 1
      }
    }) {
      // if no interrupt then hide animation
      if self.animationState == .willShow {
        self.animationState = .shown
      }
    }
  }

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

  func updateTitle() {
    if player.info.isNetworkResource {
      let mediaTitle = player.mpv.getString(MPVProperty.mediaTitle)
      window?.title = mediaTitle ?? player.info.currentURL?.path ?? ""
    } else {
      window?.representedURL = player.info.currentURL
      window?.setTitleWithRepresentedFilename(player.info.currentURL?.path ?? "")
    }
  }

  func displayOSD(_ message: OSDMessage) {
    if !player.displayOSD { return }

    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    osdAnimationState = .shown
    [osdAccessoryText, osdAccessoryProgress].forEach { $0.isHidden = true }

    let (osdString, osdType) = message.message()

    let osdTextSize = Preference.float(for: .osdTextSize)
    osdLabel.font = NSFont.systemFont(ofSize: CGFloat(osdTextSize))
    osdLabel.stringValue = osdString

    switch osdType {
    case .normal:
      osdStackView.setVisibilityPriority(NSStackViewVisibilityPriorityNotVisible, for: osdAccessoryView)
    case .withProgress(let value):
      NSLayoutConstraint.activate([osdProgressBarWidthConstraint])
      osdStackView.setVisibilityPriority(NSStackViewVisibilityPriorityMustHold, for: osdAccessoryView)
      osdAccessoryProgress.isHidden = false
      osdAccessoryProgress.doubleValue = value
    case .withText(let text):
      NSLayoutConstraint.deactivate([osdProgressBarWidthConstraint])

      // data for mustache redering
      let osdData: [String: String] = [
        "duration": player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "position": player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).toStr(),
        "chapterCount": player.info.chapters.count.toStr()
      ]

      osdStackView.setVisibilityPriority(NSStackViewVisibilityPriorityMustHold, for: osdAccessoryView)
      osdAccessoryText.isHidden = false
      osdAccessoryText.stringValue = try! (try! Template(string: text)).render(osdData)
    }

    osdVisualEffectView.alphaValue = 1
    osdVisualEffectView.isHidden = false
    let timeout = Preference.float(for: .osdAutoHideTimeout)
    hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
  }

  @objc private func hideOSD() {
    NSAnimationContext.runAnimationGroup({ (context) in
      self.osdAnimationState = .willHide
      context.duration = OSDAnimationDuration
      osdVisualEffectView.animator().alphaValue = 0
    }) {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
      }
    }
  }

  private func showSideBar(viewController: SidebarViewController, type: SideBarViewType) {
    // adjust sidebar width
    guard let view = (viewController as? NSViewController)?.view else {
        Utility.fatal("viewController is not a NSViewController")
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
    self.fadeableViews.append(titleBarView)
  }

  func enterInteractiveMode() {
    player.togglePause(true)
    isInInteractiveMode = true
    hideUI()
    bottomView.isHidden = false
    bottomView.addSubview(cropSettingsView.view)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": cropSettingsView.view])

    // get original frame
    let origWidth = CGFloat(player.info.videoWidth!)
    let origHeight = CGFloat(player.info.videoHeight!)
    let origSize = NSMakeSize(origWidth, origHeight)
    let currWidth = CGFloat(player.info.displayWidth!)
    let currHeight = CGFloat(player.info.displayHeight!)
    let winFrame = window!.frame
    let videoViewFrame: NSRect
    let videoRect: NSRect

    // get current cropped region
    if let cropFilter = player.info.cropFilter {
      let params = cropFilter.cropParams(videoSize: origSize)
      let x = CGFloat(params["x"]!)
      let y = CGFloat(params["y"]!)
      let w = CGFloat(params["w"]!)
      let h = CGFloat(params["h"]!)
      // coord of cropBoxView is flipped
      currentCrop = NSMakeRect(x, origHeight - h - y, w, h)
    } else {
      currentCrop = NSMakeRect(0, 0, origWidth, origHeight)
    }

    // if cropped, try get real window size
    if origWidth != currWidth || origHeight != currHeight {
      let scale = origWidth == currWidth ? winFrame.width / currWidth : winFrame.height / currHeight
      let winFrameWithOrigVideoSize = NSRect(origin: winFrame.origin, size: NSMakeSize(scale * origWidth, scale * origHeight))

      window!.aspectRatio = winFrameWithOrigVideoSize.size
      if #available(macOS 10.12, *) {
        pip.aspectRatio = winFrameWithOrigVideoSize.size
      }
      window!.setFrame(winFrameWithOrigVideoSize, display: true, animate: false)
      (videoRect, videoViewFrame) = videoViewSizeInInteractiveMode(winFrameWithOrigVideoSize, currentCrop: currentCrop, originalSize: origSize)
    } else {
      (videoRect, videoViewFrame) = videoViewSizeInInteractiveMode(videoView.frame, currentCrop: currentCrop, originalSize: origSize)
    }

    // add crop setting view
    window!.contentView!.addSubview(cropSettingsView.cropBoxView)
    cropSettingsView.cropBoxView.selectedRect = currentCrop
    cropSettingsView.cropBoxView.actualSize = origSize
    cropSettingsView.cropBoxView.resized(with: videoRect)
    cropSettingsView.cropBoxView.isHidden = true
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": cropSettingsView.cropBoxView])

    // show crop settings view
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = CropAnimationDuration
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
      bottomBarBottomConstraint.animator().constant = 0
      videoView.animator().frame = videoViewFrame
    }) {
      self.cropSettingsView.cropBoxView.isHidden = false
    }

  }

  func exitInteractiveMode(_ then: @escaping () -> Void) {
    player.togglePause(false)
    isInInteractiveMode = false
    cropSettingsView.cropBoxView.isHidden = true
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = CropAnimationDuration
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
      bottomBarBottomConstraint.animator().constant = -InteractiveModeBottomViewHeight
      videoView.animator().frame = NSMakeRect(0, 0, window!.contentView!.frame.width, window!.contentView!.frame.height)
    }) {
      self.cropSettingsView.cropBoxView.removeFromSuperview()
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
      Utility.log("Nil material in setMaterial()")
      return
    }
    guard #available(OSX 10.11, *) else { return }

    var appearance: NSAppearance? = nil
    var material: NSVisualEffectMaterial
    var isDarkTheme: Bool
    let sliderCell = playSlider.cell as? PlaySliderCell

    switch theme {

    case .dark:
      appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
      material = .dark
      isDarkTheme = true

    case .ultraDark:
      appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
      material = .ultraDark
      isDarkTheme = true

    case .light:
      appearance = NSAppearance(named: NSAppearanceNameVibrantLight)
      material = .light
      isDarkTheme = false

    case .mediumLight:
      appearance = NSAppearance(named: NSAppearanceNameVibrantLight)
      material = .mediumLight
      isDarkTheme = false

    }

    sliderCell?.isInDarkTheme = isDarkTheme

    [titleBarView, controlBarFloating, controlBarBottom, osdVisualEffectView, pipOverlayView].forEach {
      $0?.material = material
      $0?.appearance = appearance
    }

    if isInFullScreen {
      window!.appearance = appearance;
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
    if let geometry = cachedGeometry ?? player.getGeometry(), let screenFrame = NSScreen.main()?.visibleFrame {
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
        let w: CGFloat
        if strw.hasSuffix("%") {
          w = CGFloat(Double(String(strw.characters.dropLast()))! * 0.01 * Double(screenFrame.width))
        } else {
          w = CGFloat(Int(strw)!)
        }
        winFrame.size.width = w
        winFrame.size.height = w / winAspect
        widthOrHeightIsSet = true
      } else if let strh = geometry.h, strh != "0" {
        let h: CGFloat
        if strh.hasSuffix("%") {
          h = CGFloat(Double(String(strh.characters.dropLast()))! * 0.01 * Double(screenFrame.height))
        } else {
          h = CGFloat(Int(strh)!)
        }
        winFrame.size.height = h
        winFrame.size.width = h * winAspect
        widthOrHeightIsSet = true
      }
      // x, origin is window center
      if let strx = geometry.x, let xSign = geometry.xSign {
        let x: CGFloat
        if strx.hasSuffix("%") {
          x = CGFloat(Double(String(strx.characters.dropLast()))! * 0.01 * Double(screenFrame.width)) - winFrame.width / 2
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
          y = CGFloat(Double(String(stry.characters.dropLast()))! * 0.01 * Double(screenFrame.height)) - winFrame.height / 2
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
    guard let w = window else { return }

    let (width, height) = player.videoSizeForDisplay

    // set aspect ratio
    let originalVideoSize = NSSize(width: width, height: height)
    w.aspectRatio = originalVideoSize
    if #available(macOS 10.12, *) {
      pip.aspectRatio = originalVideoSize
    }

    videoView.videoSize = w.convertToBacking(videoView.frame).size

    if isInFullScreen {

      self.windowDidResize(Notification(name: .NSWindowDidResize))

    } else {

      var rect: NSRect
      let needResizeWindow = player.info.justOpenedFile || !Preference.bool(for: .resizeOnlyWhenManuallyOpenFile)

      if needResizeWindow {
        // get videoSize on screen
        var videoSize = originalVideoSize
        if Preference.bool(for: .usePhysicalResolution) {
          videoSize = w.convertFromBacking(
            NSMakeRect(w.frame.origin.x, w.frame.origin.y, CGFloat(width), CGFloat(height))).size
        }
        // check screen size
        if let screenSize = NSScreen.main()?.visibleFrame.size {
          videoSize = videoSize.satisfyMaxSizeWithSameAspectRatio(screenSize)
        }
        // guard min size
        videoSize = videoSize.satisfyMinSizeWithSameAspectRatio(minSize)
        // check if have geometry set
        if let wfg = windowFrameFromGeometry(newSize: videoSize) {
          rect = wfg
        } else {
          rect = w.frame.centeredResize(to: videoSize)
        }
        w.setFrame(rect, display: true, animate: true)

      } else {
        // user is navigating in playlist. remain same window width.
        let newHeight = w.frame.width / CGFloat(width) * CGFloat(height)
        let newSize = NSSize(width: w.frame.width, height: newHeight).satisfyMinSizeWithSameAspectRatio(minSize)
        rect = NSRect(origin: w.frame.origin, size: newSize)
        w.setFrame(rect, display: true, animate: true)
      }

      // animated `setFrame` can be inaccurate!
      w.setFrame(rect, display: true)

      // maybe not a good position, consider putting these at playback-restart
      player.info.justOpenedFile = false
      player.info.justStartedFile = false

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

  func setWindowScale(_ scale: Double) {
    guard let window = window, !isInFullScreen else { return }
    let screenFrame = (window.screen ?? NSScreen.main()!).visibleFrame
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
    screens = (NSScreen.screens()?.filter() { $0 != window?.screen }) ?? []
    cachedScreenCount = screens.count + 1

    blackWindows = []
    
    for screen in screens {
      var screenRect = screen.frame
      screenRect.origin = CGPoint(x: 0, y: 0)
      let blackWindow = NSWindow(contentRect: screenRect, styleMask: [], backing: .buffered, defer: false, screen: screen)
      blackWindow.backgroundColor = .black
      blackWindow.level = Int(CGWindowLevelForKey(.mainMenuWindow) + 1)
      
      blackWindows.append(blackWindow)
      blackWindow.makeKeyAndOrderFront(nil)
    }
  }
  
  private func removeBlackWindow() {
    blackWindows = []
  }

  func toggleWindowFullScreen() {
    window?.toggleFullScreen(self)
  }

  /** This method will not set `isOntop`! */
  func setWindowFloatingOnTop(_ onTop: Bool) {
    guard let window = window else { return }
    if isInFullScreen { return }
    if onTop {
      window.level = Int(CGWindowLevelForKey(.floatingWindow)) - 1
    } else {
      window.level = Int(CGWindowLevelForKey(.normalWindow))
    }

    window.collectionBehavior = [.managed, .fullScreenPrimary]

    // don't know why they will be disabled
    standardWindowButtons.forEach { $0.isEnabled = true }
  }

  // MARK: - Sync UI with playback

  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    guard let duration = player.info.videoDuration, let pos = player.info.videoPosition else {
      Utility.fatal("video info not available")
    }
    let percentage = (pos.second / duration.second) * 100
    leftLabel.stringValue = pos.stringRepresentation
    touchBarCurrentPosLabel?.updateText(with: duration, given: pos)
    rightLabel.updateText(with: duration, given: pos)
    if andProgressBar {
      playSlider.doubleValue = percentage
      touchBarPlaySlider?.setDoubleValueSafely(percentage)
    }
  }

  func updateVolume() {
    volumeSlider.doubleValue = player.info.volume
    muteButton.state = player.info.isMuted ? NSOnState : NSOffState
  }

  func updatePlayButtonState(_ state: Int) {
    playButton.state = state
    if state == NSOffState {
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

  // MARK: - IBAction

  /** Play button: pause & resume */
  @IBAction func playButtonAction(_ sender: NSButton) {
    if sender.state == NSOnState {
      player.togglePause(false)
    }
    if sender.state == NSOffState {
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
      if playButton.state == NSOffState {
        updatePlayButtonState(NSOnState)
        player.togglePause(false)
      }

    case .playlist:
      player.mpv.command(left ? .playlistPrev : .playlistNext, checkError: false)

    case .seek:
      player.seek(relativeSecond: left ? -10 : 10, option: .relative)

    }
  }

  @IBAction func settingsButtonAction(_ sender: AnyObject) {
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

  @IBAction func playlistButtonAction(_ sender: AnyObject) {
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

    // seek and update time
    let percentage = 100 * sender.doubleValue / sender.maxValue
    // label
    timePreviewWhenSeek.frame.origin = CGPoint(
      x: round(sender.knobPointPosition() - timePreviewWhenSeek.frame.width / 2),
      y: playSlider.frame.origin.y + 16)
    timePreviewWhenSeek.stringValue = (player.info.videoDuration! * percentage * 0.01).stringRepresentation
    player.seek(percent: percentage, forceExact: true)
  }


  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.doubleValue
    player.setVolume(value)
  }

  // MARK: - Utility

  private func videoViewSizeInInteractiveMode(_ rect: NSRect, currentCrop: NSRect, originalSize: NSSize) -> (NSRect, NSRect) {
    // 60 for bottom bar and 24*2 for top and bottom margin

    // size if no crop
    let nh = rect.height - 108
    let nw = nh * rect.width / rect.height
    let nx = (rect.width - nw) / 2
    let ny: CGFloat = 84

    // cropped size, originalSize should have same aspect as rect

    let cw = nw * (currentCrop.width / originalSize.width)
    let ch = nh * (currentCrop.height / originalSize.height)
    let cx = nx + nw * (currentCrop.origin.x / originalSize.width)
    let cy = ny + nh * (currentCrop.origin.y / originalSize.height)

    return (NSMakeRect(nx, ny, nw, nh), NSMakeRect(cx, cy, cw, ch))
  }

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
    }
  }

}

// MARK: - Picture in Picture

@available(macOS 10.12, *)
extension MainWindowController: PIPViewControllerDelegate {

  func enterPIP() {
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
