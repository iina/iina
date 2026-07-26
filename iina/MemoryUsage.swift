//
//  MemoryUsage.swift
//  iina
//
//  Created by low-batt on 11/11/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

/// Memory usage  logging.
///
/// This singleton provides the ability to log some statistics regarding memory usage. This provides some insight into memory use when
/// IINA is being used by users.
class MemoryUsage {
  /// The `MemoryUsage` singleton object.
  static let shared = MemoryUsage()

  private let formatter = {
    var formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
  }()

  /// Established notification observers.
  private var observers: [NSObjectProtocol] = []

  /// Current heap space used in bytes.
  private var heapInUse: Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return statistics.size_in_use
  }

  /// Current memory footprint in bytes.
  ///
  /// This is an abstract representation of the general memory impact of the IINA process,
  ///
  /// This code was adapted from an Apple DTS Engineer's response to the post
  /// [how XCode to calculate Memory](https://developer.apple.com/forums/thread/105088) in the Apple developer
  /// forum.
  private var physFootprint: mach_vm_size_t? {
    // The `TASK_VM_INFO_COUNT` and `TASK_VM_INFO_REV1_COUNT` macros are too
    // complex for the Swift C importer, so we have to define them ourselves.
    let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size /
                                                    MemoryLayout<integer_t>.size)
    let TASK_VM_INFO_REV1_COUNT = mach_msg_type_number_t(
      MemoryLayout.offset(of: \task_vm_info_data_t.min_address)! / MemoryLayout<integer_t>.size)
    var info = task_vm_info_data_t()
    var count = TASK_VM_INFO_COUNT
    let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
      infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
      }
    }
    guard kr == KERN_SUCCESS, count >= TASK_VM_INFO_REV1_COUNT else {
      var message = String(cString: mach_error_string(kr), encoding: String.Encoding.ascii) ?? ""
      if !message.isEmpty {
        message += ", "
      }
      message += "return code \(kr)"
      log("Call to task_info failed: " + message, level: .error)
      return nil
    }
    return info.phys_footprint
  }

  // MARK: - Public Functions

#if DEBUG
  /// Log  current memory usage.
  ///
  /// Logs the memory usage along with the name of the function calling `logUsage` and the line number in the source code of the
  /// call. This is useful when you want to quickly insert a call for debugging problems without taking the time to add a comment
  /// identifying the location of the call.
  /// - Parameters:
  ///   - function: Name of function calling `logUsage`.
  ///   - line: Line number in the source code of the call to `logUsage`.
  func logUsage(function: String = #function, line: Int = #line) {
    logUsage(includeLocation: true, function, line)
  }
#endif

  /// Log  current memory usage.
  /// - Parameters:
  ///   - comment: Comment describing the call to `logUsage`.
  ///   - includeLocation: Whether to include the name of the function calling `logUsage` and the line number in the source
  ///       code of the call.
  ///   - function: Name of function calling `logUsage`.
  ///   - line: Line number in the source code of the call to `logUsage`.
  func logUsage(_ comment: String? = nil, includeLocation: Bool = false,
                _ function: String = #function, _ line: Int = #line) {
    // Use a closure to avoid forming a message when logging is not enabled.
    log ({
      var message: String = ""
      if includeLocation {
        var withoutParams = function
        if let index = function.firstIndex(of: "(") {
          withoutParams = String(withoutParams.prefix(upTo: index))
        }
        message += "\(withoutParams):\(line) "
      }
      message += "Memory usage"
      if let comment { message += " \(comment)" }
      message += ":"
      if let physFootprint {
        let formatted = formatter.string(for: physFootprint) ?? String(describing: physFootprint)
        message += " footprint \(formatted) b"
      }
      let formatted = formatter.string(for: heapInUse) ?? String(describing: heapInUse)
      return "\(message) heap \(formatted) b"
    }())
  }

  // MARK: - Utils

  private func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.memory)
  }

  private func observe(_ name: Notification.Name, block: @escaping (Notification) -> Void) {
    observers.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                                                            queue: .main, using: block))
  }

  private init() {
    observe(.iinaFileLoaded) { [unowned self] notification in
      logUsage("after file loaded", includeLocation: false)
    }
  }

  deinit {
    observers.forEach {
      NotificationCenter.default.removeObserver($0)
    }
  }
}

// MARK: - Extensions

extension Logger.Sub {
  static let memory = Logger.makeSubsystem("memory", ["memorychip"])
}
