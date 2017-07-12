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
    registerForDraggedTypes([NSFilenamesPboardType, NSURLPboardType, .string])
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
    return player.acceptFromPasteboard(sender)
  }
  
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return player.openFromPasteboard(sender)
  }
  
}
