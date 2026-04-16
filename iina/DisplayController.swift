//
//  DisplayController.swift
//  iina
//
//  Created by low-batt on 9/5/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

/// Controller that keeps track of displays discovered using
/// [CGGetActiveDisplayList](https://developer.apple.com/documentation/coregraphics/cggetactivedisplaylist(_:_:_:)).
class DisplayController {
  /// The `DisplayController` singleton object.
  static let shared = DisplayController()

  /// Known displays.
  private var displays: [CGDirectDisplayID: Display] = [:]

  /// Calls
  /// [CGGetActiveDisplayList](https://developer.apple.com/documentation/coregraphics/cggetactivedisplaylist(_:_:_:))
  /// and records any previously unknown displays.
  ///
  /// The details of any newly discovered displays will be logged.
  func addNewDisplays() {
    // Get the number of displays.
    var maxDisplays: CGDisplayCount = 0
    var result = CGGetOnlineDisplayList(0, nil, &maxDisplays)
    guard checkResult(result, "CGGetOnlineDisplayList") else { return }

    // If there are no new displays there is nothing to do.
    guard maxDisplays != displays.count else { return }

    // Now that we know the number of displays we can allocate the appropriate sized array.
    var displayCount: CGDisplayCount = 0
    var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
    result = CGGetOnlineDisplayList(maxDisplays, &onlineDisplays, &displayCount)
    guard checkResult(result, "CGGetOnlineDisplayList") else { return }

    // Go through the list and add any newly discovered displays to our display dictionary.
    for displayId in onlineDisplays {
      guard !displays.keys.contains(displayId) else { continue }
      let display = Display(displayId)
      displays[displayId] = display
      // Log the details of the newly discovered display.
      Logger.log(display.description)
    }
  }

  private init() {}

  // MARK: - Error Checking

  /// Check the result of calling a [Core Graphics](https://developer.apple.com/documentation/coregraphics) method.
  /// 
  /// If the result code is not [success](https://developer.apple.com/documentation/coregraphics/cgerror/success)
  /// then an error message will be logged and `false` will be returned.
  /// - Parameters:
  ///   - result: The [CGError](https://developer.apple.com/documentation/coregraphics/cgerror) result
  ///             code returned by the core graphics method.
  ///   - method: The core graphics method that returned the result code.
  /// - Returns: `True` if the call was successful; `false` otherwise.
  private func checkResult(_ result: CGError, _ method: String) -> Bool {
    guard result != .success else { return true }
    Logger.log("Core graphics method \(method) failed: \(result) (\(result.rawValue))", level: .error)
    return false
  }
}

// MARK: - Extensions

/// A uniform type for result codes returned by functions in Core Graphics.
extension CGError: @retroactive CustomStringConvertible {

  /// A description of what the error code indicates.
  ///
  /// See the Apple [CGError](https://developer.apple.com/documentation/coregraphics/cgerror) documentation.
  public var description: String {
    switch self {
    case .cannotComplete:
      "The requested operation is inappropriate for the parameters passed in, or the current system state"
    case .failure:
      "A general failure occurred"
    case .illegalArgument:
      "One or more of the parameters passed to a function are invalid. Check for NULL pointers"
    case .invalidConnection:
      "The parameter representing a connection to the window server is invalid"
    case .invalidContext:
      "The CPSProcessSerNum or context identifier parameter is not valid"
    case .invalidOperation:
      "The requested operation is not valid for the parameters passed in, or the current system state"
    case .noneAvailable:
      "The requested operation could not be completed as the indicated resources were not found"
    case .notImplemented:
      "Return value from obsolete function stubs present for binary compatibility, but not typically called"
    case .rangeCheck:
      "A parameter passed in has a value that is inappropriate, or which does not map to a useful operation or value"
    case .success:
      "The requested operation was completed successfully"
    case .typeCheck:
      "A data type or token was encountered that did not match the expected type or token"
    @unknown default:
      "Unrecognized core graphics return code"
    }
  }
}
