//
//  Logger.swift
//  iina
//
//  Created by Collider LI on 24/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

class Logger {

  enum LogLevel: Int, Comparable {

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
      return lhs.rawValue < rhs.rawValue
    }

    case verbose
    case debug
    case warning
    case error

    var stringValue: String {
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
  var useNSLog = false

  static let enabled = Preference.bool(for: .enableLogging)
  static let logDirectory: URL = {
    let date = Date()
    let calendar = NSCalendar.current
    let y = calendar.component(.year, from: date)
    let m = calendar.component(.month, from: date)
    let d = calendar.component(.day, from: date)
    let h = calendar.component(.hour, from: date)
    let mm = calendar.component(.minute, from: date)
    let s = calendar.component(.second, from: date)
    let token = Utility.ShortCodeGenerator.getCode(length: 6)
    let sessionDirName = "\(y)-\(m)-\(d)-\(h)-\(mm)-\(s)_\(token)"
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
    return enabled ? Logger(label: label) : nil
  }

  static func closeLogFile() {
    guard Logger.enabled else { return }
    logFileHandle.closeFile()
  }

  private static func log(_ message: String, label: String, level: LogLevel, useNSLog: Bool, appendNewlineAtTheEnd: Bool) {
    let time = dateFormatter.string(from: Date())
    let string = "\(time) [\(label)][\(level.stringValue)] \(message)\(appendNewlineAtTheEnd ? "\n" : "")"
    if useNSLog {
      NSLog("%@", string)
      return
    }
    if let data = string.data(using: .utf8) {
      logFileHandle.write(data)
    } else {
      NSLog("%@", "Cannot encode log string!")
    }
  }

  static let general: Logger? = {
    #if DEBUG
      let logger = Logger(label: "iina")
      if !Logger.enabled {
        logger.useNSLog = true
      }
      return logger
    #else
      return Logger.getLogger("iina")
    #endif
  }()

  private init(label: String, logLevel: LogLevel = .debug) {
    self.label = label
    self.level = logLevel
  }

  func verbose(_ message: String, appendNewline: Bool = true) {
    guard level <= .verbose else { return }
    Logger.log(message, label: label, level: .verbose, useNSLog: useNSLog, appendNewlineAtTheEnd: appendNewline)
  }

  func debug(_ message: String, appendNewline: Bool = true) {
    guard level <= .debug else { return }
    Logger.log(message, label: label, level: .debug, useNSLog: useNSLog, appendNewlineAtTheEnd: appendNewline)
  }

  func warning(_ message: String, appendNewline: Bool = true) {
    guard level <= .warning else { return }
    Logger.log(message, label: label, level: .warning, useNSLog: useNSLog, appendNewlineAtTheEnd: appendNewline)
  }

  func error(_ message: String, appendNewline: Bool = true) {
    guard level <= .error else { return }
    Logger.log(message, label: label, level: .error, useNSLog: useNSLog, appendNewlineAtTheEnd: appendNewline)
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
