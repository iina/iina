 //
//  VideoView.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

fileprivate typealias PK = Preference.Key

class VideoView: NSView {

  lazy var playerCore = PlayerCore.shared

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
  
  var playlistAutoShowTimer = Timer()

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
    videoLayer.contentsScale = NSScreen.main()!.backingScaleFactor
    wantsLayer = true

    // other settings
    autoresizingMask = [.viewWidthSizable, .viewHeightSizable]
    wantsBestResolutionOpenGLSurface = true
  
    // dragging init
    register(forDraggedTypes: [NSFilenamesPboardType, NSURLPboardType, NSPasteboardTypeString])
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
    if playerCore.ud.bool(forKey: PK.playlistAutoShow) {
      playlistAutoShowTimer = Timer.scheduledTimer(timeInterval: TimeInterval(playerCore.ud.float(forKey: PK.playlistAutoShowTime)), target: self, selector: #selector(showPlaylist), userInfo: nil, repeats: false)
    }
    return .copy
  }

  func showPlaylist() {
    if playerCore.mainWindow?.sideBarStatus != .playlist {
      playerCore.mainWindow?.menuShowPlaylistPanel(self)
    }
    playlistAutoShowTimer.invalidate()
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    playlistAutoShowTimer.invalidate()
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pb = sender.draggingPasteboard()
    guard let types = pb.types else { return false }
    if types.contains(NSFilenamesPboardType) {
      guard let fileNames = pb.propertyList(forType: NSFilenamesPboardType) as? [String] else { return false }

      var videoFiles: [String] = []
      var subtitleFiles: [String] = []
      fileNames.forEach({ (path) in
        let ext = (path as NSString).pathExtension
        if playerCore.supportedSubtitleFormat.contains(ext) {
          subtitleFiles.append(path)
        } else {
          videoFiles.append(path)
        }
      })

      if videoFiles.count == 0 {
        if subtitleFiles.count > 0 {
          subtitleFiles.forEach { (subtitle) in
            playerCore.loadExternalSubFile(URL(fileURLWithPath: subtitle))
          }
        } else {
          return false
        }
      } else if videoFiles.count == 1 {
        playerCore.openFile(URL(fileURLWithPath: videoFiles[0]))
        subtitleFiles.forEach { (subtitle) in
          playerCore.loadExternalSubFile(URL(fileURLWithPath: subtitle))
        }
      } else {
        for path in videoFiles {
          playerCore.addToPlaylist(path)
        }
        playerCore.sendOSD(.addToPlaylist(videoFiles.count))
      }
      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
      return true
    } else if types.contains(NSURLPboardType) {
      guard let url = pb.propertyList(forType: NSURLPboardType) as? [String] else { return false }

      playerCore.openURLString(url[0])
      return true
    } else if types.contains(NSPasteboardTypeString) {
      guard let droppedString = pb.pasteboardItems![0].string(forType: "public.utf8-plain-text") else {
        return false
      }
      if Regex.urlDetect.matches(droppedString) {
        playerCore.openURLString(droppedString)
        return true
      } else {
        Utility.showAlert("unsupported_url")
        return false
      }
    }
    return false
  }

}
