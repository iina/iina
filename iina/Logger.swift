//
//  Logger.swift
//  iina
//
//  Created by Collider LI on 24/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

struct Logger {

  struct Subsystem: RawRepresentable {
    var rawValue: String

    static let general = Subsystem(rawValue: "iina")

    init(rawValue: String) {
      self.rawValue = rawValue
    }
  }

  enum Level: Int, Comparable, CustomStringConvertible {
    static func < (lhs: Level, rhs: Level) -> Bool {
      return lhs.rawValue < rhs.rawValue
    }

    case verbose
    case debug
    case warning
    case error

    static var preferred: Level = Level(rawValue: Preference.integer(for: .logLevel).clamped(to: 0...3))!

    var description: String {
      switch self {
      case .verbose: return "v"
      case .debug: return "d"
      case .warning: return "w"
      case .error: return "e"
      }
    }
  }

  static let enabled = Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .enableLogging)

  static let logDirectory: URL = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
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
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  static func closeLogFile() {
    guard enabled else { return }
    logFileHandle.closeFile()
  }

  static func log(_ message: String, level: Level = .debug, subsystem: Subsystem = .general, appendNewlineAtTheEnd: Bool = true) {
    #if !DEBUG
    guard enabled else { return }
    #endif

    guard level >= .preferred else { return }
    let time = dateFormatter.string(from: Date())
    let string = "\(time) [\(subsystem.rawValue)][\(level.description)] \(message)\(appendNewlineAtTheEnd ? "\n" : "")"
    print(string, terminator: "")

    #if DEBUG
    guard enabled else { return }
    #endif

    if let data = string.data(using: .utf8) {
      logFileHandle.write(data)
    } else {
      NSLog("Cannot encode log string!")
    }
  }

  static func ensure(_ condition: @autoclosure () -> Bool, _ errorMessage: String = "Assertion failed in \(#line):\(#file)", _ cleanup: () -> Void = {}) {
    guard condition() else {
      log(errorMessage, level: .error)
      Utility.showAlert("fatal_error", arguments: [errorMessage])
      cleanup()
      exit(1)
    }
  }

  static func fatal(_ message: String, _ cleanup: () -> Void = {}) -> Never {
    log(message, level: .error)
    log(Thread.callStackSymbols.joined(separator: "\n"))
    Utility.showAlert("fatal_error", arguments: [message])
    cleanup()
    exit(1)
  }
}
