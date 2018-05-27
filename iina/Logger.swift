//
//  Logger.swift
//  iina
//
//  Created by Collider LI on 24/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

class Logger {

  enum LogLevel: Int, Comparable, CustomStringConvertible {
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
      return lhs.rawValue < rhs.rawValue
    }

    case verbose
    case debug
    case warning
    case error

    static var preferred: LogLevel {
      return LogLevel(rawValue: Preference.integer(for: .logLevel).clamped(to: 0...3))!
    }

    var description: String {
      switch self {
      case .verbose: return "v"
      case .debug: return "d"
      case .warning: return "w"
      case .error: return "e"
      }
    }
  }

  var label: String
  var level: LogLevel
  var logToConsole = false

  static let enabled = Preference.bool(for: .enableLogging)
  static let logDirectory: URL = {
    let formatter = DateFormatter()
    formatter.dateFormat = "YYYY-MM-dd-HH-mm-ss"
    let timeString  = formatter.string(from: Date())
    let token = Utility.ShortCodeGenerator.getCode(length: 6)
    let sessionDirName = "\(timeString)_\(token)"
    let sessionDir = Utility.logDirURL.appendingPathComponent(sessionDirName, isDirectory: true)
    Utility.createDirIfNotExist(url: sessionDir)
    return sessionDir
  }()

  private static var logFileHandle: FileHandle = {
    let logFileURL = logDirectory.appendingPathComponent("iina.log")
    FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
    return try! FileHandle(forWritingTo: logFileURL)
  }()

  private static var dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd HH:mm:ss.SSS"
    return formatter
  }()

  static func getLogger(_ label: String) -> Logger? {
    #if DEBUG
    if !enabled {
      let logger = Logger(label: label, logLevel: .warning)
      logger.logToConsole = true
      return logger
    }
    #endif
    return enabled ? Logger(label: label) : nil
  }

  static func closeLogFile() {
    guard Logger.enabled else { return }
    logFileHandle.closeFile()
  }

  private static func log(_ message: String, label: String, level: LogLevel, logToConsole: Bool, appendNewlineAtTheEnd: Bool) {
    let time = dateFormatter.string(from: Date())
    let string = "\(time) [\(label)][\(level.description)] \(message)\(appendNewlineAtTheEnd ? "\n" : "")"
    if logToConsole {
      print("\(time) [\(label)][\(level.description)] \(message)")
      return
    }
    if let data = string.data(using: .utf8) {
      logFileHandle.write(data)
    } else {
      NSLog("Cannot encode log string!")
    }
  }

  static let general: Logger? = {
    return Logger.getLogger("iina")
  }()

  private init(label: String, logLevel: LogLevel = .preferred) {
    self.label = label
    self.level = logLevel
  }

  func verbose(_ message: String, appendNewline: Bool = true) {
    guard level <= .verbose else { return }
    Logger.log(message, label: label, level: .verbose, logToConsole: logToConsole, appendNewlineAtTheEnd: appendNewline)
  }

  func debug(_ message: String, appendNewline: Bool = true) {
    guard level <= .debug else { return }
    Logger.log(message, label: label, level: .debug, logToConsole: logToConsole, appendNewlineAtTheEnd: appendNewline)
  }

  func warning(_ message: String, appendNewline: Bool = true) {
    guard level <= .warning else { return }
    Logger.log(message, label: label, level: .warning, logToConsole: logToConsole, appendNewlineAtTheEnd: appendNewline)
  }

  func error(_ message: String, appendNewline: Bool = true) {
    guard level <= .error else { return }
    Logger.log(message, label: label, level: .error, logToConsole: logToConsole, appendNewlineAtTheEnd: appendNewline)
  }

  static func assert(_ expr: Bool, _ errorMessage: String, _ block: () -> Void = {}) {
    if !expr {
      general?.error(errorMessage)
      Utility.showAlert("fatal_error", arguments: [errorMessage])
      block()
      exit(1)
    }
  }

  static func fatal(_ message: String, _ block: () -> Void = {}) -> Never {
    general?.error(message)
    general?.debug(Thread.callStackSymbols.joined(separator: "\n"))
    Utility.showAlert("fatal_error", arguments: [message])
    block()
    // Exit without crash since it's not uncatched/unhandled
    exit(1)
  }
}
