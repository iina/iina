//
//  MainWindow.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MainWindow: NSWindowController, NSWindowDelegate {
  
  var selfWindow: NSWindow!
  var playerController: PlayerController!
  lazy var videoView: VideoView! = self.initVideoView()
  
  var mousePosRelatedToWindow: CGPoint?
  var isDragging: Bool = false
  
  @IBOutlet weak var btn: NSButton!
  
  override var windowNibName: String {
    return "MainWindow"
  }
  
  var fadeableViews: [NSView?] = []
  var stopAnimation: Bool = false
  
  @IBOutlet weak var titleBarView: NSVisualEffectView!
  @IBOutlet weak var titleBarTitleCell: NSTextFieldCell!
  @IBOutlet weak var controlBar: ControlBarView!
  

  override func windowDidLoad() {
    super.windowDidLoad()
    let w = self.window!
    selfWindow = self.window!
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
    let cv = window!.contentView!
    cv.addTrackingArea(NSTrackingArea(rect: cv.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))
    // video view
    w.contentView?.addSubview(videoView, positioned: .below, relativeTo: nil)
    playerController.startMPVOpenGLCB(videoView)
    w.makeMain()
    w.makeKeyAndOrderFront(nil)
  }
  
  // MARK: Lazy initializers
  
  func initVideoView() -> VideoView {
    let v = VideoView(frame: selfWindow.contentView!.bounds)
    return v
  }
  
  // MARK: - NSWindowDelegate
  
  func windowDidEndLiveResize(_ notification: Notification) {
    window!.setFrame(window!.constrainFrameRect(window!.frame, to: window!.screen), display: false)
  }
  
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
    stopAnimation = true
    fadeableViews.forEach { (v) in
      v?.isHidden = false
      v?.alphaValue = 0
    }
    NSAnimationContext.runAnimationGroup({ (context) in
        context.duration = 0.5
      fadeableViews.forEach { (v) in
        v?.animator().alphaValue = 1
      }
      }) {}
  }
  
  override func mouseExited(_ event: NSEvent) {
    if controlBar.isDragging {
      return
    }
    fadeableViews.forEach { (v) in
      v?.alphaValue = 1
    }
    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = 0.5
      fadeableViews.forEach { (v) in
        v?.animator().alphaValue = 0
      }
    }) {
      if !self.stopAnimation {
        self.fadeableViews.forEach { (v) in
          v?.isHidden = true
        }
      }
    }
  }
  
  /**
   Set video size when info available.
   */
  func adjustFrameByVideoSize(_ width: Int, _ height: Int) {
    let screenSizeOptional = NSScreen.main()?.visibleFrame.size
    let aspectRatio = Float(width) / Float(height)
    var videoSize = NSSize(width: width, height: height)
    self.window!.aspectRatio = videoSize
    // check if video size > screen size
    if let screenSize = screenSizeOptional {
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
    }
    self.window!.setContentSize(videoSize)
    if self.videoView.videoSize == nil {
      self.videoView.videoSize = videoSize
    }
  }
  
}
