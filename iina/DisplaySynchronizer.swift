//
//  DisplaySynchronizer.swift
//  iina
//
//  Created by low-batt on 5/4/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/// An object that supports synchronization of a display's refresh rate with the frame rate of a video.
///
/// This is one part of the implementation for the `Match Refresh Rate` feature. A `DisplaySynchronizer` object manages
/// refresh rate synchronization for a specific display. Higher level aspects are managed by the class `RefreshRateMatcher`.
///
/// - Note: In anticipation of questions from users regarding why this feature did or didn't change the display's refresh rate this class
///         includes extensive logging.
class DisplaySynchronizer {

  // MARK: - Static Properties and Methods

  private static var displays: [CGDirectDisplayID: DisplaySynchronizer] = [:]

  /// Returns a string containing the given display modes suitable for including in a log message.
  private static func displayModesForLog(_ displayModes: [CGDisplayMode]) -> String {
    displayModes.reduce("", { result, displayMode in
      result + "\n  " + displayMode.shortDescription
    })
  }

  /// Find the screen associated with this display.
  /// - Parameter displayId: ID of the display to return the screen for.
  /// - Returns: The `NSScreen` for the given display or `nil` if the screen could not be found
  private static func findScreen(_ displayId: CGDirectDisplayID) -> NSScreen? {
    let key: NSDeviceDescriptionKey = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
    return NSScreen.screens.first(where: {
      guard let deviceId = $0.deviceDescription[key] as? NSNumber else { return false }
      return deviceId.uint32Value == displayId
    })
  }

  /// Return the `DisplaySynchronizer` for the given display.
  ///
  /// If a `DisplaySynchronizer` does not exist for the given display, one will be constructed.
  /// - Parameter displayId: ID of the display to return a synchronizer for.
  /// - Returns: `DisplaySynchronizer` for the display with the given ID
  static func getDisplaySynchronizer(_ displayId: CGDirectDisplayID) -> DisplaySynchronizer {
    if let display = displays[displayId] {
      return display
    }
    let display = DisplaySynchronizer(displayId)
    displays[displayId] = display
    return display
  }

  /// Get the localized name for the given display.
  ///
  /// As the `localizedName` property was added to `NSScreen` in macOS Catalina the name of the screen will not be available
  /// when running on older versions of macOS.
  /// - Parameter displayId: ID of the display to return the localized name of..
  /// - Returns: A localized name describing the display or `nil` if a name could not be obtained.
  private static func getLocalizedName(_ displayId: CGDirectDisplayID) -> String? {
    if #available(macOS 10.15, *) {
      return findScreen(displayId)?.localizedName
    }
    return nil
  }

  // MARK: - Constants

  private let displayId: CGDirectDisplayID

  /// Native modes supported by the display.
  private let displayModes: [CGDisplayMode]

  /// `true` if the display did not report any native resolutions.
  private let foundNativeDisplayModes: Bool

  /// A localized name describing this display or `nil` if a name could not be obtained.
  ///
  /// As the `localizedName` property was added to `NSScreen` in macOS Catalina the name of the screen will not be available
  /// when running on older versions of macOS.
  private let localizedName: String?

  private let subsystem: Logger.Subsystem

  // MARK: - Variables

  /// The display mode the display is currently set to.
  ///
  /// This property will be `nil` if the display is invalid.
  private var currentDisplayMode: CGDisplayMode? {
    guard let currentDisplayMode = CGDisplayCopyDisplayMode(displayId) else {
      log("Unable to obtain current display mode", level: .error)
      return nil
    }
    return currentDisplayMode
  }

  /// The mode the display was in before the refresh rate was adjusted by this feature. Will be `nil` when the display is not currently
  /// adjusted.
  var displayModeForRestore: CGDisplayMode?

  /// `true` of this display belongs to a mirrored set.
  var isMirrored: Bool { (CGDisplayIsInMirrorSet(displayId) != 0) }

  /// Construct a display synchronizer for the given display.
  /// - Attention: Call the method `getDisplaySynchronizer` to obtain a `DisplaySynchronizer` object for a display.
  /// - Parameter displayId: ID of the display to be synchronized.
  private init(_ displayId: CGDirectDisplayID) {
    self.displayId = displayId
    subsystem = Logger.Subsystem(rawValue: "display\(displayId)")

    // Obtain all the available modes on the display and filter out all except the native modes.
    let allDisplayModes = CGDisplayCopyAllDisplayModes(displayId, nil) as! [CGDisplayMode]
    var nativeDisplayModes = allDisplayModes
    nativeDisplayModes.removeAll(where: { !$0.isNative })
    var usableDisplayModes = nativeDisplayModes
    usableDisplayModes.removeAll(where: { $0.refreshRate == 0 })
    displayModes = usableDisplayModes
    foundNativeDisplayModes = !nativeDisplayModes.isEmpty

    // Try and obtain the name of the display (not available in older versions of macOS).
    localizedName = DisplaySynchronizer.getLocalizedName(displayId)

    // Log details about the display in case this particular display proves problematic.
    log("Display vendor: \(CGDisplayVendorNumber(displayId)) model: \(CGDisplayModelNumber(displayId))")
 
    let description = localizedName == nil ? "" : " on \(localizedName!)"
    guard foundNativeDisplayModes else {
      // Posts on the Internet indicated some displays do not properly report their display modes.
      // Posts on the net indicate some displays may fail to set this flag. The iMac 5K 2017
      // built-in display was given as an example of such problematic displays. If this happens log
      // all the display modes. This means the feature will never find a matching display refresh
      // rate.
      log("No native display modes found\(description):\(DisplaySynchronizer.displayModesForLog(allDisplayModes))",
          level: .warning)
      return
    }
    guard !displayModes.isEmpty else {
      // Older macOS versions always report 0 for the refresh rate. Not sure if this will be
      // encountered under macOS 12 and later. Included this check just in case. This means the
      // feature will never find a matching display refresh rate.
      log("This Mac does not provide display refresh rates\(description):\(DisplaySynchronizer.displayModesForLog(nativeDisplayModes))",
          level: .warning)
      return
    }
    log("Available native display modes\(description):\(DisplaySynchronizer.displayModesForLog(displayModes))")
  }

  /// Find a display mode that matches one of the specified refresh rates.
  /// - Parameter refreshRates: List of acceptable refresh rates.
  /// - Returns: `CGDisplayMode` to set the display to or `nil` of no matching display mode was found.
  private func findMatch(_ refreshRates: [Double]) -> CGDisplayMode? {
   for refreshRate in refreshRates {
      if let matched = displayModes.first(where: { abs($0.refreshRate.distance(to: refreshRate)) < 0.02 }) {
        return matched
      }
    }
    return nil
  }

  /// Find a matching display mode for the given video frame rate.
  /// - Parameter refreshRate: The frame rate of the video.
  /// - Returns: The matching display mode or `nil` if no match was found.
  func findMatchingDisplayMode(_ videoFps: Double) -> CGDisplayMode? {
    guard haveUsableDisplayModes() else { return nil }
    // [23.976, 47.952, 24, 48], [29.97, 59.94, 30, 60]
    // [24, 48], [25, 50], [30, 60]
    var refreshRates = [videoFps, videoFps * 2]
    let rounded = videoFps.rounded()
    if videoFps != rounded {
      refreshRates.append(rounded)
      refreshRates.append(rounded * 2)
    }
    log("Video frame rate: \(rateFormatter.string(for: videoFps))")
    guard let displayMode = findMatch(refreshRates) else {
      log("No suitable display refresh rate found")
      return nil
    }
    log("Best display refresh rate: \(displayMode.shortDescription)")
    return displayMode
  }

  private func haveUsableDisplayModes() -> Bool {
    guard foundNativeDisplayModes else {
      // Posts on the Internet indicated some displays do not properly report their display modes.
      log("No native display modes found, unable to search for a matching refresh rate", level: .warning)
      return false
    }
    guard !displayModes.isEmpty else {
      // Older macOS versions report 0 for the refresh rate. Not expecting this under macOS 12+, but
      // including the check to be sure.
      log("This Mac does not provide display refresh rates, unable to search for a matching refresh rate",
          level: .warning)
      return false
    }
    return true
  }

  /// Check to see if the display is set to the given mode.
  /// - Parameter displayMode: The `CGDisplayMode` to check for.
  /// - Returns: `true` if the display is set to the given mode, `false` otherwise.
  func isCurrentDisplayMode(_ displayMode: CGDisplayMode) -> Bool {
    guard let currentDisplayMode = currentDisplayMode else { return false }
    guard currentDisplayMode.ioDisplayModeID == displayMode.ioDisplayModeID else { return false }
    log("Display is already set to the best refresh rate for this video")
    return true
  }

  /// Log message using this feature's log `subsystem`.
  private func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: subsystem)
  }

  /// Set the display mode of the display.
  /// - Parameter displayMode: Display mode to set the display to.
  /// - Parameter isRestore: If `true` the mode is being set to restore the original display mode.
  func setDisplayMode(displayMode: CGDisplayMode, isRestore: Bool = false) {
    guard let currentDisplayMode = currentDisplayMode else {
      log("Could not obtain current display mode")
      return
    }
    if displayModeForRestore == nil {
      displayModeForRestore = currentDisplayMode
      log("Saved original display refresh rate: \(displayModeForRestore!.shortDescription)")
    }
    log("\(isRestore ? "Restoring original" : "Setting") display refresh rate\(isRestore ? "" : " to"): \(displayMode.shortDescription)")
    CGDisplaySetDisplayMode(displayId, displayMode, nil).mustSucceed(#fileID, #line, "CGDisplaySetDisplayMode")
  }
}

// MARK: - Rate Formatter

fileprivate let rateFormatter = RateFormatter()

/// A formatter for formatting refresh rates in log messages.
///
/// The primary reason for this formatter is to avoid logging floating point numbers with a large number of fractional digits making log
/// messages hard to read.
private class RateFormatter: NumberFormatter {

  override init() {
    super.init()
    maximumFractionDigits = 3
    numberStyle = .decimal
    roundingMode = .down
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func string(for rate: Double) -> String {
    super.string(for: rate)! + " Hz"
  }
}

// MARK: - Extensions

extension CGDisplayMode {
  /// Returns `true` if this is a native display mode.
  /// - Important: Posts on the net indicate some displays may fail to set this flag. The iMac 5K 2017 built-in display was given as
  ///               an example of such problematic displays.
  /// - Returns: `true` if the flag `kDisplayModeNativeFlag` is set in `ioFlags`.
  var isNative: Bool { ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }

  /// A very short description of this display mode appropriate for displaying in the OSD and log file.
  var shortDescription: String { "\(width)x\(height) @ \(rateFormatter.string(for: refreshRate))" }
}

extension CGError {
  /// Validate that this Core Graphics result code indicates the operation was completed successfully.
  ///
  /// If this return code indicates the operation failed then this is deemed a fatal internal error and this method will:
  /// - Log an error message.
  /// - Show the user an alert.
  /// - Terminate the application when the user dismisses the alert.
  /// - Parameter fileID: The name of the file and module in which the operation was invoked.
  /// - Parameter line: The line number on which the method was called.
  /// - Parameter method: The name of the method that returned the result code.
  func mustSucceed(_ fileID: String, _ line: Int, _ method: String) {
    guard self != .success else { return }
    DispatchQueue.main.async {
      Logger.fatal("\(fileID):\(line) \(method) fatal: \(self)")
    }
  }
}
