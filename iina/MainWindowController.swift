//
//  MainWindowController.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MainWindowController: NSWindowController, NSWindowDelegate {

  unowned let ud: UserDefaults = UserDefaults.standard
  let minSize = NSMakeSize(500, 300)
  let bottomViewHeight: CGFloat = 60

  unowned let playerCore: PlayerCore = PlayerCore.shared
  lazy var videoView: VideoView = self.initVideoView()
  lazy var sizingTouchBarTextField: NSTextField = {
    return NSTextField()
  }()
  var touchBarPosLabelWidthLayout: NSLayoutConstraint?

  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false

  var isInFullScreen: Bool = false {
    didSet {
      playerCore.mpvController.setFlag(MPVOption.Window.fullscreen, isInFullScreen)
    }
  }
  var isInInteractiveMode: Bool = false

  // FIXME: might use another obj to handle slider?
  var isMouseInWindow: Bool = false
  var isMouseInSlider: Bool = false

  override var windowNibName: String {
    return "MainWindowController"
  }

  var fadeableViews: [NSView?] = []

  /** Animation state of he hide/show part */
  enum UIAnimationState {
    case shown, hidden, willShow, willHide
  }

  var animationState: UIAnimationState = .shown

  var osdAnimationState: UIAnimationState = .hidden

  /** For auto hiding ui after a timeout */
  var hideControlTimer: Timer?

  var hideOSDTimer: Timer?


  /** Cache current crop */
  var currentCrop: NSRect = NSRect()
  
  /** The maximum pressure recorded when clicking on the arrow buttons **/
  var maxPressure: Int32 = 0
  
  /** The value of speedValueIndex before Force Touch **/
  var oldIndex: Int = AppData.availableSpeedValues.count / 2
  
  /** The index of current speed in speed value array */
  var speedValueIndex: Int = AppData.availableSpeedValues.count / 2 {
    didSet {
      if speedValueIndex < 0 || speedValueIndex >= AppData.availableSpeedValues.count {
        speedValueIndex = AppData.availableSpeedValues.count / 2
      }
    }
  }

  enum ScrollDirection {
    case horizontal
    case vertical
  }

  var scrollDirection: ScrollDirection?

  private var useExtrackSeek: Preference.SeekOption!
  private var relativeSeekAmount: Int = 3
  private var arrowBtnFunction: Preference.ArrowButtonAction!
  private var singleClickAction: Preference.MouseClickAction!
  private var doubleClickAction: Preference.MouseClickAction!

  private var singleClickTimer: Timer?

  /** A list of observed preferences */

  private let observedPrefKeys: [String] = [
    Preference.Key.themeMaterial,
    Preference.Key.showChapterPos,
    Preference.Key.useExactSeek,
    Preference.Key.relativeSeekAmount,
    Preference.Key.arrowButtonAction,
    Preference.Key.singleClickAction,
    Preference.Key.doubleClickAction
  ]

  private var notificationObservers: [NSObjectProtocol] = []

  /** The view embedded in sidebar */
  enum SideBarViewType {
    case hidden  // indicating sidebar is hidden. Should only be used by sideBarStatus
    case settings
    case playlist
    func width() -> CGFloat {
      switch self {
      case .settings:
        return 360
      case .playlist:
        return 240
      default:
        Utility.fatal("SideBarViewType.width shouldn't be called here")
        return 0
      }
    }
  }

  var sideBarStatus: SideBarViewType = .hidden

  @IBOutlet weak var sideBarRightConstraint: NSLayoutConstraint!
  @IBOutlet weak var sideBarWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var bottomBarBottomConstraint: NSLayoutConstraint!

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

  var magnificationGestureRecognizer: NSMagnificationGestureRecognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(MainWindowController.handleMagnifyGesture(recognizer:)))

  @IBOutlet weak var titleBarView: NSVisualEffectView!
  @IBOutlet weak var titleTextField: NSTextField!
  @IBOutlet weak var controlBar: ControlBarView!
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

  @IBOutlet weak var rightLabel: NSTextField!
  @IBOutlet weak var leftLabel: NSTextField!
  @IBOutlet weak var leftArrowLabel: NSTextField!
  @IBOutlet weak var rightArrowLabel: NSTextField!
  @IBOutlet weak var osdVisualEffectView: NSVisualEffectView!
  @IBOutlet weak var osd: NSTextField!

  weak var touchBarPlaySlider: NSSlider?
  weak var touchBarCurrentPosLabel: NSTextField?


  override func windowDidLoad() {

    super.windowDidLoad()

    guard let w = self.window else { return }

    w.titleVisibility = .hidden;
    w.styleMask.insert(NSFullSizeContentViewWindowMask);
    w.titlebarAppearsTransparent = true

    // need to deal with control bar, so handle it manually
    // w.isMovableByWindowBackground  = true

    // set background color to black
    w.backgroundColor = NSColor.black
    titleBarView.layerContentsRedrawPolicy = .onSetNeedsDisplay;
    updateTitle()

    // set material
    setMaterial(Preference.Theme(rawValue: ud.integer(forKey: Preference.Key.themeMaterial)))

    // size
    w.minSize = minSize
    // fade-able views
    withStandardButtons { button in
      self.fadeableViews.append(button)
    }
    fadeableViews.append(titleBarView)
    fadeableViews.append(controlBar)
    guard let cv = w.contentView else { return }

    // sidebar views
    sideBarView.isHidden = true

    // video view
    // note that don't use auto resize for it (handle in windowDidResize)
    cv.autoresizesSubviews = false
    cv.addSubview(videoView, positioned: .below, relativeTo: nil)

    // gesture recognizer
    // disable it first for poor performance
    // cv.addGestureRecognizer(magnificationGestureRecognizer)

    // start mpv opengl_cb
    playerCore.startMPVOpenGLCB(videoView)

    // init quick setting view now
    let _ = quickSettingView

    // buffer indicator view
    bufferIndicatorView.layer?.cornerRadius = 10
    updateBufferIndicatorView()

    // other initialization
    osdVisualEffectView.isHidden = true
    osdVisualEffectView.layer?.cornerRadius = 10
    leftArrowLabel.isHidden = true
    rightArrowLabel.isHidden = true
    timePreviewWhenSeek.isHidden = true
    bottomView.isHidden = true

    useExtrackSeek = Preference.SeekOption(rawValue: ud.integer(forKey: Preference.Key.useExactSeek))
    arrowBtnFunction = Preference.ArrowButtonAction(rawValue: ud.integer(forKey: Preference.Key.arrowButtonAction))
    singleClickAction = Preference.MouseClickAction(rawValue: ud.integer(forKey: Preference.Key.singleClickAction))
    doubleClickAction = Preference.MouseClickAction(rawValue: ud.integer(forKey: Preference.Key.doubleClickAction))

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
    notificationObservers.append(fsObserver)

    // move to center and make main
    w.center()
    w.makeMain()
    w.makeKeyAndOrderFront(nil)
    w.setIsVisible(false)
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

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }

    switch keyPath {

    case Preference.Key.themeMaterial:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
      }

    case Preference.Key.showChapterPos:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Bool {
        (playSlider.cell as! PlaySliderCell).drawChapters = newValue
      }

    case Preference.Key.useExactSeek:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
          useExtrackSeek = Preference.SeekOption(rawValue: newValue)
      }

    case Preference.Key.relativeSeekAmount:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        relativeSeekAmount = newValue.constrain(min: 1, max: 5)
      }

    case Preference.Key.arrowButtonAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        arrowBtnFunction = Preference.ArrowButtonAction(rawValue: newValue)
      }

    case Preference.Key.singleClickAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        singleClickAction = Preference.MouseClickAction(rawValue: newValue)
      }

    case Preference.Key.doubleClickAction:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        doubleClickAction = Preference.MouseClickAction(rawValue: newValue)
      }

    default:
      return
    }
  }

  // MARK: - Lazy initializers

  func initVideoView() -> VideoView {
    let v = VideoView(frame: window!.contentView!.bounds)
    return v
  }

  // MARK: - Mouse / Trackpad event

  override func keyDown(with event: NSEvent) {
    window!.makeFirstResponder(window!.contentView)
    if !isInInteractiveMode {
      playerCore.execKeyCode(Utility.mpvKeyCode(from: event))
    }
  }

  /** record mouse pos on mouse down */
  override func mouseDown(with event: NSEvent) {
    guard !controlBar.isDragging else { return }
    mousePosRelatedToWindow = NSEvent.mouseLocation()
    mousePosRelatedToWindow!.x -= window!.frame.origin.x
    mousePosRelatedToWindow!.y -= window!.frame.origin.y
  }

  /** move window while dragging */
  override func mouseDragged(with event: NSEvent) {
    isDragging = true
    guard !controlBar.isDragging else { return }
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
      };
    }
  }

  /** if don't do so, window will jitter when dragging in titlebar */
  override func mouseUp(with event: NSEvent) {
    mousePosRelatedToWindow = nil
    if isDragging {
      // if it's a mouseup after dragging
      isDragging = false
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

  @objc private func performMouseActionLater(_ timer: Timer) {
    guard let action = timer.userInfo as? Preference.MouseClickAction else { return }
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
    }
  }

  override func mouseEntered(with event: NSEvent) {
    guard !isInInteractiveMode else { return }
    guard let obj = event.trackingArea?.userInfo?["obj"] as? Int else {
      Utility.log("No data for tracking area")
      return
    }
    if obj == 0 {
      // main window
      isMouseInWindow = true
      showUI()
    } else if obj == 1 {
      // slider
      isMouseInSlider = true
      timePreviewWhenSeek.isHidden = false
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
    if obj == 0 {
      // main window
      isMouseInWindow = false
      if controlBar.isDragging { return }
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
      showUIAndUpdateTimer()
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

    // handle the delta value
    let seekFactor = AppData.seekAmountMap[relativeSeekAmount]!
    let isPrecise = event.hasPreciseScrollingDeltas
    let isNatural = event.isDirectionInvertedFromDevice

    var deltaX = isPrecise ? Double(event.scrollingDeltaX) : event.scrollingDeltaX.unifiedDouble
    var deltaY = isPrecise ? Double(event.scrollingDeltaY) : event.scrollingDeltaY.unifiedDouble * 2

    if !isNatural {
      deltaX = -deltaX
      deltaY = -deltaY
    }

    if scrollDirection == .horizontal {
      playerCore.seek(relativeSecond: seekFactor * deltaX, option: useExtrackSeek)
    } else if scrollDirection == .vertical {
      let newVolume = playerCore.info.volume - Int(deltaY)
      playerCore.setVolume(newVolume)
      volumeSlider.integerValue = newVolume
    }
  }

  func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard !isInInteractiveMode else { return }
    guard window != nil else { return }
    let scale = recognizer.magnification * 10
    let newWidth = window!.frame.width + scale
    let newSize = NSSize(width: newWidth, height: window!.frame.width / (window!.aspectRatio.width / window!.aspectRatio.height))
    let newFrame = window!.frame.centeredResize(to: newSize)
    window!.setFrame(newFrame, display: true, animate: false)
  }

  // MARK: - Window delegate

  /** A method being called when window open. Pretend to be a window delegate. */
  func windowDidOpen() {
    // update buffer indicator view
    updateBufferIndicatorView()
    // enable sleep preventer
    SleepPreventer.preventSleep()
    // start tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
    cv.addTrackingArea(NSTrackingArea(rect: cv.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 0]))
    playSlider.addTrackingArea(NSTrackingArea(rect: playSlider.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 1]))
  }

  func windowWillClose(_ notification: Notification) {
    // stop playing
    if !playerCore.isMpvTerminated {
      playerCore.stop()
      videoView.stopDisplayLink()
    }
    // disable sleep preventer
    SleepPreventer.allowSleep()
    // stop tracking mouse event
    guard let w = self.window, let cv = w.contentView else { return }
    cv.trackingAreas.forEach(cv.removeTrackingArea)
    playSlider.trackingAreas.forEach(playSlider.removeTrackingArea)
  }

  func windowWillEnterFullScreen(_ notification: Notification) {
    // show titlebar
    window!.titlebarAppearsTransparent = false
    window!.titleVisibility = .visible
    removeTitlebarFromFadeableViews()
    // stop animation and hide titleBarView
    animationState = .hidden
    titleBarView.isHidden = true
    isInFullScreen = true
  }

  func windowWillExitFullScreen(_ notification: Notification) {
    // hide titlebar
    window!.titlebarAppearsTransparent = true
    window!.titleVisibility = .hidden
    // show titleBarView
    titleBarView.isHidden = false
    animationState = .shown
    addBackTitlebarToFadeableViews()
    isInFullScreen = false
    // set back frame of videoview
    videoView.frame = window!.contentView!.frame
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    // if is floating, enable it again
    if playerCore.info.isAlwaysOntop {
      setWindowFloatingOntop(true)
    }
  }

  func windowDidResize(_ notification: Notification) {
    guard let w = window else { return }
    let wSize = w.frame.size, cSize = controlBar.frame.size

    // update videoview size if in full screen, since aspect ratio may changed
    if (isInFullScreen) {

      let aspectRatio = w.aspectRatio.width / w.aspectRatio.height
      let tryHeight = wSize.width / aspectRatio
      if tryHeight <= wSize.height {
        // should have black bar above and below
        let targetHeight = wSize.width / aspectRatio
        let yOffset = (wSize.height - targetHeight) / 2
        videoView.frame = NSMakeRect(0, yOffset, wSize.width, targetHeight)
      } else if tryHeight > wSize.height{
        // should have black bar left and right
        let targetWidth = wSize.height * aspectRatio
        let xOffset = (wSize.width - targetWidth) / 2
        videoView.frame = NSMakeRect(xOffset, 0, targetWidth, wSize.height)
      }

    } else {

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
    let cph = ud.float(forKey: Preference.Key.controlBarPositionHorizontal)
    let cpv = ud.float(forKey: Preference.Key.controlBarPositionVertical)
    controlBar.setFrameOrigin(NSMakePoint(
      wSize.width * CGFloat(cph) - cSize.width * 0.5,
      wSize.height * CGFloat(cpv)
    ))
  }

  /** resize framebuffer in videoView after resizing. */
  func windowDidEndLiveResize(_ notification: Notification) {
    videoView.videoSize = window!.convertToBacking(videoView.frame).size
    // new (empty) frame buffer is created, so draw a frame manually
    videoView.drawFrame()
  }

  // MARK: - Control UI

  func hideUIAndCursor() {
    // don't hide UI when dragging control bar
    if controlBar.isDragging {
      return
    }
    hideUI()
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  private func hideUI() {
    fadeableViews.forEach { (v) in
      v?.alphaValue = 1
    }
    animationState = .willHide
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = 0.5
      fadeableViews.forEach { (v) in
        v?.animator().alphaValue = 0
      }
    }) {
      // if no interrupt then hide animation
      if self.animationState == .willHide {
        self.fadeableViews.forEach { (v) in
          v?.isHidden = true
        }
        self.animationState = .hidden
      }
    }
  }

  private func showUI () {
    animationState = .willShow
    fadeableViews.forEach { (v) in
      v?.isHidden = false
      v?.alphaValue = 0
    }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = 0.5
      fadeableViews.forEach { (v) in
        v?.animator().alphaValue = 1
      }
    }) {
      self.animationState = .shown
    }
  }

  private func showUIAndUpdateTimer() {
    if animationState == .hidden {
      showUI()
    }
    // if timer exist, destroy first
    if hideControlTimer != nil {
      hideControlTimer!.invalidate()
      hideControlTimer = nil
    }
    // create new timer
    let timeout = ud.float(forKey: Preference.Key.controlBarAutoHideTimeout)
    hideControlTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideUIAndCursor), userInfo: nil, repeats: false)
  }

  func updateTitle() {
    if let w = window, let url = playerCore.info.currentURL?.lastPathComponent {
      w.title = url
      titleTextField.stringValue = url
    }
  }

  func displayOSD(_ message: OSDMessage) {
    if !playerCore.displayOSD { return }

    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    osdAnimationState = .shown
    let osdTextSize = ud.float(forKey: Preference.Key.osdTextSize)
    osd.font = NSFont.systemFont(ofSize: CGFloat(osdTextSize))
    osd.stringValue = message.message()
    osdVisualEffectView.alphaValue = 1
    osdVisualEffectView.isHidden = false
    let timeout = ud.float(forKey: Preference.Key.osdAutoHideTimeout)
    hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
  }

  @objc private func hideOSD() {
    NSAnimationContext.runAnimationGroup({ (context) in
      self.osdAnimationState = .willHide
      context.duration = 0.5
      osdVisualEffectView.animator().alphaValue = 0
    }) {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
      }
    }
  }

  private func showSideBar(view: NSView, type: SideBarViewType) {
    // adjust sidebar width
    let width = type.width()
    sideBarWidthConstraint.constant = width
    sideBarRightConstraint.constant = -width
    sideBarView.isHidden = false
    // add view and constraints
    sideBarView.addSubview(view)
    let constraintsH = NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[v]-0-|", options: [], metrics: nil, views: ["v": view])
    let constraintsV = NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[v]-0-|", options: [], metrics: nil, views: ["v": view])
    NSLayoutConstraint.activate(constraintsH)
    NSLayoutConstraint.activate(constraintsV)
    // show sidebar
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
      sideBarRightConstraint.animator().constant = 0
    }) {
      self.sideBarStatus = type
    }
  }

  func hideSideBar(_ after: @escaping () -> Void = {}) {
    let currWidth = sideBarWidthConstraint.constant
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
      sideBarRightConstraint.animator().constant = -currWidth
    }) {
      self.sideBarStatus = .hidden
      self.sideBarView.subviews.removeAll()
      self.sideBarView.isHidden = true
      after()
    }
  }

  private func removeTitlebarFromFadeableViews() {
    // remove buttons from fade-able views
    withStandardButtons { button in
      if let index = (self.fadeableViews.index {$0 === button}) {
        self.fadeableViews.remove(at: index)
      }
    }
    // remove titlebar view from fade-able views
    if let index = (self.fadeableViews.index {$0 === titleBarView}) {
      self.fadeableViews.remove(at: index)
    }
  }

  private func addBackTitlebarToFadeableViews() {
    // add back buttons to fade-able views
    withStandardButtons { button in
      self.fadeableViews.append(button)
    }
    // add back titlebar view to fade-able views
    self.fadeableViews.append(titleBarView)
  }

  func enterInteractiveMode() {
    playerCore.togglePause(true)
    isInInteractiveMode = true
    hideUI()
    bottomView.isHidden = false
    bottomView.addSubview(cropSettingsView.view)
    quickConstrants(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": cropSettingsView.view])

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
    quickConstrants(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": cropSettingsView.cropBoxView])

    // show crop settings view
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = 0.2
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
      context.duration = 0.2
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
    timePreviewWhenSeek.frame.origin = CGPoint(x: mouseXPos + playSlider.frame.origin.x - timePreviewWhenSeek.frame.width / 2, y: timeLabelXPos)
    let percentage = Double((mouseXPos - 3) / 354)
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

    [titleBarView, controlBar, osdVisualEffectView].forEach {
      $0?.material = material
      $0?.appearance = appearance
    }

    [muteButton, playButton, leftArrowButton, rightArrowButton, settingsButton, playlistButton].forEach { btn in
      guard let currImageName = btn?.image?.name() else { return }
      if currImageName.hasSuffix("-dark") {
        if isDarkTheme {
          // dark image but with dark theme: remove "-dark"
          let newName = currImageName.substring(to: currImageName.index(currImageName.endIndex, offsetBy: -5))
          btn?.image = NSImage(named: newName)
          if let currAltImageName = btn?.alternateImage?.name() {
            btn?.alternateImage = NSImage(named: currAltImageName.substring(to: currAltImageName.index(currAltImageName.endIndex, offsetBy: -5)))
          }
        }
      } else {
        // light image but with light theme: add "-dark"
        if !isDarkTheme {
          btn?.image = NSImage(named: currImageName + "-dark")
          if let currAltImageName = btn?.alternateImage?.name() {
            btn?.alternateImage = NSImage(named: currAltImageName + "-dark")
          }
        }
      }
    }
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

  /** Set video size when info available. */
  func adjustFrameByVideoSize(_ width: Int, _ height: Int) {
    guard let w = window else { return }
    // set aspect ratio
    let originalVideoSize = NSSize(width: width, height: height)
    w.aspectRatio = originalVideoSize

    videoView.videoSize = originalVideoSize
    videoView.restartDisplayLink()

    if isInFullScreen {

      self.windowDidResize(Notification(name: .NSWindowDidResize))

    } else {

      if playerCore.info.jumppedFromPlaylist &&
        ud.bool(forKey: Preference.Key.resizeOnlyWhenManuallyOpenFile) {
        // user is navigating in playlist. remain same window width.
        let newHeight = w.frame.width / CGFloat(width) * CGFloat(height)
        let rect = NSRect(origin: w.frame.origin, size: NSSize(width: w.frame.width, height: newHeight))
        w.setFrame(rect, display: true, animate: true)
      } else {
        // get videoSize on screen
        var videoSize = originalVideoSize
        if ud.bool(forKey: Preference.Key.usePhysicalResolution) {
          videoSize = w.convertFromBacking(
            NSMakeRect(w.frame.origin.x, w.frame.origin.y, CGFloat(width), CGFloat(height))
          ).size
        }
        // check screen size
        if let screenSize = NSScreen.main()?.visibleFrame.size {
          videoSize = videoSize.satisfyMaxSizeWithSameAspectRatio(screenSize)
          // check default window position
        }
        let rect = w.frame.centeredResize(to: videoSize.satisfyMinSizeWithSameAspectRatio(minSize))
        w.setFrame(rect, display: true, animate: true)
      }

      if (!window!.isVisible) {
        window!.setIsVisible(true)
      }

      playerCore.info.jumppedFromPlaylist = false

    }

    // UI and slider
    updatePlayTime(withDuration: true, andProgressBar: true)
    updateVolume()
  }

  /** Important: `window.toggleFullScreen` should never be called directly, since it can't handle floating window. */
  func toggleWindowFullScreen() {
    // if is floating, disable it temporarily.
    // it will be enabled again in `windowDidExitFullScreen()`.
    if !isInFullScreen && playerCore.info.isAlwaysOntop {
      setWindowFloatingOntop(false)
    }
    window?.toggleFullScreen(self)
  }

  func setWindowFloatingOntop(_ onTop: Bool) {
    guard let window = window else { return }
    if onTop {
      window.level = Int(CGWindowLevelForKey(.floatingWindow))
    } else {
      window.level = Int(CGWindowLevelForKey(.normalWindow))
    }
    // don't know why they will be disabled
    withStandardButtons { $0?.isEnabled = true }
  }

  // MARK: - Sync UI with playback

  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    guard let duration = playerCore.info.videoDuration, let pos = playerCore.info.videoPosition else {
      Utility.fatal("video info not available")
      return
    }
    let percantage = (pos.second / duration.second) * 100
    leftLabel.stringValue = pos.stringRepresentation
    touchBarCurrentPosLabel?.stringValue = pos.stringRepresentation
    if withDuration {
      rightLabel.stringValue = duration.stringRepresentation
    }
    if andProgressBar {
      playSlider.doubleValue = percantage
      touchBarPlaySlider?.doubleValue = percantage
    }
  }

  func updateVolume() {
    volumeSlider.integerValue = playerCore.info.volume
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
      bufferProgressLabel.stringValue = String(format: NSLocalizedString("main.buffering_indicator",comment:"Buffering... %s%%"),bufferingState)
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
        if maxPressure == 1 { // Single click ended
          speedValueIndex = oldIndex - 1
        } else { // Force Touch ended
          speedValueIndex = speeds / 2
        }
        maxPressure = 0
      } else {
        if sender.intValue == 1 && maxPressure == 0 { // First press
          oldIndex = speedValueIndex
          speedValueIndex -= 1
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
        if maxPressure == 1 { // Single click ended
          speedValueIndex = oldIndex + 1
        } else { // Force Touch ended
          speedValueIndex = speeds / 2
        }
        maxPressure = 0
      } else {
        if sender.intValue == 1 && maxPressure == 0 { // First press
          oldIndex = speedValueIndex
          speedValueIndex += 1
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
      playerCore.mpvController.command(left ? .playlistPrev : .playlistNext)

    case .seek:
      playerCore.seek(relativeSecond: left ? -10 : 10, option: .relative)

    }
  }

  @IBAction func settingsButtonAction(_ sender: AnyObject) {
    let view = quickSettingView.view
    switch sideBarStatus {
    case .hidden:
      showSideBar(view: view, type: .settings)
    case .playlist:
      hideSideBar {
        self.showSideBar(view: view, type: .settings)
      }
    case .settings:
      hideSideBar()
    }
  }

  @IBAction func playlistButtonAction(_ sender: AnyObject) {
    let view = playlistView.view
    switch sideBarStatus {
    case .hidden:
      showSideBar(view: view, type: .playlist)
    case .playlist:
      hideSideBar()
    case .settings:
      hideSideBar {
        self.showSideBar(view: view, type: .playlist)
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
      x: sender.knobPointPosition() - timePreviewWhenSeek.frame.width / 2,
      y: playSlider.frame.origin.y + 15)
    timePreviewWhenSeek.stringValue = (playerCore.info.videoDuration! * percentage * 0.01).stringRepresentation
    playerCore.seek(percent: percentage, forceExact: true)
  }


  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.integerValue
    playerCore.setVolume(value)
  }


  // MARK: - Utilility

  private func withStandardButtons(_ block: (NSButton?) -> Void) {
    guard let w = window else { return }
    block(w.standardWindowButton(.closeButton))
    block(w.standardWindowButton(.miniaturizeButton))
    block(w.standardWindowButton(.zoomButton))
  }

  private func quickConstrants(_ constrants: [String], _ views: [String: NSView]) {
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

}



// MARK: - Touch bar

fileprivate extension NSTouchBarCustomizationIdentifier {

  static let windowBar = NSTouchBarCustomizationIdentifier("\(Bundle.main.bundleIdentifier!).windowTouchBar")

}

fileprivate extension NSTouchBarItemIdentifier {

  static let playPause = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.playPause")
  static let slider = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.slider")
  static let volumeUp = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voUp")
  static let volumeDown = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.voDn")
  static let rewind = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.rewind")
  static let fastForward = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.forward")
  static let time = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.time")
  static let ahead15Sec = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.ahead15Sec")
  static let back15Sec = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.back15Sec")
  static let ahead30Sec = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.ahead30Sec")
  static let back30Sec = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.back30Sec")
  static let next = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.next")
  static let prev = NSTouchBarItemIdentifier("\(Bundle.main.bundleIdentifier!).TouchBarItem.prev")

}


// Image name, tag, custom label
@available(OSX 10.12.2, *)
fileprivate let touchBarItemBinding: [NSTouchBarItemIdentifier: (String, Int, String)] = [
  .ahead15Sec: (NSImageNameTouchBarSkipAhead15SecondsTemplate, 15, "15sec Ahead"),
  .ahead30Sec: (NSImageNameTouchBarSkipAhead30SecondsTemplate, 30, "30sec Ahead"),
  .back15Sec: (NSImageNameTouchBarSkipBack15SecondsTemplate, -15, "-15sec Ahead"),
  .back30Sec: (NSImageNameTouchBarSkipBack30SecondsTemplate, -30, "-30sec Ahead"),
  .next: (NSImageNameTouchBarSkipAheadTemplate, 0, "Next video"),
  .prev: (NSImageNameTouchBarSkipBackTemplate, 1, "Previous video"),
  .volumeUp: (NSImageNameTouchBarVolumeUpTemplate, 0, "Volume +"),
  .volumeDown: (NSImageNameTouchBarVolumeDownTemplate, 1, "Volume -"),
  .rewind: (NSImageNameTouchBarRewindTemplate, 0, "Rewind"),
  .fastForward: (NSImageNameTouchBarFastForwardTemplate, 1, "Fast forward")
]

@available(OSX 10.12.2, *)
extension MainWindowController: NSTouchBarDelegate {

  override func makeTouchBar() -> NSTouchBar? {
    let touchBar = NSTouchBar()
    touchBar.delegate = self
    touchBar.customizationIdentifier = .windowBar
    touchBar.defaultItemIdentifiers = [.playPause, .slider, .time]
    touchBar.customizationAllowedItemIdentifiers = [.playPause, .slider, .volumeUp, .volumeDown, .rewind, .fastForward, .time, .ahead15Sec, .ahead30Sec, .back15Sec, .back30Sec, .next, .prev, .fixedSpaceLarge]
    return touchBar
  }

  func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItemIdentifier) -> NSTouchBarItem? {

    switch identifier {

    case NSTouchBarItemIdentifier.playPause:
      let item = NSCustomTouchBarItem(identifier: identifier)
      item.view = NSButton(image: NSImage(named: NSImageNameTouchBarPauseTemplate)!, target: self, action: #selector(self.touchBarPlayBtnAction(_:)))
      item.customizationLabel = "Play / Pause"
      return item

    case NSTouchBarItemIdentifier.slider:
      let item = NSSliderTouchBarItem(identifier: identifier)
      item.slider.minValue = 0
      item.slider.maxValue = 100
      item.slider.target = self
      item.slider.action = #selector(self.touchBarSliderAction(_:))
      item.customizationLabel = "Seek"
      self.touchBarPlaySlider = item.slider
      return item

    case NSTouchBarItemIdentifier.volumeUp,
         NSTouchBarItemIdentifier.volumeDown:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarVolumeAction(_:)))

    case NSTouchBarItemIdentifier.rewind,
         NSTouchBarItemIdentifier.fastForward:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarRewindAction(_:)))

    case NSTouchBarItemIdentifier.time:
      let item = NSCustomTouchBarItem(identifier: identifier)
      let label = NSTextField(labelWithString: "0:00")
      label.alignment = .center
      self.touchBarCurrentPosLabel = label
      item.view = label
      item.customizationLabel = "Time Position"
      return item

    case NSTouchBarItemIdentifier.ahead15Sec,
         NSTouchBarItemIdentifier.back15Sec,
         NSTouchBarItemIdentifier.ahead30Sec,
         NSTouchBarItemIdentifier.back30Sec:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarSeekAction(_:)))

    case NSTouchBarItemIdentifier.next,
         NSTouchBarItemIdentifier.prev:
      guard let data = touchBarItemBinding[identifier] else { return nil }
      return buttonTouchBarItem(withIdentifier: identifier, imageName: data.0, tag: data.1, customLabel: data.2, action: #selector(self.touchBarSkipAction(_:)))

    default:
      return nil
    }
  }

  func touchBarPlayBtnAction(_ sender: NSButton) {
    if playerCore.info.isPaused {
      sender.image = NSImage(named: NSImageNameTouchBarPauseTemplate)
    } else {
      sender.image = NSImage(named: NSImageNameTouchBarPlayTemplate)
    }
    playerCore.togglePause(nil)
  }

  func touchBarVolumeAction(_ sender: NSButton) {
    let currVolume = playerCore.info.volume
    playerCore.setVolume(currVolume + (sender.tag == 0 ? 5 : -5))
  }

  func touchBarRewindAction(_ sender: NSButton) {
    arrowButtonAction(left: sender.tag == 0)
  }

  func touchBarSeekAction(_ sender: NSButton) {
    let sec = sender.tag
    playerCore.seek(relativeSecond: Double(sec), option: .relative)
  }

  func touchBarSkipAction(_ sender: NSButton) {
    playerCore.navigateInPlaylist(nextOrPrev: sender.tag == 0)
  }

  func touchBarSliderAction(_ sender: NSSlider) {
    let percentage = 100 * sender.doubleValue / sender.maxValue
    playerCore.seek(percent: percentage)
  }

  private func buttonTouchBarItem(withIdentifier identifier: NSTouchBarItemIdentifier, imageName: String, tag: Int, customLabel: String, action: Selector) -> NSCustomTouchBarItem {
    let item = NSCustomTouchBarItem(identifier: identifier)
    let button = NSButton(image: NSImage(named: imageName)!, target: self, action: action)
    button.tag = tag
    item.view = button
    item.customizationLabel = customLabel
    return item
  }

  // MARK: - Set TouchBar Time Label

  func setupTouchBarUI() {
    guard let duration = playerCore.info.videoDuration else {
      Utility.fatal("video info not available")
      return
    }

    let pad: CGFloat = 16.0
    sizingTouchBarTextField.stringValue = duration.stringRepresentation
    if let widthConstant = sizingTouchBarTextField.cell?.cellSize.width, let posLabel = touchBarCurrentPosLabel {
      if let posConstraint = touchBarPosLabelWidthLayout {
        posConstraint.constant = widthConstant + pad
        posLabel.setNeedsDisplay()
      } else {
        let posConstraint = NSLayoutConstraint(item: posLabel, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: widthConstant + pad)
        posLabel.addConstraint(posConstraint)
        touchBarPosLabelWidthLayout = posConstraint
      }
    }

  }
}
