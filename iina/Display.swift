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
    let modes = displayModes.reduce("", { result, displayMode in
      result + "\n    " + displayMode.shortDescription })
    description += "\n  Native modes:"
    description += modes
    return description
  }

  // Luminance of non-XDR displays.
  let displayBacklight: Int?

  let displayId: CGDirectDisplayID

  /// Native modes supported by the display.
  let displayModes: [CGDisplayMode]

  /// Whether the display is built-in, such as the internal display in portable systems.
  let isBuiltin: Bool

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
  init(_ displayId: CGDirectDisplayID) {
    self.displayId = displayId
    isBuiltin = CGDisplayIsBuiltin(displayId) != 0
    modelNumber = CGDisplayModelNumber(displayId)
    vendorNumber = CGDisplayVendorNumber(displayId)

    // Obtain all the available modes on the display and filter out all except the native modes.
    // Native modes are of interest as IINA in the future might add support for matching the refresh
    // rate of the display when in full screen mode.
    let allDisplayModes = CGDisplayCopyAllDisplayModes(displayId, nil) as! [CGDisplayMode]
    var usableDisplayModes = allDisplayModes
    usableDisplayModes.removeAll(where: { !$0.isNative })
    displayModes = usableDisplayModes

    // Additional information has to be obtained from the display's info dictionary.
    guard let info = CoreDisplay_DisplayCreateInfoDictionary(displayId)?.takeRetainedValue() as?
            [String: AnyObject] else {
      // Not expected to occur, but we don't want it to be a fatal error if it does occur.
      Logger.log("Failed to create info dictionary for display \(displayId)", level: .error)
      displayBacklight = nil
      nonReferencePeakHDRLuminance = nil
      nonReferencePeakSDRLuminance = nil
      productName = nil
      referencePeakHDRLuminance = nil
      referencePeakSDRLuminance = nil
      return
    }
    // It appears the luminance of non-XDR displays is reported using the key DisplayBacklight.
    displayBacklight = info["DisplayBacklight"] as? Int
    if let productName = info["DisplayProductName"] as? [String: String] {
      // As the product name is only used in a log message we use the English name.
      self.productName = productName["en_US"]
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
