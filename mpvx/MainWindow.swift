//
//  MainWindow.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MainWindow: NSWindowController, NSWindowDelegate {
  
  let ud: UserDefaults = UserDefaults.standard
  
  var playerController: PlayerController!
  lazy var videoView: VideoView! = self.initVideoView()
  
  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  
  override var windowNibName: String {
    return "MainWindow"
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
  
  @IBOutlet weak var titleBarView: NSVisualEffectView!
  @IBOutlet weak var titleBarTitleCell: NSTextFieldCell!
  @IBOutlet weak var controlBar: ControlBarView!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var playSlider: NSSlider!
  @IBOutlet weak var volumeSlider: NSSlider!
  
  @IBOutlet weak var rightLabel: NSTextField!
  @IBOutlet weak var leftLabel: NSTextField!
  @IBOutlet weak var osd: NSTextField!

  override func windowDidLoad() {
    super.windowDidLoad()
    guard let w = self.window else { return }
    w.titleVisibility = .hidden;
    w.styleMask.insert(NSFullSizeContentViewWindowMask);
    w.titlebarAppearsTransparent = true
    // need to deal with control bar, so handle it manually
    // w.isMovableByWindowBackground  = true
    updateTitle()
    if #available(OSX 10.11, *), UserDefaults.standard.bool(forKey: Preference.Key.controlBarDarker) {
      titleBarView.material = .ultraDark
    }
    // size
    w.minSize = NSMakeSize(200, 200)
    // fade-able views
    fadeableViews.append(w.standardWindowButton(.closeButton))
    fadeableViews.append(w.standardWindowButton(.miniaturizeButton))
    fadeableViews.append(w.standardWindowButton(.zoomButton))
    fadeableViews.append(titleBarView)
    fadeableViews.append(controlBar)
    guard let cv = w.contentView else { return }
    cv.addTrackingArea(NSTrackingArea(rect: cv.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: nil))
    // video view
    cv.addSubview(videoView, positioned: .below, relativeTo: nil)
    playerController.startMPVOpenGLCB(videoView)
    // other initialization
    osd.isHidden = true
    // make main
    w.makeMain()
    w.makeKeyAndOrderFront(nil)
    w.setIsVisible(false)
  }
  
  // MARK: - Lazy initializers
  
  func initVideoView() -> VideoView {
    let v = VideoView(frame: window!.contentView!.bounds)
    return v
  }
  
  // MARK: - NSWindowDelegate
  
  override func keyDown(_ event: NSEvent) {
    playerController.togglePause(nil)
  }
  
  /** record mouse pos on mouse down */
  override func mouseDown(_ event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    mousePosRelatedToWindow = NSEvent.mouseLocation()
    mousePosRelatedToWindow!.x -= window!.frame.origin.x
    mousePosRelatedToWindow!.y -= window!.frame.origin.y
  }
  
  /** move window while dragging */
  override func mouseDragged(_ event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    Swift.print(mousePosRelatedToWindow)
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
  override func mouseUp(_ event: NSEvent) {
    mousePosRelatedToWindow = nil
  }
  
  override func mouseEntered(_ event: NSEvent) {
    showUI()
  }
  
  override func mouseExited(_ event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    hideUI()
  }
  
  override func mouseMoved(_ event: NSEvent) {
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
  
  // MARK: - Control UI
  
  func hideUIAndCurdor() {
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
  
  func updateTitle() {
    if let w = window, url = playerController.info.currentURL?.lastPathComponent {
      w.title = url
      titleBarTitleCell.title = url
    }
  }
  
  func displayOSD(_ message: String) {
    if hideOSDTimer != nil {
      hideOSDTimer!.invalidate()
      hideOSDTimer = nil
    }
    osdAnimationState = .shown
    osd.stringValue = message
    osd.alphaValue = 1
    osd.isHidden = false
    let timeout = ud.integer(forKey: Preference.Key.osdAutoHideTimeout)
    hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
  }
  
  @objc private func hideOSD() {
    NSAnimationContext.runAnimationGroup({ (context) in
      self.osdAnimationState = .willHide
      context.duration = 0.5
      osd.animator().alphaValue = 0
    }) {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
      }
    }
  }
  
  // MARK: - Window size
  
  func windowDidResize(_ notification: Notification) {
    if let w = window {
      let wSize = w.frame.size, cSize = controlBar.frame.size
      w.setFrame(w.constrainFrameRect(w.frame, to: w.screen), display: false)
      // update control bar position
      let cph = ud.float(forKey: Preference.Key.controlBarPositionHorizontal)
      let cpv = ud.float(forKey: Preference.Key.controlBarPositionVertical)
      controlBar.setFrameOrigin(NSMakePoint(
        wSize.width * CGFloat(cph) - cSize.width * 0.5,
        wSize.height * CGFloat(cpv)
      ))
    }
  }
  
  /** Set video size when info available. */
  func adjustFrameByVideoSize() {
    guard let width = playerController.info.videoWidth, let height = playerController.info.videoHeight else {
      Utility.fatal("video info not available")
      return
    }
    // set aspect ratio
    let aspectRatio = Float(width) / Float(height)
    var videoSize = NSSize(width: width, height: height)
    self.window!.aspectRatio = videoSize
    // check screen size
    let screenSizeOptional = NSScreen.main()?.visibleFrame.size
    if let screenSize = screenSizeOptional {
      // check if video size > screen size
      let tryWidth = CGFloat(Float(screenSize.height) * aspectRatio)
      let tryHeight = CGFloat(Float(screenSize.width) / aspectRatio)
      if screenSize.width >= videoSize.width {
        if screenSize.height < videoSize.height {
          videoSize.height = screenSize.height
          videoSize.width = tryWidth
        }
      } else {
        // screenSize.width < videoSize.width
        if screenSize.height < videoSize.height {
          if (screenSize.height >= tryHeight) {
            videoSize.width = screenSize.width
            videoSize.height = tryHeight
          } else {
            videoSize.height = screenSize.height
            videoSize.width = tryWidth
          }
        } else {
          videoSize.width = screenSize.width
          videoSize.height = tryHeight
        }
      }
      // check default window position
    }
    
    self.window!.setContentSize(videoSize)
    if self.videoView.videoSize == nil {
      self.videoView.videoSize = videoSize
    }
    window!.setIsVisible(true)
    // UI and slider
    updatePlayTime(withDuration: true, andProgressBar: true)
    updateVolume()
  }
  
  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    guard let duration = playerController.info.videoDuration, let pos = playerController.info.videoPosition else {
      Utility.fatal("video info not available")
      return
    }
    let percantage = (Double(pos.second) / Double(duration.second)) * 100
    leftLabel.stringValue = pos.stringRepresentation
    if withDuration {
      rightLabel.stringValue = duration.stringRepresentation
    }
    if andProgressBar {
      playSlider.doubleValue = percantage
    }
  }
  
  func updateVolume() {
    let volume = ud.integer(forKey: Preference.Key.softVolume)
    playerController.setVolume(volume)
    volumeSlider.integerValue = volume
  }
  
  // MARK: - IBAction
  
  /** Play button: pause & resume */
  @IBAction func playButtonAction(_ sender: NSButton) {
    if sender.state == NSOnState {
      playerController.togglePause(true)
    }
    if sender.state == NSOffState {
      playerController.togglePause(false)
    }
  }
  
  /** When slider changes */
  @IBAction func playSliderChanges(_ sender: NSSlider) {
    guard let duration = playerController.info.videoDuration else {
      Utility.fatal("video info not available")
      return
    }
    let percentage = 100 * sender.doubleValue / sender.maxValue
    playerController.seek(percent: percentage)
  }
  
  
  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.integerValue
    playerController.setVolume(value)
    displayOSD("Volume: \(value)")
  }
  
  
}
