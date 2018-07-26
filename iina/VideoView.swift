 //
//  VideoView.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa


class VideoView: NSView {

  weak var player: PlayerCore!

  lazy var videoLayer: ViewLayer = {
    let layer = ViewLayer()
    layer.videoView = self
    return layer
  }()

  /** The mpv opengl-cb context */
  var mpvGLContext: OpaquePointer! {
    didSet {
      videoLayer.initMpvStuff()
    }
  }

  var videoSize: NSSize?

  var isUninited = false

  var uninitLock = NSLock()

  var draggingTimer: Timer?
  var triggered: Bool = false

  var lastPosition: NSPoint?

  var hasPlayableFiles: Bool = false

  // MARK: - Attributes

  override var mouseDownCanMoveWindow: Bool {
    return true
  }

  override var isOpaque: Bool {
    return true
  }

  // MARK: - Init

  override init(frame: CGRect) {

    super.init(frame: frame)

    // set up layer
    layer = videoLayer
    videoLayer.contentsScale = NSScreen.main!.backingScaleFactor
    wantsLayer = true

    // other settings
    autoresizingMask = [.width, .height]
    wantsBestResolutionOpenGLSurface = true

    // dragging init
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func uninit() {
    uninitLock.lock()
    
    guard !isUninited else {
      uninitLock.unlock()
      return
    }
    
    mpv_opengl_cb_set_update_callback(mpvGLContext, nil, nil)
    mpv_opengl_cb_uninit_gl(mpvGLContext)
    isUninited = true
    uninitLock.unlock()
  }

  deinit {
    uninit()
  }

  override func draw(_ dirtyRect: NSRect) {
    // do nothing
  }
  
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  // MARK: Drag and drop
  
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    hasPlayableFiles = (player.acceptFromPasteboard(sender, isPlaylist: true) == .copy)
    return player.acceptFromPasteboard(sender)
  }

  @objc func showPlaylist() {
    player.mainWindow.menuShowPlaylistPanel(.dummy)
    triggered = true
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let position = NSEvent.mouseLocation

    func inTriggerArea(_ point: NSPoint?) -> Bool {
      let windowFrame = player.mainWindow.window!.frame
      guard let _ = point else { return false }
      return point!.x > (windowFrame.maxX - windowFrame.width * 0.2)
    }

    func createTimer() {
      draggingTimer = Timer.scheduledTimer(timeInterval: TimeInterval(0.3), target: self,
                            selector: #selector(showPlaylist), userInfo: nil, repeats: false)
    }

    func destroyTimer() {
      if draggingTimer != nil {
        draggingTimer!.invalidate()
        draggingTimer = nil
      }
    }

    guard !triggered && hasPlayableFiles else { return super.draggingUpdated(sender) }

    if position != lastPosition {
      let nowIn = inTriggerArea(position)
      let lastIn = inTriggerArea(lastPosition)
      if nowIn && !lastIn {
        createTimer()
      } else if nowIn && lastIn {
        destroyTimer()
        createTimer()
      } else if !nowIn && lastIn {
        destroyTimer()
      }
    }
    lastPosition = position

    return super.draggingUpdated(sender)
  }
  
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return player.openFromPasteboard(sender)
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    if triggered {
      player.mainWindow.hideSideBar()
    }
    triggered = false
    lastPosition = nil
  }
  
}
