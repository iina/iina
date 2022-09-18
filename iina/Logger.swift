//
//  Logger.swift
//  iina
//
//  Created by Collider LI on 24/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

/// The IINA Logger.
///
/// Logging to a file is controlled by a preference in `Advanced` preferences and by default is disabled.
///
/// The logger takes a two phase approach to handling errors. During initialization of the logger any failure while creating the log directory,
/// creating the log file and opening the file for writing, is treated as a fatal error. The user will be shown an alert and when the user
/// dismisses the alert the application will terminate. Once the logger is successfully initialized errors involving the file are only printed to
/// the console to avoid disrupting playback.
/// - Important: The `createDirIfNotExist` method in `Utilities` **must not** be used by the logger. If an error occurs
///     that method will attempt to report it using the logger. If the logger is still being initialized this will result in a crash. For that reason
///     the logger uses its own similar method.
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
    // get path
    let libraryPaths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
    guard let libraryPath = libraryPaths.first else {
      fatalDuringInit("Cannot get path to Logs directory: \(libraryPaths)")
    }
    let logsUrl = libraryPath.appendingPathComponent("Logs", isDirectory: true)
    let bundleID = Bundle.main.bundleIdentifier!
    let appLogsUrl = logsUrl.appendingPathComponent(bundleID, isDirectory: true)

    // MUST NOT use the similar method in Utilities as that method uses Logger methods. Logger
    // methods must not ever be called while the logger is still initializing.
    createDirIfNotExist(url: logsUrl)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let timeString  = formatter.string(from: Date())
    let token = Utility.ShortCodeGenerator.getCode(length: 6)
    let sessionDirName = "\(timeString)_\(token)"
    let sessionDir = appLogsUrl.appendingPathComponent(sessionDirName, isDirectory: true)

    // MUST NOT use the similar method in Utilities. See above for reason.
    createDirIfNotExist(url: sessionDir)
    return sessionDir
  }()

  private static let logFile: URL = logDirectory.appendingPathComponent("iina.log")

  private static let loggerSubsystem = Logger.Subsystem(rawValue: "logger")

  private static var logFileHandle: FileHandle? = {
    FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: nil)
    do {
      return try FileHandle(forWritingTo: logFile)
    } catch  {
      fatalDuringInit("Cannot open log file \(logFile.path) for writing: \(error.localizedDescription)")
    }
  }()

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  // Must coordinate closing of the log file to avoid writing to a closed file handle.
  private static let lock = Lock()

  /// Closes the log file, if logging is enabled,
  /// - Important: Currently IINA does not coordinate threads during termination. This results in a race condition as to whether
  ///     a thread will attempt to log a message after the log file has been closed or not.  Previously this was triggering crashes due
  ///     to writing to a closed file handle. The logger now uses a lock to coordinate closing of the log file. If a log message is logged
  ///     after the log file is closed it will only be logged to the console.
  static func closeLogFile() {
    guard enabled else { return }
    // Lock to avoid closing the log file while another thread is writing to it.
    lock.withLock {
      guard let fileHandle = logFileHandle else { return }
      do {
        // The deprecated method is used instead of the new close method that throws swift exceptions
        // because testing with the new write method found it failed to convert all objective-c
        // exceptions to swift exceptions.
        try ObjcUtils.catchException { fileHandle.closeFile() }
      } catch {
        // Unusual, but could happen if closing causes a buffer to be flushed to a full disk.
        print(formatMessage("Cannot close log file \(logFile.path): \(error.localizedDescription)",
                            .error, Logger.loggerSubsystem, true))
      }
      logFileHandle = nil
    }
  }

  /// Creates a directory at the specified URL along with any nonexistent parent directories.
  ///
  /// If the directory cannot be created then this method will treat the failure as a fatal error. The user will be shown an alert and when
  /// the user dismisses the alert the application will terminate.
  /// - Parameter url: A file URL that specifies the directory to create.
  /// - Important: This method is designed to be usable during logger initialization. The similar method found in `Utilities`
  ///     **must not** be used. If an error occurs that method will attempt to report it using the logger. As the logger is still being
  ///     initialized this will result in a crash.
  private static func createDirIfNotExist(url: URL) {
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    } catch {
      fatalDuringInit("Cannot create directory \(url): \(error.localizedDescription)")
    }
  }

  private static func formatMessage(_ message: String, _ level: Level, _ subsystem: Subsystem,
                                    _ appendNewlineAtTheEnd: Bool) -> String {
    let time = dateFormatter.string(from: Date())
    return "\(time) [\(subsystem.rawValue)][\(level.description)] \(message)\(appendNewlineAtTheEnd ? "\n" : "")"
  }

  static func log(_ message: String, level: Level = .debug, subsystem: Subsystem = .general, appendNewlineAtTheEnd: Bool = true) {
    #if !DEBUG
    guard enabled else { return }
    #endif

    guard level >= .preferred else { return }
    let string = formatMessage(message, level, subsystem, appendNewlineAtTheEnd)
    print(string, terminator: "")

    #if DEBUG
    guard enabled else { return }
    #endif

    guard let data = string.data(using: .utf8) else {
      print(formatMessage("Cannot encode log string!", .error, Logger.loggerSubsystem, false))
      return
    }
    // Lock to prevent the log file from being closed by another thread while writing to it.
    lock.withLock() {
      // The logger may be called after it has been closed.
      guard let logFileHandle = logFileHandle else { return }
      do {
        // The deprecated write method is used instead of the replacement method that throws swift
        // exceptions because testing the new method with macOS 12.5.1 showed that method failed to
        // turn all objective-c exceptions into swift exceptions. The exception thrown for writing
        // to a closed channel was not picked up by the catch block.
        try ObjcUtils.catchException { logFileHandle.write(data) }
      } catch {
        print(formatMessage("Cannot write to log file: \(error.localizedDescription)", .error,
                            Logger.loggerSubsystem, false))
      }
    }
  }

  static func ensure(_ condition: @autoclosure () -> Bool, _ errorMessage: String = "Assertion failed in \(#line):\(#file)", _ cleanup: () -> Void = {}) {
    guard condition() else {
      log(errorMessage, level: .error)
      showAlertAndExit(errorMessage, cleanup)
    }
  }

  static func fatal(_ message: String, _ cleanup: () -> Void = {}) -> Never {
    log(message, level: .error)
    log(Thread.callStackSymbols.joined(separator: "\n"))
    showAlertAndExit(message, cleanup)
  }

  /// Reports a fatal error during logger initialization and stops execution.
  ///
  /// This method will print the given error message to the console and then show an alert to the user. When the user dismisses the
  /// alert this method will terminate the process with an exit code of one.
  /// - Parameter message: The fatal error to report.
  /// - Important: This method differs from the method `fatal` in that it is designed to be safe to call during logger initialization
  ///     and therefore intentionally avoids attempting to log the fatal error message.
  private static func fatalDuringInit(_ message: String) -> Never {
    print(formatMessage(message, .error, Logger.loggerSubsystem, true))
    showAlertAndExit(message)
  }

  private static func showAlertAndExit(_ message: String, _ cleanup: () -> Void = {}) -> Never {
    Utility.showAlert("fatal_error", arguments: [message])
    cleanup()
    exit(1)
  }
}
