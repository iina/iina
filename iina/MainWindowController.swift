//
//  MainWindowController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa
import Mustache

fileprivate typealias PK = Preference.Key

fileprivate let TitleBarHeightNormal: CGFloat = 22
fileprivate let TitleBarHeightWithOSC: CGFloat = 22 + 24 + 10
fileprivate let TitleBarHeightWithOSCInFullScreen: CGFloat = 24 + 10
fileprivate let OSCTopMainViewMarginTop: CGFloat = 26
fileprivate let OSCTopMainViewMarginTopInFullScreen: CGFloat = 6

fileprivate let PlaylistMinWidth: CGFloat = 240
fileprivate let PlaylistMaxWidth: CGFloat = 400

fileprivate let UIAnimationDuration: TimeInterval = 0.25
fileprivate let OSDAnimationDuration: TimeInterval = 0.5
fileprivate let SideBarAnimationDuration: TimeInterval = 0.2
fileprivate let CropAnimationDuration: TimeInterval = 0.2

class MainWindowController: NSWindowController, NSWindowDelegate {

  override var nextResponder: NSResponder? {
    get { return nil }
    set { }
  }

  override var windowNibName: String {
    return "MainWindowController"
  }

  // MARK: - Constants

  unowned let ud: UserDefaults = UserDefaults.standard

  let minSize = NSMakeSize(500, 300)
  let bottomViewHeight: CGFloat = 60
  let minimumPressDuration: TimeInterval = 0.5

  // MARK: - Objects, Views

  unowned let playerCore: PlayerCore = PlayerCore.shared
  lazy var videoView: VideoView = self.initVideoView()
  lazy var sizingTouchBarTextField: NSTextField = {
    return NSTextField()
  }()

  /** The quick setting window */
  lazy var quickSettingView: QuickSettingViewController = {
    let quickSettingView = QuickSettingViewController()
    quickSettingView.mainWindow = self
    return quickSettingView
  }()

  lazy var playlistView: PlaylistViewController = {
    let playListView = PlaylistViewController()
    playListView.mainWindow = self
    return playListView
  }()

  lazy var cropSettingsView: CropSettingsViewController = {
    let cropView = CropSettingsViewController()
    cropView.mainWindow = self
    return cropView
  }()

  private lazy var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = {
    return NSMagnificationGestureRecognizer(target: self, action: #selector(MainWindowController.handleMagnifyGesture(recognizer:)))
  }()

  private var singleClickTimer: Timer?

  /** For auto hiding ui after a timeout */
  var hideControlTimer: Timer?

  var hideOSDTimer: Timer?
  
  var screens: [NSScreen] = []
  var cachedScreenCount = 0

  var blackWindows: [NSWindow] = []
  
  // MARK: - Status

  var cachedGeometry: PlayerCore.GeometryDef?

  var touchBarPosLabelWidthLayout: NSLayoutConstraint?

  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  var isResizingSidebar: Bool = false

  var isInFullScreen: Bool = false {
    didSet {
      playerCore.mpvController.setFlag(MPVOption.Window.fullscreen, isInFullScreen)
    }
  }

  var isOntop: Bool = false {
    didSet {
      playerCore.mpvController.setFlag(MPVOption.Window.ontop, isOntop)
    }
  }

  var isInPIP: Bool = false
  var isInInteractiveMode: Bool = false

  // might use another obj to handle slider?
  var isMouseInWindow: Bool = false
  var isMouseInSlider: Bool = false

  var isFastforwarding: Bool = false

  var lastMagnification: CGFloat = 0.0

  var fadeableViews: [NSView] = []

  /** Cache current crop */
  var currentCrop: NSRect = NSRect()

  /** The maximum pressure recorded when clicking on the arrow buttons **/
  var maxPressure: Int32 = 0

  /** The value of speedValueIndex before Force Touch **/
  var oldIndex: Int = AppData.availableSpeedValues.count / 2

  /** When the arrow buttons were last clicked **/
  var lastClick = Date()

  /** The index of current speed in speed value array */
  var speedValueIndex: Int = AppData.availableSpeedValues.count / 2 {
    didSet {
      if speedValueIndex < 0 || speedValueIndex >= AppData.availableSpeedValues.count {
        speedValueIndex = AppData.availableSpeedValues.count / 2
      }
    }
  }

  var wasPlayingWhenSeekBegan: Bool?
  
  var mouseExitEnterCount = 0

  // MARK: - Enums

  /** Animation state of he hide/show part */
  enum UIAnimationState {
    case shown, hidden, willShow, willHide
  }

  var animationState: UIAnimationState = .shown
  var osdAnimationState: UIAnimationState = .hidden
  var sidebarAnimationState: UIAnimationState = .hidden

  enum ScrollDirection {
    case horizontal
    case vertical
  }

  var scrollDirection: ScrollDirection?

  private var notificationObservers: [NSObjectProtocol] = []

  /** The view embedded in sidebar */
  enum SideBarViewType {
    case hidden // indicating sidebar is hidden. Should only be used by sideBarStatus
    case settings
    case playlist
    func width() -> CGFloat {
      switch self {
      case .settings:
        return 360
      case .playlist:
        return CGFloat(UserDefaults.standard.integer(forKey: PK.playlistWidth)).constrain(min: PlaylistMinWidth, max: PlaylistMaxWidth)
      default:
        Utility.fatal("SideBarViewType.width shouldn't be called here")
      }
    }
  }

  var sideBarStatus: SideBarViewType = .hidden

  // MARK: - Observed user defaults

  private var oscPosition: Preference.OSCPosition!
  private var useExtractSeek: Preference.SeekOption!
  private var relativeSeekAmount: Int = 3
  private var volumeScrollAmount: Int = 4
  private var horizontalScrollAction: Preference.ScrollAction!
  private var verticalScrollAction: Preference.ScrollAction!
  private var arrowBtnFunction: Preference.ArrowButtonAction!
  private var singleClickAction: Preference.MouseClickAction!
  private var doubleClickAction: Preference.MouseClickAction!
  private var rightClickAction: Preference.MouseClickAction!
  private var pinchAction: Preference.PinchAction!

  /** A list of observed preferences */
  private let observedPrefKeys: [String] = [
    PK.themeMaterial,
    PK.oscPosition,
    PK.showChapterPos,
    PK.useExactSeek,
    PK.relativeSeekAmount,
    PK.volumeScrollAmount,
    PK.horizontalScrollAction,
    PK.verticalScrollAction,
    PK.arrowButtonAction,
    PK.singleClickAction,
    PK.doubleClickAction,
    PK.rightClickAction,
    PK.pinchAction,
    PK.showRemainingTime,
    PK.blackOutMonitor,
    PK.alwaysFloatOnTop
  ]

  // MARK: - Outlets

  @IBOutlet weak var sideBarRightConstraint: NSLayoutConstraint!
  @IBOutlet weak var sideBarWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var bottomBarBottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var titleBarHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var oscTopMainViewTopConstraint: NSLayoutConstraint!
  var osdProgressBarWidthConstraint: NSLayoutConstraint!

  @IBOutlet weak var titleBarView: NSVisualEffectView!

  var standardWindowButtons: [NSButton] {
    get {
      return ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindowButton]).flatMap {
        window?.standardWindowButton($0)
      }
    }
  }

  var titleTextField: NSTextField? {
    get {
      return window?.standardWindowButton(.documentIconButton)?.superview?.subviews.flatMap({ $0 as? NSTextField }).first
    }
  }

  var currentControlBar: NSView?

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

  @available(macOS 10.12, *)
  lazy var pip: PIPViewController = {
    let pip = PIPViewController()
    pip.userCanResize = true
    pip.delegate = self
    return pip
  }()
  @available(macOS 10.12, *)
  lazy var pipVideo: NSViewController = {
    return NSViewController()
  }()

  // MARK: - Initialization


  override func windowWillLoad() {
    oscPosition = Preference.OSCPosition(rawValue: ud.integer(forKey: PK.oscPosition))
    relativeSeekAmount = ud.integer(forKey: PK.relativeSeekAmount)
    volumeScrollAmount = ud.integer(forKey: PK.volumeScrollAmount)
    horizontalScrollAction = Preference.ScrollAction(rawValue: ud.integer(forKey: PK.horizontalScrollAction))
    verticalScrollAction = Preference.ScrollAction(rawValue: ud.integer(forKey: PK.verticalScrollAction))
    useExtractSeek = Preference.SeekOption(rawValue: ud.integer(forKey: PK.useExactSeek))
    arrowBtnFunction = Preference.ArrowButtonAction(rawValue: ud.integer(forKey: PK.arrowButtonAction))
    singleClickAction = Preference.MouseClickAction(rawValue: ud.integer(forKey: PK.singleClickAction))
    doubleClickAction = Preference.MouseClickAction(rawValue: ud.integer(forKey: PK.doubleClickAction))
    rightClickAction = Preference.MouseClickAction(rawValue: ud.integer(forKey: PK.rightClickAction))
    pinchAction = Preference.PinchAction(rawValue: ud.integer(forKey: PK.pinchAction))
  }

  override func windowDidLoad() {

    super.windowDidLoad()

    guard let w = self.window else { return }
    
    // enable sleep preventer
    SleepPreventer.preventSleep()

    w.initialFirstResponder = nil

    w.center()

    w.styleMask.insert(NSFullSizeContentViewWindowMask)
    w.titlebarAppearsTransparent = true

    // need to deal with control bar, so handle it manually
    // w.isMovableByWindowBackground  = true

    // set background color to black
    w.backgroundColor = NSColor.black
    titleBarView.layerContentsRedrawPolicy = .onSetNeedsDisplay
    updateTitle()

    // set material
    setMaterial(Preference.Theme(rawValue: ud.integer(forKey: PK.themeMaterial)))

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

    //videoView.translatesAutoresizingMaskIntoConstraints = false
    //quickConstrants(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": videoView])

    videoView.videoLayer.display()

    // gesture recognizer
    cv.addGestureRecognizer(magnificationGestureRecognizer)

    // start mpv opengl_cb
    playerCore.startMPVOpenGLCB(videoView)

    // init quick setting view now
    let _ = quickSettingView

    // buffer indicator view
    bufferIndicatorView.layer?.cornerRadius = 10
    updateBufferIndicatorView()

    // other initialization
    [titleBarView, osdVisualEffectView, controlBarBottom, controlBarFloating, sideBarView, osdVisualEffectView, pipOverlayView].forEach {
      $0?.state = .active
    }
    osdVisualEffectView.isHidden = true
    osdVisualEffectView.layer?.cornerRadius = 10
    leftArrowLabel.isHidden = true
    rightArrowLabel.isHidden = true
    timePreviewWhenSeek.isHidden = true
    bottomView.isHidden = true
    pipOverlayView.isHidden = true
    rightLabel.mode = ud.bool(forKey: PK.showRemainingTime) ? .remaining : .duration

    osdProgressBarWidthConstraint = NSLayoutConstraint(item: osdAccessoryProgress, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 150)

    // add user default observers
    observedPrefKeys.forEach { key in
      ud.addObserver(self, forKeyPath: key, options: .new, context: nil)
    }

    // add notification observers
    let fsObserver = NotificationCenter.default.addObserver(forName: Constants.Noti.fsChanged, object: nil, queue: .main) { [unowned self] _ in
      let fs = self.playerCore.mpvController.getFlag(MPVOption.Window.fullscreen)
      if fs != self.isInFullScreen {
        self.toggleWindowFullScreen()
      }
    }
    let ontopObserver = NotificationCenter.default.addObserver(forName: Constants.Noti.ontopChanged, object: nil, queue: .main) { [unowned self] _ in
      let ontop = self.playerCore.mpvController.getFlag(MPVOption.Window.ontop)
      if ontop != self.isOntop {
        self.isOntop = ontop
        self.setWindowFloatingOnTop(ontop)
      }
    }
    let screenChangeObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSApplicationDidChangeScreenParameters, object: nil, queue: .main) { [unowned self] _ in
      // This observer handles a situation that the user connected a new screen or removed a screen
      if self.isInFullScreen && self.ud.bool(forKey: PK.blackOutMonitor) {
        if NSScreen.screens()?.count ?? 0 != self.cachedScreenCount {
          self.removeBlackWindow()
          self.blackOutOtherMonitors()
        }
      }
    }
    let changeWorkspaceObserver = NSWorkspace.shared().notificationCenter.addObserver(forName: NSNotification.Name.NSWorkspaceActiveSpaceDidChange, object: nil, queue: .main) { [unowned self] _ in
      if self.isInFullScreen && self.ud.bool(forKey: PK.blackOutMonitor) {
        if self.window?.isOnActiveSpace ?? false {
          self.removeBlackWindow()
          self.blackOutOtherMonitors()
        } else {
          self.removeBlackWindow()
        }
      }
    }

    notificationObservers.append(fsObserver)
    notificationObservers.append(ontopObserver)
    notificationObservers.append(screenChangeObserver)
    notificationObservers.append(changeWorkspaceObserver)
  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        self.ud.removeObserver(self, forKeyPath: key)
      }
      for observer in self.notificationObservers {
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    switch keyPath {

    case PK.themeMaterial:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
      }

    case PK.oscPosition:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        setupOnScreenController(position: Preference.OSCPosition(rawValue: newValue) ?? .floating)
      }

    case PK.showChapterPos:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        (playSlider.cell as! PlaySliderCell).drawChapters = newValue
      }

    case PK.useExactSeek:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        useExtractSeek = Preference.SeekOption(rawValue: newValue)
      }

    case PK.relativeSeekAmount:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        relativeSeekAmount = newValue.constrain(min: 1, max: 5)
      }

    case PK.volumeScrollAmount:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        volumeScrollAmount = newValue.constrain(min: 1, max: 4)
      }

    case PK.verticalScrollAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        verticalScrollAction = Preference.ScrollAction(rawValue: newValue)
      }

    case PK.horizontalScrollAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        horizontalScrollAction = Preference.ScrollAction(rawValue: newValue)
      }

    case PK.arrowButtonAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        arrowBtnFunction = Preference.ArrowButtonAction(rawValue: newValue)
      }

    case PK.arrowButtonAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        arrowBtnFunction = Preference.ArrowButtonAction(rawValue: newValue)
      }

    case PK.singleClickAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        singleClickAction = Preference.MouseClickAction(rawValue: newValue)
      }

    case PK.doubleClickAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        doubleClickAction = Preference.MouseClickAction(rawValue: newValue)
      }

    case PK.rightClickAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        rightClickAction = Preference.MouseClickAction(rawValue: newValue)
      }

    case PK.pinchAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        pinchAction = Preference.PinchAction(rawValue: newValue)
      }

    case PK.showRemainingTime:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        rightLabel.mode = newValue ? .remaining : .duration
        touchBarCurrentPosLabel?.mode = newValue ? .remaining : .current
      }
    
    case PK.blackOutMonitor:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        if isInFullScreen {
          if newValue {
            blackOutOtherMonitors()
          } else {
            removeBlackWindow()
          }
        }
      }

    case PK.alwaysFloatOnTop:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        if !playerCore.info.isPaused {
          self.isOntop = newValue
          setWindowFloatingOnTop(newValue)
        }
      }

    default:
      return
    }
  }

  func initVideoView() -> VideoView {
    let v = VideoView(frame: window!.contentView!.bounds)
    return v
  }

  func setupOnScreenController(position newPosition: Preference.OSCPosition) {

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
    switch oscPosition! {
    case .floating:
      currentControlBar = controlBarFloating
      fragControlView.setVisibilityPriority(NSStackViewVisibilityPriorityMustHold, for: fragControlViewLeftView)
      fragControlView.setVisibilityPriority(NSStackViewVisibilityPriorityMustHold, for: fragControlViewRightView)
      oscFloatingTopView.addView(fragVolumeView, in: .leading)
      oscFloatingTopView.addView(fragToolbarView, in: .trailing)
      oscFloatingTopView.addView(fragControlView, in: .center)
      oscFloatingBottomView.addSubview(fragSliderView)
      quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": fragSliderView])
      // center control bar
      let cph = ud.float(forKey: PK.controlBarPositionHorizontal)
      let cpv = ud.float(forKey: PK.controlBarPositionVertical)
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
    if !isInInteractiveMode {
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
            playerCore.abLoop()
            returnValue = 0
          default:
            returnValue = playerCore.mpvController.command(rawString: kb.rawAction)
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
  }

  /** record mouse pos on mouse down */
  override func mouseDown(with event: NSEvent) {
    guard !controlBarFloating.isDragging else { return }
    mousePosRelatedToWindow = event.locationInWindow
    // playlist resizing
    if sideBarStatus == .playlist {
      let sf = sideBarView.frame
      if NSPointInRect(mousePosRelatedToWindow!, NSMakeRect(sf.origin.x-4, sf.origin.y, 4, sf.height)) {
        isResizingSidebar = true
      }
    }
  }

  /** move window while dragging */
  override func mouseDragged(with event: NSEvent) {
    if isResizingSidebar {
      let currentLocation = event.locationInWindow
      let newWidth = window!.frame.width - currentLocation.x - 2
      sideBarWidthConstraint.constant = newWidth.constrain(min: PlaylistMinWidth, max: PlaylistMaxWidth)
    } else {
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

  /** if don't do so, window will jitter when dragging in titlebar */
  override func mouseUp(with event: NSEvent) {
    mousePosRelatedToWindow = nil
    if isDragging {
      // if it's a mouseup after dragging
      isDragging = false
    } else if isResizingSidebar {
      isResizingSidebar = false
      ud.set(Int(sideBarWidthConstraint.constant), forKey: PK.playlistWidth)
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
          if doubleClickAction! == .none {
            // if double click action is none, it's safe to perform action immediately
            performMouseAction(singleClickAction)
          } else {
            // else start a timer
            singleClickTimer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval(), target: self, selector: #selector(self.performMouseActionLater(_:)), userInfo: singleClickAction, repeats: false)
            mouseExitEnterCount = 0
          }
        } else if event.clickCount == 2 {
          // double click
          guard doubleClickAction! != .none else { return }
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

  @objc private func performMouseActionLater(_ timer: Timer) {
    guard let action = timer.userInfo as? Preference.MouseClickAction else { return }
    if mouseExitEnterCount >= 2 && action == .hideOSC {
      // the counter being greater than or equal to 2 means that the mouse re-entered the window
      // showUI() must be called due to the movement in the window, thus hideOSC action should be cancelled
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
      playerCore.togglePause(nil)

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
      isMouseInSlider = true
      if !controlBarFloating.isDragging {
        timePreviewWhenSeek.isHidden = false
      }
      let mousePos = playSlider.convert(event.locationInWindow, from: nil)
      updateTimeLabel(mousePos.x)
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
      updateTimeLabel(mousePos.x)
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    let mousePos = playSlider.convert(event.locationInWindow, from: nil)
    if isMouseInSlider {
      updateTimeLabel(mousePos.x)
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
      wasPlayingWhenSeekBegan = !playerCore.info.isPaused
      if wasPlayingWhenSeekBegan! {
        playerCore.togglePause(true)
      }
    }

    if isTrackpadEnd && wasPlayingWhenSeekBegan != nil {
      // only resume playback when it was playing when began
      if wasPlayingWhenSeekBegan! {
        playerCore.togglePause(false)
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
      playerCore.seek(relativeSecond: seekAmount, option: useExtractSeek)
    } else if scrollAction == .volume {
      // don't use precised delta for mouse
      let newVolume = playerCore.info.volume + (isMouse ? delta : AppData.volumeMap[volumeScrollAmount] * delta)
      playerCore.setVolume(newVolume)
      volumeSlider.doubleValue = newVolume
    }
  }

  func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard pinchAction != .none && !isInFullScreen else { return }
    guard !isInInteractiveMode, let window = window, let screenFrame = NSScreen.main()?.visibleFrame else { return }

    if pinchAction == .windowSize {
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
    if ud.bool(forKey: PK.alwaysFloatOnTop) {
      isOntop = true
      setWindowFloatingOnTop(true)
    }
    // truncate middle for title
    if let attrTitle = titleTextField?.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
      let p = attrTitle.attribute(NSParagraphStyleAttributeName, at: 0, effectiveRange: nil) as! NSMutableParagraphStyle
      p.lineBreakMode = .byTruncatingMiddle
      attrTitle.addAttribute(NSParagraphStyleAttributeName, value: p, range: NSRange(location: 0, length: attrTitle.length))
    }
  }

  func windowWillClose(_ notification: Notification) {
    // Close PIP
    if isInPIP {
      if #available(macOS 10.12, *) {
        exitPIP(manually: true)
      }
    }
    // stop playing
    if !playerCore.isMpvTerminated {
      playerCore.savePlaybackPosition()
      playerCore.stop()
      // videoView.stopDisplayLink()
    }
    playerCore.info.currentFolder = nil
    // disable sleep preventer
    if !playerCore.info.isPaused {
      SleepPreventer.allowSleep()
    }
    // stop tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
    cv.trackingAreas.forEach(cv.removeTrackingArea)
    playSlider.trackingAreas.forEach(playSlider.removeTrackingArea)
  }

  func windowWillEnterFullScreen(_ notification: Notification) {
    playerCore.mpvController.setFlag(MPVOption.Window.keepaspect, true)

    // Set the appearance to match the theme so the titlebar matches the theme
    switch(Preference.Theme(rawValue: ud.integer(forKey: PK.themeMaterial))!) {
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

    isInFullScreen = true
  }

  func windowWillExitFullScreen(_ notification: Notification) {
    playerCore.mpvController.setFlag(MPVOption.Window.keepaspect, false)

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


    isInFullScreen = false

    // set back frame of videoview, but only if not in PIP
    if !isInPIP {
      videoView.frame = window!.contentView!.frame
    }
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    if ud.bool(forKey: PK.blackOutMonitor) {
      removeBlackWindow()
    }
    
    if !playerCore.info.isPaused {
      setWindowFloatingOnTop(isOntop)
    }
  }

  func windowDidResize(_ notification: Notification) {
    guard let w = window else { return }
    let wSize = w.frame.size
    // is paused, draw new frame
    if playerCore.info.isPaused {
      videoView.videoLayer.draw()
    }

    // update videoview size if in full screen, since aspect ratio may changed
    if (isInFullScreen && !isInPIP) {

      // Let mpv decide where to draw
      /*
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
      */

      videoView.frame = NSRect(x: 0, y: 0, width: w.frame.width, height: w.frame.height)

    } else if (!isInPIP) {

      let frame = NSRect(x: 0, y: 0, width: w.contentView!.frame.width, height: w.contentView!.frame.height)

      if isInInteractiveMode {

        let origWidth = CGFloat(playerCore.info.videoWidth!)
        let origHeight = CGFloat(playerCore.info.videoHeight!)

        // if is in interactive mode
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
      let cph = ud.float(forKey: PK.controlBarPositionHorizontal)
      let cpv = ud.float(forKey: PK.controlBarPositionVertical)
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

  // MARK: - Control UI

  func hideUIAndCursor() {
    // don't hide UI when dragging control bar
    if controlBarFloating.isDragging {
      return
    }
    hideUI()
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  private func hideUI() {
    // Don't hide UI when in PIP
    guard !isInPIP || animationState == .hidden else {
      return
    }
    
    animationState = .willHide
    fadeableViews.forEach { (v) in
      v.isHidden = false
    }
    standardWindowButtons.forEach { $0.isEnabled = false }
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
    let timeout = ud.float(forKey: PK.controlBarAutoHideTimeout)
    hideControlTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideUIAndCursor), userInfo: nil, repeats: false)
  }

  func updateTitle() {
    window?.representedURL = playerCore.info.currentURL
    window?.setTitleWithRepresentedFilename(playerCore.info.currentURL?.path ?? "")
  }

  func displayOSD(_ message: OSDMessage) {
    if !playerCore.displayOSD { return }

    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    osdAnimationState = .shown
    [osdAccessoryText, osdAccessoryProgress].forEach { $0.isHidden = true }

    let (osdString, osdType) = message.message()

    let osdTextSize = ud.float(forKey: PK.osdTextSize)
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
        "duration": playerCore.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "position": playerCore.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "currChapter": (playerCore.mpvController.getInt(MPVProperty.chapter) + 1).toStr(),
        "chapterCount": playerCore.info.chapters.count.toStr()
      ]

      osdStackView.setVisibilityPriority(NSStackViewVisibilityPriorityMustHold, for: osdAccessoryView)
      osdAccessoryText.isHidden = false
      osdAccessoryText.stringValue = try! (try! Template(string: text)).render(osdData)
    }

    osdVisualEffectView.alphaValue = 1
    osdVisualEffectView.isHidden = false
    let timeout = ud.float(forKey: PK.osdAutoHideTimeout)
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

  func hideSideBar(_ after: @escaping () -> Void = { }) {
    sidebarAnimationState = .willHide
    let currWidth = sideBarWidthConstraint.constant
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = SideBarAnimationDuration
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
    playerCore.togglePause(true)
    isInInteractiveMode = true
    hideUI()
    bottomView.isHidden = false
    bottomView.addSubview(cropSettingsView.view)
    quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": cropSettingsView.view])

    // get original frame
    let origWidth = CGFloat(playerCore.info.videoWidth!)
    let origHeight = CGFloat(playerCore.info.videoHeight!)
    let origSize = NSMakeSize(origWidth, origHeight)
    let currWidth = CGFloat(playerCore.info.displayWidth!)
    let currHeight = CGFloat(playerCore.info.displayHeight!)
    let winFrame = window!.frame
    let videoViewFrame: NSRect
    let videoRect: NSRect

    // get current cropped region
    if let cropFilter = playerCore.info.cropFilter {
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
    quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": cropSettingsView.cropBoxView])

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
    playerCore.togglePause(false)
    isInInteractiveMode = false
    cropSettingsView.cropBoxView.isHidden = true
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = CropAnimationDuration
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
      bottomBarBottomConstraint.animator().constant = -bottomViewHeight
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
  private func updateTimeLabel(_ mouseXPos: CGFloat) {
    let timeLabelXPos = playSlider.frame.origin.y + 15
    timePreviewWhenSeek.frame.origin = CGPoint(x: round(mouseXPos + playSlider.frame.origin.x - timePreviewWhenSeek.frame.width / 2), y: timeLabelXPos + 1)
    let sliderFrame = playSlider.bounds
    var percentage = Double((mouseXPos - 3) / (sliderFrame.width - 6))
    if percentage < 0 {
      percentage = 0
    }
    if let duration = playerCore.info.videoDuration {
      timePreviewWhenSeek.stringValue = (duration * percentage).stringRepresentation
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

    if playerCore.info.isNetworkResource {
      bufferIndicatorView.isHidden = false
      bufferSpin.startAnimation(nil)
      bufferProgressLabel.stringValue = "Opening stream..."
      bufferDetailLabel.stringValue = ""
    } else {
      bufferIndicatorView.isHidden = true
    }
  }

  // MARK: - Window size / aspect

  func windowFrameFromGeometry(newSize: NSSize? = nil) -> NSRect? {
    // set geometry. using `!` should be safe since it passed the regex.
    if let geometry = cachedGeometry ?? playerCore.getGeometry(), let screenFrame = NSScreen.main()?.visibleFrame {
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

  /** Set video size when info available. */
  func adjustFrameByVideoSize(_ videoWidth: Int, _ videoHeight: Int) {
    guard let w = window else { return }

    // if no video track
    var width = videoWidth
    var height = videoHeight
    if width == 0 { width = AppData.widthWhenNoVideo }
    if height == 0 { height = AppData.heightWhenNoVideo }

    // if video has rotation
    let rotate = playerCore.mpvController.getInt(MPVProperty.videoParamsRotate)
    if rotate == 90 || rotate == 270 {
      swap(&width, &height)
    }

    // set aspect ratio
    let originalVideoSize = NSSize(width: width, height: height)
    w.aspectRatio = originalVideoSize

    videoView.videoSize = w.convertToBacking(videoView.frame).size

    if isInFullScreen {

      self.windowDidResize(Notification(name: .NSWindowDidResize))

    } else {

      var rect: NSRect
      let needResizeWindow = playerCore.info.justOpenedFile || !ud.bool(forKey: PK.resizeOnlyWhenManuallyOpenFile)

      if needResizeWindow {
        // get videoSize on screen
        var videoSize = originalVideoSize
        if ud.bool(forKey: PK.usePhysicalResolution) {
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

      if (!window!.isVisible) {
        window!.setIsVisible(true)
      }

      // maybe not a good position, consider putting these at playback-restart
      playerCore.info.justOpenedFile = false
      playerCore.info.justStartedFile = false

    }

    // UI and slider
    updatePlayTime(withDuration: true, andProgressBar: true)
    updateVolume()
  }
  
  func blackOutOtherMonitors() {
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
  
  func removeBlackWindow() {
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
    guard let duration = playerCore.info.videoDuration, let pos = playerCore.info.videoPosition else {
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
    volumeSlider.doubleValue = playerCore.info.volume
    muteButton.state = playerCore.info.isMuted ? NSOnState : NSOffState
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
    let needShowIndicator = playerCore.info.pausedForCache || playerCore.info.isSeeking

    if needShowIndicator {
      let sizeStr = FileSize.format(playerCore.info.cacheSize, unit: .kb)
      let usedStr = FileSize.format(playerCore.info.cacheUsed, unit: .kb)
      let speedStr = FileSize.format(playerCore.info.cacheSpeed, unit: .b)
      let bufferingState = playerCore.info.bufferingState
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
      playerCore.togglePause(false)
    }
    if sender.state == NSOffState {
      playerCore.togglePause(true)
      // speed is already reset by playerCore
      speedValueIndex = AppData.availableSpeedValues.count / 2
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = true
      // set speed to 0 if is fastforwarding
      if isFastforwarding {
        playerCore.setSpeed(1)
        isFastforwarding = false
      }
    }
  }

  /** mute button */
  @IBAction func muteButtonAction(_ sender: NSButton) {
    playerCore.toogleMute(nil)
    if playerCore.info.isMuted {
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
    switch arrowBtnFunction! {
    case .speed:
      isFastforwarding = true
      let speedValue = AppData.availableSpeedValues[speedValueIndex]
      playerCore.setSpeed(speedValue)
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
        playerCore.togglePause(false)
      }

    case .playlist:
      playerCore.mpvController.command(left ? .playlistPrev : .playlistNext, checkError: false)

    case .seek:
      playerCore.seek(relativeSecond: left ? -10 : 10, option: .relative)

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
    timePreviewWhenSeek.stringValue = (playerCore.info.videoDuration! * percentage * 0.01).stringRepresentation
    playerCore.seek(percent: percentage, forceExact: true)
  }


  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.doubleValue
    playerCore.setVolume(value)
  }

  // MARK: - Utility

  private func quickConstraints(_ constrants: [String], _ views: [String: NSView]) {
    constrants.forEach { c in
      let cc = NSLayoutConstraint.constraints(withVisualFormat: c, options: [], metrics: nil, views: views)
      NSLayoutConstraint.activate(cc)
    }
  }

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
    switch cmd {
    case .openFile:
      (NSApp.delegate! as! AppDelegate).openFile(self)
    case .openURL:
      (NSApp.delegate! as! AppDelegate).openURL(self)
    case .togglePIP:
      if #available(OSX 10.12, *) {
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
      self.menuToggleFlip(.dummy)
    case .mirror:
      self.menuToggleMirror(.dummy)
    case .saveCurrentPlaylist:
      self.menuSavePlaylist(.dummy)
    case .deleteCurrentFile:
      self.menuDeleteCurrentFile(.dummy)
    case .findOnlineSubs:
      self.menuFindOnlineSub(.dummy)
    case .saveDownloadedSub:
      self.saveDownloadedSub(.dummy)
    }
  }

}

// MARK: - Picture in Picture

@available(macOS 10.12, *)
extension MainWindowController: PIPViewControllerDelegate {

  func enterPIP() {
    // FIXME: Internal PIP API
    // Do not enter PIP if already "PIPing"  (in this case, in the PIP animation)
    // Also do not enter if PIP state cannot be determined
    let pipping = pip.value(forKey: "_pipping") as? Bool ?? true
    guard !pipping else {
      return
    }
    pipVideo.view = videoView
    pip.aspectRatio = NSSize(width: playerCore.info.videoWidth!, height: playerCore.info.videoHeight!)
    pip.playing = !playerCore.info.isPaused
    pip.title = window?.title
    pip.presentAsPicture(inPicture: pipVideo)
    pipOverlayView.isHidden = false
    isInPIP = true
  }

  func exitPIP(manually: Bool) {
    isInPIP = false
    if manually {
      pip.dismissViewController(pipVideo)
    }
    pipOverlayView.isHidden = true
    window?.contentView?.addSubview(videoView, positioned: .below, relativeTo: nil)
    videoView.frame = window?.contentView?.frame ?? .zero

    // Reset animation (disabling it if exitPIP is called manually)
    // See WebKit issue 25096170 as well as the workaround:
    // https://trac.webkit.org/browser/trunk/Source/WebCore/platform/mac/WebVideoFullscreenInterfaceMac.mm#L343
    pip.replacementRect = .infinite
    pip.replacementWindow = nil
  }

  func pipShouldClose(_ pip: PIPViewController) -> Bool {
    // Set frame to animate back to
    pip.replacementRect = window?.contentView?.frame ?? .zero
    pip.replacementWindow = window
    return true
  }

  func pipDidClose(_ pip: PIPViewController) {
    exitPIP(manually: false)
  }

  func pipActionPlay(_ pip: PIPViewController) {
    playerCore.togglePause(false)
  }

  func pipActionPause(_ pip: PIPViewController) {
    playerCore.togglePause(true)
  }

  func pipActionStop(_ pip: PIPViewController) {
    exitPIP(manually: false)
  }
}

protocol SidebarViewController {
  var downShift: CGFloat { get set }
}
