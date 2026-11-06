//
//  Display.swift
//  iina
//
//  Created by low-batt on 9/28/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

fileprivate let rateFormatter = RateFormatter()

/// A display discovered using
/// [CGGetActiveDisplayList](https://developer.apple.com/documentation/coregraphics/cggetactivedisplaylist(_:_:_:)).
struct Display: CustomStringConvertible {

  /// A description of this display suitable to include in a log message.
  var description: String {
    var description = "Display \(displayId)"
    var attributes: [String] = []
    if isBuiltin {
      attributes.append("builtin")
    }
    if isVirtual {
      attributes.append("virtual")
    }
    if CGDisplayIsMain(displayId) != 0 {
      attributes.append("main")
    }
    if CGDisplayIsInMirrorSet(displayId) != 0 {
      attributes.append("in mirror set")
    }
    if CGDisplayIsOnline(displayId) != 0 {
      attributes.append("online")
    }
    if CGDisplayIsAsleep(displayId) != 0 {
      attributes.append("asleep")
    }
    if !attributes.isEmpty {
      description += " (\(attributes.joined(separator: ", ")))"
    }
    description += ":"
    if let productName {
      description += "\n  Product name: \(productName)"
    }
    description += "\n  Model: "
    if modelNumber == kDisplayProductIDGeneric {
      description += "generic"
    } else if modelNumber == 0xFFFFFFFF {
      description += "no monitor associated with display"
    } else {
      description += "\(modelNumber)"
    }
    description += "\n  Vendor: "
    if vendorNumber == kDisplayVendorIDUnknown {
      description += "unknown"
    } else if vendorNumber == 0xFFFFFFFF {
      description += "no monitor associated with display"
    } else {
      description += "\(vendorNumber)"
    }
    description += "\n  Bounds: \(CGDisplayBounds(displayId))"
    if let displayBacklight {
      description += "\n  Display luminance: \(displayBacklight) nits"
    }
    if let nonReferencePeakHDRLuminance, let nonReferencePeakSDRLuminance {
      description += """
        \n  Peak non-reference luminance: HDR \(nonReferencePeakHDRLuminance) nits, \
        SDR \(nonReferencePeakSDRLuminance) nits
        """
    }
    if let referencePeakHDRLuminance, let referencePeakSDRLuminance {
      description += """
        \n  Peak reference luminance: HDR \(referencePeakHDRLuminance) nits, \
        SDR \(referencePeakSDRLuminance) nits
        """
    }
    if let mode = CGDisplayCopyDisplayMode(displayId) {
      description += "\n  Mode: \(mode.shortDescription)"
    }
    if let modes = displayModes?.reduce("", { result, displayMode in
      result + "\n    " + displayMode.shortDescription }) {
      description += "\n  Native modes:"
      description += modes
    }
    return description
  }

  // Luminance of non-XDR displays.
  let displayBacklight: Int?

  let displayId: CGDirectDisplayID

  /// Native modes supported by the display.
  /// - Note: When waking up, macOS may return a virtual display that does not report any native modes or the modes may be
  ///         missing because macOS was still in the process of querying the display for information.
  let displayModes: [CGDisplayMode]?

  /// Whether the display is built-in, such as the internal display in portable systems.
  let isBuiltin: Bool

  /// Whether the display is a virtual device.
  let isVirtual: Bool

  /// The model number of the display's monitor.
  let modelNumber: UInt32

  /// XDR display luminance.
  let nonReferencePeakHDRLuminance: Int?
  let nonReferencePeakSDRLuminance: Int?

  /// Product name of the display in English..
  let productName: String?

  /// XDR display luminance.
  let referencePeakHDRLuminance: Int?
  let referencePeakSDRLuminance: Int?

  /// The vendor number of the display’s monitor.
  let vendorNumber: UInt32

  /// Create a `Display` object for the display with the given ID.
  /// - Parameter displayId: The
  ///     [CGDirectDisplayID](https://developer.apple.com/documentation/coregraphics/cgdirectdisplayid)
  ///     that identifies the display to create a `Display` object for.
  /// - Important: Although the Apple documentation for the
  ///     [CGDisplayCopyAllDisplayModes](https://developer.apple.com/documentation/coregraphics/cgdisplaycopyalldisplaymodes(_:_:))
  ///     method indicates it only returns `nil` if called with an invalid display ID, that has proven to not be true. Apparently this
  ///     method will return `nil` when macOS is in the process of querying the display for information. Unfortunately macOS will
  ///     post [didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)
  ///     before it has finished querying the display and populating this information. This creates a race condition where IINA may or
  ///     may not find the display information populated. See issue [#6215](https://github.com/iina/iina/issues/6215)
  ///     for details.
  ///
  ///     Currently this information is only used for logging display attributes to help with debugging problems, so it is acceptable to
  ///     not populate `displayModes`.  If in the future this information is needed for a feature, such as matching the refresh rate
  ///     of the display, changes in this area will be needed.
  init(_ displayId: CGDirectDisplayID) {
    self.displayId = displayId
    isBuiltin = CGDisplayIsBuiltin(displayId) != 0
    modelNumber = CGDisplayModelNumber(displayId)
    vendorNumber = CGDisplayVendorNumber(displayId)

    // Obtain all the available modes on the display and filter out all except the native modes.
    // Native modes are of interest as IINA in the future might add support for matching the refresh
    // rate of the display when in full screen mode.
    if let allDisplayModes = CGDisplayCopyAllDisplayModes(displayId, nil) as? [CGDisplayMode] {
      var usableDisplayModes = allDisplayModes
      usableDisplayModes.removeAll(where: { !$0.isNative })
      // When waking up, macOS may return a virtual display that does not report any native modes.
      displayModes = usableDisplayModes.isEmpty ? nil : usableDisplayModes
    } else {
      // As discussed above in the comments for this initializer, this method will return nil when
      // macOS is in the process of querying the display for information.
      Logger.log("Failed to obtain display modes for display \(displayId)")
      displayModes = nil
    }
    // Additional information has to be obtained from the display's info dictionary.
    guard let info = CoreDisplay_DisplayCreateInfoDictionary(displayId)?.takeRetainedValue() as?
            [String: AnyObject] else {
      // Not expected to occur, but we don't want it to be a fatal error if it does occur.
      Logger.log("Failed to create info dictionary for display \(displayId)", level: .error)
      displayBacklight = nil
      isVirtual = false
      nonReferencePeakHDRLuminance = nil
      nonReferencePeakSDRLuminance = nil
      productName = nil
      referencePeakHDRLuminance = nil
      referencePeakSDRLuminance = nil
      return
    }
    // It appears the luminance of non-XDR displays is reported using the key DisplayBacklight.
    displayBacklight = info["DisplayBacklight"] as? Int
    if let virtual = info["kCGDisplayIsVirtualDevice"] as? Int {
      isVirtual = virtual == 1
    } else {
      isVirtual = false
    }
    // As the product name is only used in a log message we use the English name. When waking up,
    // macOS may return a virtual display that populates all the names with empty strings, so a
    // check that the name is not empty is required.
    if let productNames = info["DisplayProductName"] as? [String: String],
       let name = productNames["en_US"], !name.isEmpty {
      productName = name
    } else {
      productName = nil
    }
    // These luminance keys were seen with XDR displays.
    nonReferencePeakHDRLuminance = info["NonReferencePeakHDRLuminance"] as? Int
    nonReferencePeakSDRLuminance = info["NonReferencePeakSDRLuminance"] as? Int
    referencePeakHDRLuminance = info["ReferencePeakHDRLuminance"] as? Int
    referencePeakSDRLuminance = info["ReferencePeakSDRLuminance"] as? Int
  }
}

// MARK: - Rate Formatter

/// A formatter for formatting display refresh rates in log messages.
///
/// The primary reason for this formatter is to avoid logging floating point numbers with a large number of fractional digits making log
/// messages hard to read.
private class RateFormatter: NumberFormatter, @unchecked Sendable {

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
  var isNative: Bool { (ioFlags & UInt32(kDisplayModeNativeFlag)) != 0 }

  var shortDescription: String { "\(width)x\(height) @ \(rateFormatter.string(for: refreshRate))" }
}
