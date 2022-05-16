//
//  RefreshRateMatcher.swift
//  iina
//
//  Created by low-batt on 5/4/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Cocoa

/// An object that provides the implementation for the `Match Refresh Rate` feature.
///
/// When enabled the `Match Refresh Rate` feature will attempt to synchronize the display refresh rate with the frame rate of the
/// video being played when in full screen mode.
///
/// A good reference for this feature is the mpv wiki post [Display synchronization](https://github.com/mpv-player/mpv/wiki/Display-synchronization).
/// That post covers a broader set of issues. The issue this feature addresses is discussed in the section
/// [xrandr.lua](https://github.com/mpv-player/mpv/wiki/Display-synchronization#xrandrlua), changing the rate
/// at which the display updates. That section discusses the [mpv-plugin-xrandr](https://gitlab.com/lvml/mpv-plugin-xrandr)
/// Lua script. That script performs the same function as this feature, but only supports Linux.
///
/// The frame rate of the video is based on the mpv [container-fps](https://mpv.io/manual/stable/#command-interface-container-fps)
/// property for which the mpv manual says:
///
/// **container-fps**
///
/// _Container FPS. This can easily contain bogus values. For videos that use modern container formats or video codecs, this will
/// often be incorrect._
///
/// Rather concerning, however this is the same property that is used by the [mpv-plugin-xrandr](https://gitlab.com/lvml/mpv-plugin-xrandr)
/// script.
///
/// This feature must be prepared to adjust the display mode when:
/// - Entering full screen mode
/// - Exiting full screen node
/// - Playing next video in the playlist
/// - The feature is enabled/disabled using the video menu
/// - The space the window is on becomes active/inactive
/// - The display the window is on is connected/disconnected
/// - The display joins or leaves a mirrored set
///
/// This class handles the high level aspects of the feature. The class `DisplaySynchronizer` handles finding a display mode
/// appropriate for the frame rate of the video and changing the mode of the display.
///
/// - Note: Over concerns about whether all the cases where a display could change are handled this class currently includes
///         extensive logging.
class RefreshRateMatcher: NSObject {

  // MARK: - Constants

  private let player: PlayerCore
  private let subsystem: Logger.Subsystem
  private let videoView: VideoView

  // MARK: - Variables

  /// Remember the display the window is on to be able to detect when the window moves to another screen.
  private var displayId: CGDirectDisplayID?

  /// The  `Match Refresh Rate` feature is only active when the window is in full screen mode.
  private var isInFullScreenMode = false

  private var isMatchRefreshRateEnabled: Bool {
    if #available(macOS 12, *) {
      return Preference.bool(for: .matchRefreshRate)
    }
    // This feature searches the refresh rates the display supports for a rate that matches the
    // frame rate of the video being played. Unfortunately before Monterey macOS was returning zero
    // for the refreshRate property of CGDisplayMode. Without that information this feature can not
    // function.
    return false
  }

  /// Remember whether the display is in a mirror set or not to detect when the display joins or leaves a mirror set.
  private var isMirrored = false

  /// Remember whether the window is on the currently active space to detect space changes affecting window visibility.
  private var isOnActiveSpace = true

  /// Set when an OSD message was not posted because the screen is currently animating.
  private var pendingOSD: CGDisplayMode?

  /// Set when playback was paused and needs to be resumed once the screen finishes animating.
  private var pendingResume = false

  /// Remember the video frame rate to detect if the next video has the same rate.
  private var videoFps: Double? = nil

  /// Construct a `RefreshRateMatcher` object.
  /// - Parameter player: The player for the window this object is associated with.
  /// - Parameter videoView: The view of the window this object is associated with.
  init(_ player: PlayerCore, _ videoView: VideoView) {
    // For the logger associate this object with the particular player.
    subsystem = Logger.Subsystem(rawValue: "refreshrate\(player.label!)")
    self.player = player
    self.videoView = videoView
    super.init()
    
    // Keep track of the display ID of the display the window's screen is on in order to detect when
    // the window moves to another screen.
    displayId = getDisplayId()

    // Need to know when the preference for this feature changes so the feature can be dynamically
    // turned off if there are problems with the display.
    UserDefaults.standard.addObserver(self, forKeyPath: PK.matchRefreshRate.rawValue, options: .new,
                                      context: nil)

    // Need to know when the next video in the playlist starts playing as the display may need to be
    // changed to adapt to the frame rate of the next video.
    NotificationCenter.default.addObserver(self, selector: #selector(RefreshRateMatcher.fileLoaded),
                                           name: .iinaFileLoaded, object: nil)
        
    // Need to know if the window moves to a new screen, such as when the video started playing on
    // an external monitor and that monitor was disconnected. If the feature is active the refresh
    // rate of the screen the window moved to may need to be changed. This is also need to detect
    // when the display joins or leaves a mirrored set. A more direct way of checking for these
    // changes would be to use CGDisplayRegisterReconfigurationCallback, however the Apple
    // documentation for CGDisplayReconfigurationCallBack indicates "Your callback function should
    // avoid attempting to change display configurations". Since display reconfiguration may be
    // needed we instead list for screen change notifications. The downside of this notification is
    // that macOS posts this notification for multiple reasons including when the screen moves to a
    // different GPU and when the dock hiding/revealing animation is active thus changing the
    // dimensions of the visible frame. I did not find a way to filter these notifications so the
    // screenChanged method may be called a lot.
    NotificationCenter.default.addObserver(self, selector: #selector(RefreshRateMatcher.screenChanged),
                                           name: NSApplication.didChangeScreenParametersNotification,
                                           object: nil)
    
    // Need to know when the space the window is in becomes active/inactive to appropriately set and
    // restore refresh rate changes.
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(RefreshRateMatcher.spaceChanged),
      name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
  }

  deinit {
    UserDefaults.standard.removeObserver(self, forKeyPath: PK.matchRefreshRate.rawValue)
  }

  /// Complete any pending operations.
  ///
  /// A user will have a very hard time reading an OSD message that is posted when the screen is animating while entering or exiting
  /// full screen mode. For this reason the OSD is not posted until the transition to or from full screen mode is completed.
  ///
  /// Playback must be paused while changing the display's refresh rate to avoid audio/video desynchronization. Resuming during the
  /// transition to and from full screen mode triggered desynchronization. For this reason playback is not resumed until the transition to
  /// or from full screen mode is completed.
  private func completePendingOperations() {
    if let displayMode = pendingOSD {
      sendOSD(displayMode, false)
      pendingOSD = nil
    }
    resumePlayback()
  }

  /// Listener for `fileLoaded` notifications.
  ///
  /// The display refresh rate may need to be updated if the fps of the video was not available when the window transitioned to full
  /// screen mode or if this notification is due to starting to play the next video in the playlist and that video has a different frame rate.
  @objc private func fileLoaded() {
    // This notification is called from a background thread. Must queue the work to the main thread.
    DispatchQueue.main.async { [self] in
      // Only need to take action if the feature is enabled and the window is in full screen mode.
      guard isMatchRefreshRateEnabled, isInFullScreenMode else { return }
      log("Notified file loaded")

      // If the current fps matches the saved fps then the display is already set appropriately.
      let currentVideoFps = getVideoFps()
      guard currentVideoFps != videoFps else { return }
      videoFps = currentVideoFps
      guard videoFps != nil else {
        // Must have loaded the next video in a playlist and the frame rate for this video can not
        // be determined. If the display was changed for the previous video then restore the display
        // to the original refresh rate. OSD messages must be delayed to avoid colliding with the
        // OSD file loading message.
        restoreRefreshRate(delayOSD: true)
        return
      }

      // The video frame rate is known and differs from the remembered rate. The usual case is that
      // the next video in a playlist was just loaded. It could also be that the window went into
      // full screen mode while the video was still loading so the video frame rate was not
      // available at that time. Try and match the video's frame rate. OSD messages must be delayed
      // to avoid colliding with the OSD file loading message.
      let displayMode = matchRefreshRate(delayOSD: true)
      if displayMode == nil {
        // No matching refresh rate found, if the display was changed for the previous video then
        // restore the display to the original refresh rate.
        restoreRefreshRate(delayOSD: true)
      }
    }
  }

  /// Return the ID of the display the window is on.
  /// - Returns: The `CGDirectDisplayID` of the display the window is on or `nil` if not available.
  private func getDisplayId() -> CGDirectDisplayID? {
    guard let window = videoView.window, let screen = window.screen else { return nil }
    return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID)
  }

  /// Return the frame rate of the current video.
  /// - Returns: The fps of the video or `nil` if not available.
  private func getVideoFps() -> Double? {
    let containerFps = player.mpv.getDouble(MPVProperty.containerFps)
    guard containerFps == 0.0 else { return containerFps }
    log("Video frame rate can not be determined")
    return nil
  }

  /// Log message using this feature's log `subsystem`.
  private func log(_ message: String) {
    Logger.log(message, subsystem: subsystem)
  }

  /// Try and find a display mode with a refresh rate appropriate for the current video and if one is found ensure the display is set to
  /// that mode.
  ///
  /// The caller must be able to specify whether playback should be resumed and whether an OSD message should be displayed as
  /// these actions may need to be postponed or suppressed depending upon the current circumstances.
  /// - Parameters:
  ///   - delayResume: If `true` playback will not be resumed if it needed to be paused.
  ///   - noOSD: If `true` do not post an OSD message.
  ///   - delayOSD: If `true` delay displaying this OSD message otherwise display immediately.
  /// - Returns: The `CGDisplayMode` the matching display mode or `nil` if a suitable display mode was not found.
  @discardableResult
  private func matchRefreshRate(delayResume: Bool = false, noOSD: Bool = false, delayOSD: Bool = false) -> CGDisplayMode? {
    guard let displayId = getDisplayId(), let videoFps = videoFps else { return nil }
    let displaySynchronizer = DisplaySynchronizer.getDisplaySynchronizer(displayId)
    isMirrored = displaySynchronizer.isMirrored
    guard !isMirrored else {
      log("Display is mirrored, will not attempt to match refresh rate")
      return nil
    }
    guard let displayMode = displaySynchronizer.findMatchingDisplayMode(videoFps) else {
      // A suitable display mode was not found.
      return nil
    }
    // Check if the display is already configured with the desirable mode.
    guard !displaySynchronizer.isCurrentDisplayMode(displayMode) else { return displayMode }
    setDisplayMode(displaySynchronizer, displayMode, delayResume, isRestore: false)
    player.mpv.setDouble(MPVOption.Video.overrideDisplayFps, displayMode.refreshRate)
    guard !noOSD else {
      // The OSD message will either be displayed later, or cancelled.
      pendingOSD = displayMode
      return displayMode
    }
    sendOSD(displayMode, delayOSD)
    return displayMode
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                             context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let change = change else { return }
    switch keyPath {
    case PK.matchRefreshRate.rawValue:
      if let newValue = change[.newKey] as? Bool {
        preferenceChanged(isMatchRefreshRateEnabled: newValue)
      }
    default:
      return
    }
  }

  /// Listener for changes to the preference controlling this feature.
  /// - Parameter isMatchRefreshRateEnabled: Whether the feature is enabled or not.
  private func preferenceChanged(isMatchRefreshRateEnabled: Bool) {
    // Nothing needs to be done unless the window is currently in full screen mode.
    guard isInFullScreenMode else { return }
    guard isMatchRefreshRateEnabled else {
      log("Match refresh rate disabled")
      restoreRefreshRate()
      return
    }
    log("Match refresh rate enabled")
    displayId = getDisplayId()
    guard let displayId = displayId  else { return }
    let displaySynchronizer = DisplaySynchronizer.getDisplaySynchronizer(displayId)
    isMirrored = displaySynchronizer.isMirrored
    videoFps = getVideoFps()
    guard videoFps != nil else { return }
    matchRefreshRate()
  }

  /// If the refresh rate of the display was changed then this method will restore the display to its original refresh rate.
  ///
  /// The caller must be able to specify whether playback should be resumed and whether an OSD message should be displayed as
  /// these actions may need to be postponed or suppressed depending upon the circumstances.
  /// - Parameters:
  ///   - delayResume: If `true` playback will not be resumed if it needed to be paused.
  ///   - noOSD: If `true` do not post an OSD message.
  ///   - delayOSD: If `true` delay displaying this OSD message otherwise display immediately.
  private func restoreRefreshRate(delayResume: Bool = false, noOSD: Bool = false, delayOSD: Bool = false) {
    guard let displayId = displayId else { return }
    let displaySynchronizer = DisplaySynchronizer.getDisplaySynchronizer(displayId)
    // The display mode saved in the synchronizer will be nil if the display's refresh rate was not
    // changed does not need to be restored.
    guard let displayMode = displaySynchronizer.displayModeForRestore else { return }
    setDisplayMode(displaySynchronizer, displayMode, delayResume, isRestore: true)
    player.mpv.setDouble(MPVOption.Video.overrideDisplayFps, displayMode.refreshRate)
    displaySynchronizer.displayModeForRestore = nil
    guard !noOSD else {
      // The OSD message will either be displayed later, or cancelled.
      pendingOSD = displayMode
      return
    }
    sendOSD(displayMode, delayOSD)
    return
  }

  private func resumePlayback() {
    guard pendingResume else { return }
    log("Resuming playback after changing display refresh rate")
    player.resume(internalPauseResume: true)
    pendingResume = false
  }
  
  /// Listener for changes to screens.
  ///
  /// May need to adjust the refresh rate if the window moved to a different display, or the display joined or left a mirrored set.
  @objc private func screenChanged() {
    // Only need to take action if the feature is enabled and the window is in full screen mode.
    guard isMatchRefreshRateEnabled, isInFullScreenMode, let currentDisplayId = getDisplayId() else { return }
    if currentDisplayId != displayId {
      // Since the window was in full screen mode it only changes screens when the display it was on
      // was disconnected. That will reset the display mode, so clear any saved mode to avoid
      // needlessly setting the display mode if this screen is connected again.
      if let displayId = displayId {
        let displaySynchronizer = DisplaySynchronizer.getDisplaySynchronizer(displayId)
        displaySynchronizer.displayModeForRestore = nil
      }
      displayId = currentDisplayId
      guard let displayId = displayId else { return }
      log("Window moved to display \(displayId)")
      let displaySynchronizer = DisplaySynchronizer.getDisplaySynchronizer(displayId)
      // Keep track of the mirrored state of this new display.
      isMirrored = displaySynchronizer.isMirrored
      // Attempt to adjust the refresh rate of the screen the window is now on.
      matchRefreshRate()
      return
    }
    // The window is still on the same display. Check if the mirror state has changed.
    guard let displayId = displayId else { return }
    let displaySynchronizer = DisplaySynchronizer.getDisplaySynchronizer(displayId)
    let currentMirrorState = displaySynchronizer.isMirrored
    guard currentMirrorState != isMirrored else { return }
    
    // The display either joined or left a mirrored set.
    isMirrored = currentMirrorState
    guard isMirrored else {
      log("Display is no longer mirrored, will attempt to match refresh rate")
      matchRefreshRate()
      return
    }
    log("Display is now mirrored, will not attempt to match refresh rate")
    restoreRefreshRate()
  }

  /// Display an OSD message.
  ///
  /// If the display's refresh rate is being changed when moving to the next video in the playlist then OSD messages need to be delayed
  /// to avoid colliding with the file loaded OSD message.
  /// - Parameter delayOSD: If `true` delay displaying this OSD message otherwise display immediately.
  private func sendOSD(_ displayMode: CGDisplayMode, _ delayOSD: Bool) {
    guard delayOSD else {
      player.sendOSD(.displayMode("\(displayMode.shortDescription)"))
      return
    }
    let osdTimeout = Int(Preference.float(for: .osdAutoHideTimeout).rounded(.up))
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(osdTimeout)) {
      self.player.sendOSD(.displayMode("\(displayMode.shortDescription)"))
    }
  }

  /// Set the display mode of the display to the given mode.
  /// - Parameters:
  ///   - displaySynchronizer: The `DisplaySynchronizer` for the display.
  ///   - displayMode: The `CGDisplayMode` to set the display to.
  ///   - delayResume: If `true` playback will not be resumed if it needed to be paused.
  ///   - isRestore: If `true` the mode is being set to restore the display to its original refresh rate.
  private func setDisplayMode(_ displaySynchronizer: DisplaySynchronizer, _ displayMode: CGDisplayMode,
                              _ delayResume: Bool, isRestore: Bool) {
    if !player.info.isPaused {
      log("Pausing playback to avoid audio/video desynchronization")
      player.pause(internalPauseResume: true)
      pendingResume = true
    }
    displaySynchronizer.setDisplayMode(displayMode: displayMode, isRestore: isRestore)
    guard pendingResume, !delayResume else { return }
    resumePlayback()
  }

  /// Listener for changes to spaces.
  ///
  /// If the space the window is in becomes active or inactive the display's refresh rate may need to be updated.
  @objc private func spaceChanged() {
    // Only need to take action if the feature is enabled, the window is in full screen mode and
    // this change altered the status of the space the window is in.
    guard isMatchRefreshRateEnabled, isInFullScreenMode, let window = videoView.window,
          window.isOnActiveSpace != isOnActiveSpace else { return }
    isOnActiveSpace = window.isOnActiveSpace
    guard isOnActiveSpace else {
      log("Space window is in became inactive")
      // The space the window is on is not visible, so no reason to display an OSD message.
      restoreRefreshRate(noOSD: true)
      pendingOSD = nil
      return
    }
    log("Space window is in became active")
    matchRefreshRate()
  }

  /// Inform the `Match Refresh Rate` feature that the window entered full screen mode.
  ///
  /// Complete any operations that were waiting for animations to finish.
  func windowDidEnterFullScreen() {
    guard isMatchRefreshRateEnabled else { return }
    completePendingOperations()
  }

  /// Inform the `Match Refresh Rate` feature that the window exited full screen mode.
  ///
  /// Complete any operations that were waiting for animations to finish.
  func windowDidExitFullScreen() {
    guard isMatchRefreshRateEnabled else { return }
    completePendingOperations()
    isInFullScreenMode = false
  }

  /// Inform the `Match Refresh Rate` feature that the window is entering full screen mode.
  ///
  /// The `Match Refresh Rate` feature only takes effect when the window is in full screen mode. This method will search for a
  /// matching refresh rate on the display and if one is found then change the display's refresh rate.
  func windowWillEnterFullScreen() {
    isInFullScreenMode = true
    guard isMatchRefreshRateEnabled else { return }
    log("Entering full screen mode")
    videoFps = getVideoFps()
    guard videoFps != nil else {
      // If in Preferences/General section under "When media is opened" the "Enter fullscreen"
      // preference is enabled, then the window may go into full screen mode before mpv has been
      // able to determine the video fps. That is one example of why the video fps may not be
      // available. If that happens we will attempt to get the frame rate again when notified the
      // file has loaded.
      return
    }
    // Must postpone resuming playback and showing OSD messages until animations finish.
    matchRefreshRate(delayResume: true, noOSD: true)
  }

  /// Inform the `Match Refresh Rate` feature that the window is exiting full screen mode.
  ///
  /// The `Match Refresh Rate` feature only takes effect when the window is in full screen mode. This method will restore the
  /// display's refresh rate if it was changed to match the video.
  func windowWillExitFullScreen() {
    guard isMatchRefreshRateEnabled else { return }
    log("Exiting full screen mode")

    // Must postpone resuming playback and showing OSD messages until animations finish.
    restoreRefreshRate(delayResume: true, noOSD: true)
  }
}
