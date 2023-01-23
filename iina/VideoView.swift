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

  @Atomic var isUninited = false

  var draggingTimer: Timer?

  // whether auto show playlist is triggered
  var playlistShown: Bool = false

  // variable for tracing mouse position when dragging in the view
  var lastMousePosition: NSPoint?

  var hasPlayableFiles: Bool = false

  // cached indicator to prevent unnecessary updates of DisplayLink
  var currentDisplay: UInt32?

  private var displayIdleTimer: Timer?

  lazy var hdrSubsystem = Logger.makeSubsystem("hdr")

  static let deviceRGBColorspace = CGColorSpaceCreateDeviceRGB()

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
    videoLayer.colorspace = VideoView.deviceRGBColorspace
    videoLayer.contentsScale = NSScreen.main!.backingScaleFactor
    wantsLayer = true

    // other settings
    autoresizingMask = [.width, .height]
    wantsBestResolutionOpenGLSurface = true
    wantsExtendedDynamicRangeOpenGLSurface = true

    // dragging init
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
  }

  convenience init(frame: CGRect, player: PlayerCore) {
    self.init(frame: frame)
    self.player = player
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Uninitialize this view.
  ///
  /// This method will stop drawing and free the mpv render context. This is done before sending a quit command to mpv.
  /// - Important: Once mpv has been instructed to quit accessing the mpv core can result in a crash, therefore locks must be
  ///     used to coordinate uninitializing the view so that other threads do not attempt to use the mpv core while it is shutting down.
  func uninit() {
    $isUninited.withLock() { isUninited in
      guard !isUninited else { return }
      isUninited = true

      videoLayer.suspend()
      player.mpv.mpvUninitRendering()
    }
  }

  deinit {
    uninit()
  }

  override func draw(_ dirtyRect: NSRect) {
    // do nothing
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }

  /// Workaround for issue #4183, Cursor remains visible after resuming playback with the touchpad using secondary click
  ///
  /// See `MainWindowController.workaroundCursorDefect` and the issue for details on this workaround.
  override func rightMouseDown(with event: NSEvent) {
    player.mainWindow.rightMouseDown(with: event)
    super.rightMouseDown(with: event)
  }

  /// Workaround for issue #3211, Legacy fullscreen is broken (11.0.1)
  ///
  /// Changes in Big Sur broke the legacy full screen feature. The `MainWindowController` method `legacyAnimateToWindowed`
  /// had to be changed to get this feature working again. Under Big Sur that method now calls the AppKit method
  /// `window.styleMask.insert(.titled)`. This is a part of restoring the window's style mask to the way it was before entering
  /// full screen mode. A side effect of restoring the window's title is that AppKit stops calling `MainWindowController.mouseUp`.
  /// This appears to be a defect in the Cocoa framework. See the issue for details. As a workaround the mouse up event is caught in
  /// the view which then calls the window controller's method.
  override func mouseUp(with event: NSEvent) {
    // Only check for Big Sur or greater, not if the preference use legacy full screen is enabled as
    // that can be changed while running and once the window title has been removed and added back
    // AppKit malfunctions from then on. The check for running under Big Sur or later isn't really
    // needed as it would be fine to always call the controller. The check merely makes it clear
    // that this is only needed due to macOS changes starting with Big Sur.
    if #available(macOS 11, *) {
      player.mainWindow.mouseUp(with: event)
    } else {
      super.mouseUp(with: event)
    }
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

    guard !player.isInMiniPlayer && !playlistShown && hasPlayableFiles else { return super.draggingUpdated(sender) }

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
    if link == nil {
      CVDisplayLinkCreateWithActiveCGDisplays(&link)
    }
    guard let link = link else {
      Logger.fatal("Cannot Create display link!")
    }
    guard !CVDisplayLinkIsRunning(link) else { return }
    updateDisplayLink()
    CVDisplayLinkSetOutputCallback(link, displayLinkCallback, mutableRawPointerOf(obj: self))
    CVDisplayLinkStart(link)
  }

  @objc func stopDisplayLink() {
    guard let link = link, CVDisplayLinkIsRunning(link) else { return }
    CVDisplayLinkStop(link)
  }

  // This should only be called if the window has changed displays
  func updateDisplayLink() {
    guard let window = window, let link = link, let screen = window.screen else { return }
    let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32

    // Do nothing if on the same display
    if (currentDisplay == displayId) { return }
    currentDisplay = displayId

    CVDisplayLinkSetCurrentCGDisplay(link, displayId)
    let actualData = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link)
    let nominalData = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
    var actualFps: Double = 0;

    if (nominalData.flags & Int32(CVTimeFlags.isIndefinite.rawValue)) < 1 {
      let nominalFps = Double(nominalData.timeScale) / Double(nominalData.timeValue)

      if actualData > 0 {
        actualFps = 1/actualData
      }

      if abs(actualFps - nominalFps) > 1 {
        Logger.log("Falling back to nominal display refresh rate: \(nominalFps) from \(actualFps)")
        actualFps = nominalFps;
      }
    } else {
      Logger.log("Falling back to standard display refresh rate: 60 from \(actualFps)")
      actualFps = 60;
    }
    player.mpv.setDouble(MPVOption.Video.overrideDisplayFps, actualFps)

    if #available(macOS 10.15, *) {
      refreshEdrMode()
    } else {
      setICCProfile(displayId)
    }
  }

  // MARK: - Reducing Energy Use

  /// Starts the display link if it has been stopped in order to save energy.
  func displayActive() {
    displayIdleTimer?.invalidate()
    startDisplayLink()
  }

  /// Reduces energy consumption when the display link does not need to be running.
  ///
  /// Adherence to energy efficiency best practices requires that IINA be absolutely idle when there is no reason to be performing any
  /// processing, such as when playback is paused. The [CVDisplayLink](https://developer.apple.com/documentation/corevideo/cvdisplaylink-k0k)
  /// is a high-priority thread that runs at the refresh rate of a display. If the display is not being updated it is desirable to stop the
  /// display link in order to not waste energy on needless processing.
  ///
  /// However, IINA will pause playback for short intervals when performing certain operations. In such cases it does not make sense to
  /// shutdown the display link only to have to immediately start it again. To avoid this a `Timer` is used to delay shutting down the
  /// display link. If playback becomes active again before the timer has fired then the `Timer` will be invalidated and the display link
  /// will not be shutdown.
  ///
  /// - Note: In addition to playback the display link must be running for operations such seeking, stepping and entering and leaving
  ///         full screen mode.
  func displayIdle() {
    displayIdleTimer?.invalidate()
    // The time of 3 seconds is somewhat arbitrary. As mpv does not provide an event indicating a
    // frame step has completed it must not be too short or will catch mpv still drawing when
    // stepping.
    displayIdleTimer = Timer(timeInterval: 3.0, target: self, selector: #selector(stopDisplayLink), userInfo: nil, repeats: false)
    RunLoop.current.add(displayIdleTimer!, forMode: .default)
  }

  func setICCProfile(_ displayId: UInt32) {
    if !Preference.bool(for: .loadIccProfile) {
      Logger.log("Not using ICC due to user preference", subsystem: hdrSubsystem)
      player.mpv.setString(MPVOption.GPURendererOptions.iccProfile, "")
    } else {
      Logger.log("Loading ICC profile", subsystem: hdrSubsystem)
      typealias ProfileData = (uuid: CFUUID, profileUrl: URL?)
      guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayId)?.takeRetainedValue() else { return }

      var argResult: ProfileData = (uuid, nil)
      withUnsafeMutablePointer(to: &argResult) { data in
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
        }, data)
      }

      if let iccProfilePath = argResult.profileUrl?.path, FileManager.default.fileExists(atPath: iccProfilePath) {
        player.mpv.setString(MPVOption.GPURendererOptions.iccProfile, iccProfilePath)
      }
    }

    if videoLayer.colorspace != VideoView.deviceRGBColorspace {
      Logger.log("Returning to deviceRGB color space", subsystem: hdrSubsystem)
      videoLayer.wantsExtendedDynamicRangeContent = false
      videoLayer.colorspace = VideoView.deviceRGBColorspace
      player.mpv.setString(MPVOption.GPURendererOptions.targetTrc, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.targetPrim, "auto")
    }
  }
}

// MARK: - HDR

@available(macOS 10.15, *)
extension VideoView {
  func refreshEdrMode() {
    guard player.mainWindow.loaded else { return }
    guard player.mpv.fileLoaded else { return }
    guard let displayId = currentDisplay else { return };
    if let screen = self.window?.screen {
      NSScreen.log("Refreshing HDR for \(player.subsystem.rawValue) @ display\(displayId)", screen)
    }
    let edrEnabled = requestEdrMode()
    let edrAvailable = edrEnabled != false
    if player.info.hdrAvailable != edrAvailable {
      player.mainWindow.quickSettingView.setHdrAvailability(to: edrAvailable)
    }
    if edrEnabled != true { setICCProfile(displayId) }
  }

  func requestEdrMode() -> Bool? {
    guard let mpv = player.mpv else { return false }

    guard let primaries = mpv.getString(MPVProperty.videoParamsPrimaries), let gamma = mpv.getString(MPVProperty.videoParamsGamma) else {
      Logger.log("HDR primaries and gamma not available", level: .debug, subsystem: hdrSubsystem);
      return false;
    }
  
    let peak = mpv.getDouble(MPVProperty.videoParamsSigPeak)
    Logger.log("HDR gamma=\(gamma), primaries=\(primaries), sig_peak=\(peak)", level: .debug, subsystem: hdrSubsystem)

    var name: CFString? = nil;
    switch primaries {
    case "display-p3":
      if #available(macOS 10.15.4, *) {
        name = CGColorSpace.displayP3_PQ
      } else {
        name = CGColorSpace.displayP3_PQ_EOTF
      }

    case "bt.2020":
      if #available(macOS 11.0, *) {
        name = CGColorSpace.itur_2100_PQ
      } else if #available(macOS 10.15.4, *) {
        name = CGColorSpace.itur_2020_PQ
      } else {
        name = CGColorSpace.itur_2020_PQ_EOTF
      }

    case "bt.709":
      return false; // SDR

    default:
      Logger.log("Unknown HDR color space information gamma=\(gamma) primaries=\(primaries)", level: .debug, subsystem: hdrSubsystem);
      return false;
    }

    guard (window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0) > 1.0 else {
      Logger.log("HDR video was found but the display does not support EDR mode", level: .debug, subsystem: hdrSubsystem);
      return false;
    }

    guard player.info.hdrEnabled else { return nil }

    if videoLayer.colorspace?.name == name {
      Logger.log("HDR mode already enabled, skipping", level: .debug, subsystem: hdrSubsystem);
      return true;
    }

    Logger.log("Will activate HDR color space instead of using ICC profile", level: .debug, subsystem: hdrSubsystem);

    videoLayer.wantsExtendedDynamicRangeContent = true
    videoLayer.colorspace = CGColorSpace(name: name!)
    mpv.setString(MPVOption.GPURendererOptions.iccProfile, "")
    mpv.setString(MPVOption.GPURendererOptions.targetTrc, "pq")
    mpv.setString(MPVOption.GPURendererOptions.targetPrim, primaries)
    return true;
  }
}

fileprivate func displayLinkCallback(
  _ displayLink: CVDisplayLink, _ inNow: UnsafePointer<CVTimeStamp>,
  _ inOutputTime: UnsafePointer<CVTimeStamp>,
  _ flagsIn: CVOptionFlags,
  _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
  _ context: UnsafeMutableRawPointer?) -> CVReturn {
  let videoView = unsafeBitCast(context, to: VideoView.self)
  videoView.$isUninited.withLock() { isUninited in
    guard !isUninited else { return }
    videoView.player.mpv.mpvReportSwap()
  }
  return kCVReturnSuccess
}
