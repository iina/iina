//
//  MainWindowController.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MainWindowController: NSWindowController, NSWindowDelegate {
  
  let ud: UserDefaults = UserDefaults.standard
  let minSize = NSMakeSize(500, 300)
  
  lazy var playerCore = PlayerCore.shared
  lazy var videoView: VideoView = self.initVideoView()
  
  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  
  var isInFullScreen: Bool = false
  
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
  
  /** The index of current speed in speed value array */
  var speedValueIndex: Int = 5
  
  enum ScrollDirection {
    case horizontal
    case vertical
  }
  
  var scrollDirection: ScrollDirection?
  
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
    cv.addTrackingArea(NSTrackingArea(rect: cv.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 0]))
    
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
    
    // other initialization
    osdVisualEffectView.isHidden = true
    osdVisualEffectView.layer?.cornerRadius = 10
    leftArrowLabel.isHidden = true
    rightArrowLabel.isHidden = true
    timePreviewWhenSeek.isHidden = true
    playSlider.addTrackingArea(NSTrackingArea(rect: playSlider.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: ["obj": 1]))
    
    // add user default observers
    ud.addObserver(self, forKeyPath: Preference.Key.themeMaterial, options: .new, context: nil)
    
    // move to center and make main
    w.center()
    w.makeMain()
    w.makeKeyAndOrderFront(nil)
    w.setIsVisible(false)
  }
  
  func windowWillClose(_ notification: Notification) {
    ud.removeObserver(self, forKeyPath: Preference.Key.themeMaterial)
  }
  
  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }
    
    switch keyPath {
      
    case Preference.Key.themeMaterial:
      if let newValue = change[NSKeyValueChangeKey.newKey] as? Int {
        setMaterial(Preference.Theme(rawValue: newValue))
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
    
    playerCore.execKeyCode(Utility.mpvKeyCode(from: event))
  }
  
  /** record mouse pos on mouse down */
  override func mouseDown(with event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    mousePosRelatedToWindow = NSEvent.mouseLocation()
    mousePosRelatedToWindow!.x -= window!.frame.origin.x
    mousePosRelatedToWindow!.y -= window!.frame.origin.y
  }
  
  /** move window while dragging */
  override func mouseDragged(with event: NSEvent) {
    isDragging = true
    if controlBar.isDragging {
      return
    }
    if mousePosRelatedToWindow != nil {
      let currentLocation = NSEvent.mouseLocation()
      let newOrigin = CGPoint(
        x: currentLocation.x - mousePosRelatedToWindow!.x,
        y: currentLocation.y - mousePosRelatedToWindow!.y
      )
      window?.setFrameOrigin(newOrigin)
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
      if !mouseInSideBar && sideBarStatus != .hidden {
        hideSideBar()
      }
    }
  }
  
  override func mouseEntered(with event: NSEvent) {
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
    let mousePos = playSlider.convert(event.locationInWindow, from: nil)
    if isMouseInSlider {
      updateTimeLabel(mousePos.x)
    }
    if isMouseInWindow {
      showUIAndUpdateTimer()
    }
  }
  
  override func scrollWheel(with event: NSEvent) {
    if event.phase.contains(.began) {
      if event.scrollingDeltaX != 0 {
        scrollDirection = .horizontal
      } else if event.scrollingDeltaY != 0 {
        scrollDirection = .vertical
      }
    } else if event.phase.contains(.ended) {
      scrollDirection = nil
    }
    // handle the value
    let seekFactor = 0.05
    if scrollDirection == .horizontal {
       playerCore.seek(relativeSecond: seekFactor * Double(event.scrollingDeltaX), exact: true)
    } else if scrollDirection == .vertical {
      let newVolume = playerCore.info.volume - Int(event.scrollingDeltaY)
      playerCore.setVolume(newVolume)
      volumeSlider.integerValue = newVolume
    }
  }
  
  func handleMagnifyGesture(recognizer: NSMagnificationGestureRecognizer) {
    guard window != nil else { return }
    let scale = recognizer.magnification * 10
    let newWidth = window!.frame.width + scale
    let newSize = NSSize(width: newWidth, height: window!.frame.width / (window!.aspectRatio.width / window!.aspectRatio.height))
    let newFrame = window!.frame.centeredResize(to: newSize)
    window!.setFrame(newFrame, display: true, animate: false)
  }
  
  // MARK: - Window delegate
  
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
      videoView.setFrameSize(w.contentView!.frame.size)
      
    }
    // update control bar position
    let cph = ud.float(forKey: Preference.Key.controlBarPositionHorizontal)
    let cpv = ud.float(forKey: Preference.Key.controlBarPositionVertical)
    controlBar.setFrameOrigin(NSMakePoint(
      wSize.width * CGFloat(cph) - cSize.width * 0.5,
      wSize.height * CGFloat(cpv)
    ))
  }
  
  // MARK: - Control UI
  
  func hideUIAndCurdor() {
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
    hideControlTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideUIAndCurdor), userInfo: nil, repeats: false)
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
    let timeout = ud.integer(forKey: Preference.Key.osdAutoHideTimeout)
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
  
  private func hideSideBar(_ after: @escaping () -> Void = {}) {
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
  
  /** Display time label when mouse over slider */
  private func updateTimeLabel(_ mouseXPos: CGFloat) {
    let timeLabelXPos = playSlider.frame.origin.y + 15
    timePreviewWhenSeek.frame.origin = CGPoint(x: mouseXPos + playSlider.frame.origin.x - timePreviewWhenSeek.frame.width / 2, y: timeLabelXPos)
    let percentage = Double(mouseXPos / playSlider.frame.width)
    timePreviewWhenSeek.stringValue = (playerCore.info.videoDuration! * percentage).stringRepresentation
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
  
  // MARK: - Window size / aspect
  
  /** Set video size when info available. */
  func adjustFrameByVideoSize(_ width: Int, _ height: Int) {
    guard let w = window else { return }
    // set aspect ratio
    let originalVideoSize = NSSize(width: width, height: height)
    w.aspectRatio = originalVideoSize
    videoView.videoSize = originalVideoSize
    
    if isInFullScreen {
      self.windowDidResize(Notification(name: .NSWindowDidResize))
      return
    }
    // get videoSize on screen
    var videoSize = w.convertFromBacking(
      NSMakeRect(w.frame.origin.x, w.frame.origin.y, CGFloat(width), CGFloat(height))
    ).size
    // check screen size
    if let screenSize = NSScreen.main()?.visibleFrame.size {
      videoSize = videoSize.satisfyMaxSizeWithSameAspectRatio(screenSize)
      // check default window position
    }
    
    let rect = w.frame.centeredResize(to: videoSize.satisfyMinSizeWithSameAspectRatio(minSize))
    w.setFrame(rect, display: true, animate: true)
    if (!window!.isVisible) {
      window!.setIsVisible(true)
    }
    // UI and slider
    updatePlayTime(withDuration: true, andProgressBar: true)
    updateVolume()
  }
  
  // MARK: - Sync UI with playback
  
  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    guard let duration = playerCore.info.videoDuration, let pos = playerCore.info.videoPosition else {
      Utility.fatal("video info not available")
      return
    }
    let percantage = (Double(pos.second) / Double(duration.second)) * 100
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
      speedValueIndex = 5
      leftArrowLabel.isHidden = true
      rightArrowLabel.isHidden = true
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
      speedValueIndex = 5
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
    arrowButtonAction(left: true)
  }
  
  @IBAction func rightButtonAction(_ sender: NSButton) {
    arrowButtonAction(left: false)
  }
  
  /** handle action of both left and right arrow button */
  func arrowButtonAction(left: Bool) {
    let actionType = Preference.ArrowButtonAction(rawValue: ud.integer(forKey: Preference.Key.arrowButtonAction))
    switch actionType! {
    case .speed:
      if left {
        if speedValueIndex >= 5 {
          speedValueIndex = 4
        } else if speedValueIndex <= 0 {
          speedValueIndex = 0
        } else {
          speedValueIndex -= 1
        }
      } else {
        if speedValueIndex <= 5 {
          speedValueIndex = 6
        } else if speedValueIndex >= 10 {
          speedValueIndex = 10
        } else {
          speedValueIndex += 1
        }
      }
      let speedValue = AppData.availableSpeedValues[speedValueIndex]
      playerCore.setSpeed(speedValue)
      if speedValueIndex == 5 {
        leftArrowLabel.isHidden = true
        rightArrowLabel.isHidden = true
      } else if speedValueIndex < 5 {
        leftArrowLabel.isHidden = false
        rightArrowLabel.isHidden = true
        leftArrowLabel.stringValue = String(format: "%.0fx", speedValue)
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
      break
    case .seek:
      playerCore.seek(relativeSecond: left ? -10 : 10)
      break
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
    playerCore.seek(percent: percentage)
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
  
}

// MARK: - Menu Actions

extension MainWindowController {
  
  @IBAction func menuTogglePause(_ sender: NSMenuItem) {
    if sender.title == "Play" {
      playerCore.togglePause(false)
      sender.title = "Pause"
    } else {
      playerCore.togglePause(true)
      sender.title = "Play"
    }
  }
  
  @IBAction func menuStop(_ sender: NSMenuItem) {
    // FIXME: handle stop
    playerCore.stop()
    displayOSD(.stop)
  }
  
  @IBAction func menuStep(_ sender: NSMenuItem) {
    if sender.tag == 0 { // -> 5s
      playerCore.seek(relativeSecond: 5)
    } else if sender.tag == 1 { // <- 5s
      playerCore.seek(relativeSecond: -5)
    }
  }
  
  @IBAction func menuStepFrame(_ sender: NSMenuItem) {
    if !playerCore.info.isPaused {
      playerCore.togglePause(true)
    }
    if sender.tag == 0 { // -> 1f
      playerCore.frameStep(backwards: false)
    } else if sender.tag == 1 { // <- 1f
      playerCore.frameStep(backwards: true)
    }
  }
  
  
  @IBAction func menuJumpToBegin(_ sender: NSMenuItem) {
    playerCore.seek(absoluteSecond: 0)
  }
  
  @IBAction func menuJumpTo(_ sender: NSMenuItem) {
    let _ = Utility.quickPromptPanel(messageText: "Jump to:", informativeText: "Example: 20:35") { input in
      if let vt = VideoTime(input) {
        self.playerCore.seek(absoluteSecond: Double(vt.second))
      }
    }
  }
  
  @IBAction func menuSnapshot(_ sender: NSMenuItem) {
    playerCore.screenShot()
    displayOSD(.screenShot)
  }
  
  @IBAction func menuABLoop(_ sender: NSMenuItem) {
    playerCore.abLoop()
    displayOSD(.abLoop(playerCore.info.abLoopStatus))
  }
  
  @IBAction func menuPlaylistItem(_ sender: NSMenuItem) {
    let index = sender.tag
    playerCore.playFileInPlaylist(index)
  }
  
  @IBAction func menuShowPlaylistPanel(_ sender: NSMenuItem) {
    playlistView.pleaseSwitchToTab(.playlist)
    playlistButtonAction(sender)
  }
  
  @IBAction func menuShowChaptersPanel(_ sender: NSMenuItem) {
    playlistView.pleaseSwitchToTab(.chapters)
    playlistButtonAction(sender)
  }
  
  @IBAction func menuChapterSwitch(_ sender: NSMenuItem) {
    let index = sender.tag
    playerCore.playChapter(index)
    let chapter = playerCore.info.chapters[index]
    displayOSD(.chapter(chapter.title))
  }
  
  @IBAction func menuShowVideoQuickSettings(_ sender: NSMenuItem) {
    quickSettingView.pleaseSwitchToTab(.video)
    settingsButtonAction(sender)
  }
  
  @IBAction func menuShowAudioQuickSettings(_ sender: NSMenuItem) {
    quickSettingView.pleaseSwitchToTab(.audio)
    settingsButtonAction(sender)
  }
  
  @IBAction func menuShowSubQuickSettings(_ sender: NSMenuItem) {
    quickSettingView.pleaseSwitchToTab(.sub)
    settingsButtonAction(sender)
  }
  
  @IBAction func menuChangeTrack(_ sender: NSMenuItem) {
    if let trackObj = sender.representedObject as? MPVTrack {
      playerCore.setTrack(trackObj.id, forType: trackObj.type)
    }
  }

  @IBAction func menuChangeAspect(_ sender: NSMenuItem) {
    if let aspectStr = sender.representedObject as? String {
      playerCore.setVideoAspect(aspectStr)
      displayOSD(.aspect(aspectStr))
    } else {
      Utility.log("Unknown aspect in menuChangeAspect(): \(sender.representedObject)")
    }
  }
  
  @IBAction func menuChangeCrop(_ sender: NSMenuItem) {
    guard let vwidth = playerCore.info.videoWidth, let vheight = playerCore.info.videoHeight else {
      Utility.log("Cannot get video width and height")
      return
    }
    if let cropStr = sender.representedObject as? String {
      if let aspect = Aspect(string: cropStr) {
        let cropped = NSMakeSize(CGFloat(vwidth), CGFloat(vheight)).crop(withAspect: aspect)
        let vf = MPVFilter.crop(w: Int(cropped.width), h: Int(cropped.height), x: nil, y: nil)
        playerCore.addVideoFilter(vf)
        // warning! may should not update it here
        playerCore.info.unsureCrop = cropStr
        playerCore.info.cropFilter = vf
      } else {
        if let filter = playerCore.info.cropFilter {
          playerCore.removeVideoFiler(filter)
          playerCore.info.unsureCrop = "None"
        }
      }
    } else {
      Utility.log("sender.representedObject is not a string in menuChangeCrop()")
    }
  }
  
  @IBAction func menuChangeRotation(_ sender: NSMenuItem) {
    if let rotationInt = sender.representedObject as? Int {
      playerCore.setVideoRotate(rotationInt)
    }
  }
  
  @IBAction func menuToggleFlip(_ sender: NSMenuItem) {
    if playerCore.info.flipFilter == nil {
      playerCore.setFlip(true)
    } else {
      playerCore.setFlip(false)
    }
  }
  
  @IBAction func menuToggleMirror(_ sender: NSMenuItem) {
    if playerCore.info.mirrorFilter == nil {
      playerCore.setMirror(true)
    } else {
      playerCore.setMirror(false)
    }
  }
  
  @IBAction func menuToggleDeinterlace(_ sender: NSMenuItem) {
    playerCore.toggleDeinterlace(sender.state != NSOnState)
  }
  
  @IBAction func menuChangeWindowSize(_ sender: NSMenuItem) {
    // -1: normal(non-retina), same as 1 when on non-retina screen
    //  0: half
    //  1: normal
    //  2: double
    //  3: fit screen
    //  10: smaller size
    //  11: bigger size
    let size = sender.tag
    guard let w = window, let vw = playerCore.info.displayWidth, let vh = playerCore.info.displayHeight else { return }
    
    var retinaSize = w.convertFromBacking(NSMakeRect(w.frame.origin.x, w.frame.origin.y, CGFloat(vw), CGFloat(vh)))
    let screenFrame = NSScreen.main()!.visibleFrame
    let newFrame: NSRect
    let sizeMap: [CGFloat] = [0.5, 1, 2]
    let scaleStep: CGFloat = 25
    
    switch size {
    // scale
    case 0, 1, 2:
      retinaSize.size.width *= sizeMap[size]
      retinaSize.size.height *= sizeMap[size]
      if retinaSize.size.width > screenFrame.size.width || retinaSize.size.height > screenFrame.size.height {
        newFrame = w.frame.centeredResize(to: w.frame.size.shrink(toSize: screenFrame.size)).constrain(in: screenFrame)
      } else {
        newFrame = w.frame.centeredResize(to: retinaSize.size).constrain(in: screenFrame)
      }
    // fit screen
    case 3:
      w.center()
      newFrame = w.frame.centeredResize(to: w.frame.size.shrink(toSize: screenFrame.size))
    // bigger size
    case 10, 11:
      let newWidth = w.frame.width + scaleStep * (size == 10 ? -1 : 1)
      let newHeight = newWidth / (w.aspectRatio.width / w.aspectRatio.height)
      newFrame = w.frame.centeredResize(to: NSSize(width: newWidth, height: newHeight))
    default:
      return
    }
    
    w.setFrame(newFrame, display: true, animate: true)
  }
  
  @IBAction func menuAlwaysOnTop(_ sender: NSMenuItem) {
    guard let w = window else { return }
    if playerCore.info.isAlwaysOntop {
      w.level = Int(CGWindowLevelForKey(.baseWindow))
      w.level = Int(CGWindowLevelForKey(.normalWindow))
      playerCore.info.isAlwaysOntop = false
    } else {
      w.level = Int(CGWindowLevelForKey(.floatingWindow))
      w.level = Int(CGWindowLevelForKey(.maximumWindow))
      playerCore.info.isAlwaysOntop = true
    }
  }
  
  @IBAction func menuToggleFullScreen(_ sender: NSMenuItem) {
    guard let w = window else { return }
    w.toggleFullScreen(sender)
    sender.title = isInFullScreen ? Constants.String.exitFullScreen : Constants.String.fullScreen
  }
  
  @IBAction func menuChangeVolume(_ sender: NSMenuItem) {
    if let volumeDelta = sender.representedObject as? Int {
      let newVolume = volumeDelta + playerCore.info.volume
      playerCore.setVolume(newVolume)
    } else {
      Utility.log("sender.representedObject is not int in menuChangeVolume()")
    }
  }
  
  @IBAction func menuToggleMute(_ sender: NSMenuItem) {
    playerCore.toogleMute(nil)
    updateVolume()
  }
  
  @IBAction func menuChangeAudioDelay(_ sender: NSMenuItem) {
    if let delayDelta = sender.representedObject as? Double {
      let newDelay = playerCore.info.audioDelay + delayDelta
      playerCore.setAudioDelay(newDelay)
    } else {
      Utility.log("sender.representedObject is not Double in menuChangeAudioDelay()")
    }
  }
  
  @IBAction func menuResetAudioDelay(_ sender: NSMenuItem) {
    playerCore.setAudioDelay(0)
  }
  
  @IBAction func menuLoadExternalSub(_ sender: NSMenuItem) {
    let _ = Utility.quickOpenPanel(title: "Load external subtitle file") { url in
      self.playerCore.loadExternalSubFile(url)
    }
  }
  
  @IBAction func menuChangeSubDelay(_ sender: NSMenuItem) {
    if let delayDelta = sender.representedObject as? Double {
      let newDelay = playerCore.info.subDelay + delayDelta
      playerCore.setSubDelay(newDelay)
    } else {
      Utility.log("sender.representedObject is not Double in menuChangeSubDelay()")
    }
  }
  
  @IBAction func menuChangeSubScale(_ sender: NSMenuItem) {
    if sender.tag == 0 {
      playerCore.setSubScale(1)
      return
    }
    // FIXME: better refactor this part
    let amount = sender.tag > 0 ? 0.1 : -0.1
    let currentScale = playerCore.mpvController.getDouble(MPVOption.Subtitles.subScale)
    let displayValue = currentScale >= 1 ? currentScale : -1/currentScale
    let truncated = round(displayValue * 100) / 100
    var newTruncated = truncated + amount
    // range for this value should be (~, -1), (1, ~)
    if newTruncated > 0 && newTruncated < 1 || newTruncated > -1 && newTruncated < 0 {
      newTruncated = -truncated + amount
    }
    playerCore.setSubScale(abs(newTruncated > 0 ? newTruncated : 1 / newTruncated))
  }
  
  @IBAction func menuResetSubDelay(_ sender: NSMenuItem) {
    playerCore.setSubDelay(0)
  }
  
  @IBAction func menuSetSubEncoding(_ sender: NSMenuItem) {
    playerCore.setSubEncoding((sender.representedObject as? String) ?? "auto")
  }
  
  @IBAction func menuSubFont(_ sender: NSMenuItem) {
    Utility.quickFontPickerWindow() {
      self.playerCore.setSubFont($0 ?? "")
    }
    
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
    playerCore.setSpeed(0)
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
    playerCore.seek(relativeSecond: Double(sec))
  }
  
  func touchBarSkipAction(_ sender: NSButton) {
    if sender.tag == 0 {
      // next
      playerCore.mpvController.command(.playlistNext)
    } else {
      // prev
      playerCore.mpvController.command(.playlistPrev)
    }
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
  
}
