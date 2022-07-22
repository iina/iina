//
//  MPVLogLevel.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.09.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

enum MPVLogLevel: Int, CustomStringConvertible {
  case no = 0  // - disable absolutely all messages
  case fatal   // - critical/aborting errors
  case error   // - simple errors
  case warn    // - possible problems
  case info    // - informational message
  case verbose // - noisy informational message
  case debug   // - very noisy technical information
  case trace   // - extremely noisy

  static func fromString(_ name: String) -> MPVLogLevel? {
    if name.count == 1 {
      switch name {
        case "n":
          return .no
        case "f":
          return .fatal
        case "e":
          return .error
        case "w":
          return .warn
        case "i":
          return .info
        case "v":
          return .verbose
        case "d":
          return .debug
        case "t":
          return .trace
        default:
          return nil
      }
    }

    switch name {
      case "no":
        return .no
      case "fatal":
        return .fatal
      case "error":
        return .error
      case "warn":
        return .warn
      case "info":
        return .info
      case "verbose":
        return .verbose
      case "debug":
        return .debug
      case "trace":
        return .trace
      default:
        return nil
    }
  }

  public var description: String {
    get {
      switch self {
        case .no:
          return "no"
        case .fatal:
          return "fatal"
        case .error:
          return "error"
        case .warn:
          return "warn"
        case .info:
          return "info"
        case .verbose:
          return "verbose"
        case .debug:
          return "debug"
        case .trace:
          return "trace"
      }
    }
  }

  /*
   Assumes that `self` represents a logging threshold.
   Returns  true if the given level falls within this logging threshold.
   Example: MPVLogLevel.debug.shouldLog(5) -> true
   */
  public func shouldLog(severity: Int) -> Bool {
    return rawValue >= severity
  }

  /*
   Assumes that `self` represents a logging threshold.
   Returns  true if the given level falls within this logging threshold.
   Examples:
   1. MPVLogLevel.info.shouldLog("debug") -> false
   2. MPVLogLevel.debug.shouldLog("verbose") -> false
   */
 public func shouldLog(severity: String) -> Bool {
   if let severityParsed = MPVLogLevel.fromString(severity) {
     return shouldLog(severity: severityParsed.rawValue)
   } else {
     Logger.log("Failed to parse logging level: '\(severity)'", level: .error)
     return false
   }
 }
}
