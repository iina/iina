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
  var link: CVDisplayLink?

  lazy var videoLayer: ViewLayer = {
    let layer = ViewLayer()
    layer.videoView = self
    return layer
  }()

  var videoSize: NSSize?

  var isUninited = false
  var uninitLock = NSLock()

  var draggingTimer: Timer?

  // whether auto show playlist is triggered
  var playlistShown: Bool = false

  // variable for tracing mouse position when dragging in the view
  var lastMousePosition: NSPoint?

  var hasPlayableFiles: Bool = false
  
  // cached indicator to prevent unnecessary updates of DisplayLink
  var currentDisplay: UInt32?

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

    player.mpv.mpvUninitRendering()
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
    playlistShown = true
  }

  private func createTimer() {
    draggingTimer = Timer.scheduledTimer(timeInterval: TimeInterval(0.3), target: self,
                                         selector: #selector(showPlaylist), userInfo: nil, repeats: false)
  }

  private func destroyTimer() {
    if let draggingTimer = draggingTimer {
      draggingTimer.invalidate()
    }
    draggingTimer = nil
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {

    guard !playlistShown && hasPlayableFiles else { return super.draggingUpdated(sender) }

    func inTriggerArea(_ point: NSPoint?) -> Bool {
      guard let point = point, let frame = player.mainWindow.window?.frame else { return false }
      return point.x > (frame.maxX - frame.width * 0.2)
    }

    let position = NSEvent.mouseLocation

    if position != lastMousePosition {
      if inTriggerArea(lastMousePosition) {
        destroyTimer()
      }
      if inTriggerArea(position) {
        createTimer()
      }
      lastMousePosition = position
    }

    return super.draggingUpdated(sender)
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    destroyTimer()
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return player.openFromPasteboard(sender)
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    if playlistShown {
      player.mainWindow.hideSideBar()
    }
    playlistShown = false
    lastMousePosition = nil
  }

  // MARK: Display link

  func startDisplayLink() {
    CVDisplayLinkCreateWithActiveCGDisplays(&link)
    guard let link = link else {
      Logger.fatal("Cannot Create display link!")
    }
    updateDisplaylink()
    CVDisplayLinkSetOutputCallback(link, displayLinkCallback, mutableRawPointerOf(obj: player.mpv))
    CVDisplayLinkStart(link)
  }

  func stopDisplaylink() {
    guard let link = link, CVDisplayLinkIsRunning(link) else { return }
    CVDisplayLinkStop(link)
  }

  func updateDisplaylink() {
    guard let window = window, let link = link else { return }
    let displayId = window.screen!.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
    if (currentDisplay == displayId) {
      return
    }
    
    CVDisplayLinkSetCurrentCGDisplay(link, displayId)
    if let refreshRate = CGDisplayCopyDisplayMode(displayId)?.refreshRate {
      player.mpv.setDouble(MPVOption.Video.displayFps, refreshRate)
    }
    setICCProfile(displayId)
    currentDisplay = displayId
  }
  
  func setICCProfile(_ displayId: UInt32) {
    typealias ProfileData = (uuid: CFUUID, profileUrl: URL?)

    let uuid = CGDisplayCreateUUIDFromDisplayID(displayId).takeRetainedValue()
    var argResult: ProfileData = (uuid, nil)
    let dataPointer = UnsafeMutablePointer(&argResult)
    
    ColorSyncIterateDeviceProfiles({ (dict: CFDictionary?, ptr: UnsafeMutableRawPointer?) -> Bool in
      if let info = dict as? [String: Any], let current = info["DeviceProfileIsCurrent"] as? Int {
        let deviceID = info["DeviceID"] as! CFUUID
        let ptr = ptr!.bindMemory(to: ProfileData.self, capacity: 1)
        let uuid = ptr.pointee.uuid
        
        if current == 1, deviceID == uuid {
          let profileURL = info["DeviceProfileURL"] as! URL
          ptr.pointee.profileUrl = profileURL
          return false
        }
      }
      return true
    }, dataPointer)
    
    if let iccProfilePath = argResult.profileUrl?.path, FileManager.default.fileExists(atPath: iccProfilePath) {
      player.mpv.setString(MPVOption.GPURendererOptions.iccProfile, iccProfilePath)
    }
  }
}

fileprivate func displayLinkCallback(
  _ displayLink: CVDisplayLink, _ inNow: UnsafePointer<CVTimeStamp>,
  _ inOutputTime: UnsafePointer<CVTimeStamp>,
  _ flagsIn: CVOptionFlags,
  _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
  _ context: UnsafeMutableRawPointer?) -> CVReturn {
  let mpv = unsafeBitCast(context, to: MPVController.self)
  mpv.mpvReportSwap()
  return kCVReturnSuccess
}

