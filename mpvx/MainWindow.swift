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
  
  @IBOutlet weak var btn: NSButton!
  
  override var windowNibName: String {
    return "MainWindow"
  }
  
  var fadeableViews: [NSView?] = []
  
  enum UIAnimationState {
    case shown
    case hidden
    case willShow
    case willHide
  }
  var animationState: UIAnimationState = .shown
  
  /** For auto hiding ui after a timeout */
  var hideControlTimer: Timer?
  
  @IBOutlet weak var titleBarView: NSVisualEffectView!
  @IBOutlet weak var titleBarTitleCell: NSTextFieldCell!
  @IBOutlet weak var controlBar: ControlBarView!
  

  override func windowDidLoad() {
    super.windowDidLoad()
    guard let w = self.window else { return }
    w.titleVisibility = .hidden;
    w.styleMask.insert(NSFullSizeContentViewWindowMask);
    w.titlebarAppearsTransparent = true
    // need to deal with control bar, so handle it manually
    // w.isMovableByWindowBackground  = true
    w.title = AppData.currentURL!.lastPathComponent!
    titleBarTitleCell.title = w.title
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
    w.makeMain()
    w.makeKeyAndOrderFront(nil)
  }
  
  // MARK: Lazy initializers
  
  func initVideoView() -> VideoView {
    let v = VideoView(frame: window!.contentView!.bounds)
    return v
  }
  
  // MARK: - NSWindowDelegate
  
  override func keyDown(_ event: NSEvent) {
    playerController.togglePause(nil)
  }
  
  override func mouseDown(_ event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    mousePosRelatedToWindow = NSEvent.mouseLocation()
    mousePosRelatedToWindow!.x -= window!.frame.origin.x
    mousePosRelatedToWindow!.y -= window!.frame.origin.y
  }
  
  override func mouseDragged(_ event: NSEvent) {
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
  
  func hideUIAndCurdor() {
    hideUI()
    NSCursor.setHiddenUntilMouseMoves(true)
  }
  
  func hideUI() {
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
  
  func showUI () {
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
  
  /**
   Set video size when info available.
   */
  func adjustFrameByVideoSize(_ width: Int, _ height: Int) {
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
  }
  
}
