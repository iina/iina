//
//  MPVDefaults.swift
//  iina
//
//  Created by low-batt on 10/24/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// Default values for mpv options.
///
/// The default value for a mpv option can be obtained using the mpv property 
/// [option-info/\<name>/default-value](https://mpv.io/manual/stable/#command-interface-option-info/%3Cname%3E/default-value).
/// _Unfortunately_, this property is not available until a mpv instance has been initialized. IINA uses the default values when setting
/// options in order to reduce the number of log messages emitted by only logging options that are not being set to the default value.
/// The options are set in `MVPController.mpvInit`  before the mpv instance is initialized and the property containing the option
/// defaults is available. To work around this mpv restriction this class uses its own mpv instance dedicated to providing the defaults.
///
/// A similar issue exists for the mpv properties that provide the mpv and libass version numbers, which IINA would like log near the
/// start of the log file. So this class also provides the version numbers.
class MPVOptionDefaults {
  /// The `MPVDefaults` singleton object.
  static let shared = MPVOptionDefaults()

  /// Version number of the libass library.
  ///
  /// The mpv libass version property returns an integer encoded as a hex binary-coded decimal.
  var libassVersion: String {
    guard mpv != nil, let version = getPropertyAsInt(MPVProperty.libassVersion) else {
      return "Unable to obtain libass version number"
    }
    let major = String(version >> 28 & 0xF, radix: 16)
    let minor = String(version >> 20 & 0xFF, radix: 16)
    let patch = String(version >> 12 & 0xFF, radix: 16)
    return "\(major).\(minor).\(patch)"
  }

  /// Version number of the mpv library.
  var mpvVersion: String {
    guard mpv != nil, let version = getPropertyAsString(MPVProperty.mpvVersion) else {
      return "Unable to obtain mpv version number"
    }
    return version
  }

  private let mpv: OpaquePointer?

  private init() {
    mpv = mpv_create()
    guard mpv != nil else {
      MPVOptionDefaults.log("Failed to create a mpv instance", level: .error)
      return
    }
    logError(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.loadAutoProfiles, "no"))
    logError(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.loadOsdConsole, "no"))
    logError(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.loadScripts, "no"))
    logError(mpv_set_option_string(mpv, MPVOption.ProgramBehavior.loadStatsOverlay, "no"))
    logError(mpv_initialize(mpv))
  }

  // MARK: - Default Value Getters

  func getDouble(_ name: String) -> Double? {
    var data = Double()
    let errorCode = getDefaultValue(name, MPV_FORMAT_DOUBLE, &data)
    guard errorCode >= 0 else { return nil }
    return data
  }

  func getFlag(_ name: String) -> Bool? {
    var data = Int64()
    let errorCode = getDefaultValue(name, MPV_FORMAT_FLAG, &data)
    guard errorCode >= 0 else { return nil }
    return data > 0
  }

  func getInt(_ name: String) -> Int? {
    var data = Int64()
    let errorCode = getDefaultValue(name, MPV_FORMAT_INT64, &data)
    guard errorCode >= 0 else { return nil }
    return Int(data)
  }

  func getString(_ name: String) -> String? {
    guard mpv != nil else { return nil }
    let cstr = mpv_get_property_string(mpv, formPropertyName(name))
    let str: String? = cstr == nil ? nil : String(cString: cstr!)
    mpv_free(cstr)
    return str
  }

  // MARK: - Supporting Methods
  
  /// Forms the name of the mpv property containing the default value for the given mpv option.
  /// - Parameter name: Name of the mpv option.
  /// - Returns: Name of property to get the value of.
  private func formPropertyName(_ name: String) -> String { "option-info/\(name)/default-value" }
  
  /// Get the default value for the given option.
  /// - Note: If a mpv instance could not be created when this class was initialized then this method will return `Int32.min` as an
  ///         error code. That number was chosen to make it clear this it is not a mpv error code.
  /// - Parameters:
  ///   - name: Name of the mpv option.
  ///   - format: Format of the given option.
  ///   - data: Pointer to the variable that will holdErr the option value.
  /// - Returns: Error code, 0 and positive values mean success, negative values are always errors.
  private func getDefaultValue(_ name: String, _ format: mpv_format, _ data: UnsafeMutableRawPointer) -> Int32 {
    guard mpv != nil else { return Int32.min }
    return logError(mpv_get_property(mpv, formPropertyName(name), format, data))
  }

  private func getPropertyAsInt(_ name: String) -> Int? {
    guard mpv != nil else { return nil }
    var data = Int64()
    let errorCode = logError(mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data))
    guard errorCode >= 0 else { return nil }
    return Int(data)
  }

  private func getPropertyAsString(_ name: String) -> String? {
    guard mpv != nil else { return nil }
    let cstr = mpv_get_property_string(mpv, name)
    let str: String? = cstr == nil ? nil : String(cString: cstr!)
    mpv_free(cstr)
    return str
  }

  @discardableResult
  private func logError(_ errorCode: Int32) -> Int32 {
    guard errorCode < 0 else { return errorCode }
    MPVOptionDefaults.log("mpv API error: \"\(String(cString: mpv_error_string(errorCode)))\", Return value: \(errorCode)", level: .error)
    return errorCode
  }

  private static func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.mpvDefaults)
  }
}

extension Logger.Sub {
  static let mpvDefaults = Logger.makeSubsystem("mpv-defaults")
}
