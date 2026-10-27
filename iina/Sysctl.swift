//
//  Sysctl.swift
//  iina
//
//  Created by low-batt on 7/18/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// Wrapper to provide easy access to system information accessible through [sysctlbyname](https://developer.apple.com/documentation/kernel/1387446-sysctlbyname).
///
/// - Important: The values returned by the computed properties are optional because we do not know if the kernel state is
///     available in old versions of macOS supported by IINA.
struct Sysctl {
  static let shared = Sysctl()

  /// Mac model identifier, e.g., `MacBookPro18,2`.
  var hwModel: String? { getString("hw.model") }
  
  /// CPU chip, e.g., `Apple M1 Max`.
  var machineCpuBrandString: String? { getString("machdep.cpu.brand_string") }
  
  /// Retrieve the kernel state with the given name as a string.
  /// - Parameter name: Name of the state to retrieve.
  /// - Returns: Value of given state or `nil` if the value can not be obtained.
  private func getString(_ name: String) -> String? {
    var size = 0
    // Get the size of the string.
    guard sysctlbyname(name, nil, &size, nil, 0) == EXIT_SUCCESS else {
      Logger.log("Call to sysctlbyname for \(name) failed: \(String(cString: strerror(errno))) (\(errno))", level: .warning)
      return nil
    }
    // Now get the named kernel state as a string.
    var value = [CChar](repeating: 0,  count: Int(size))
    guard sysctlbyname(name, &value, &size, nil, 0) == EXIT_SUCCESS else {
      Logger.log("Call to sysctlbyname for \(name) failed: \(String(cString: strerror(errno))) (\(errno))", level: .warning)
      return nil
    }
    return String(cString: value)
  }
}
