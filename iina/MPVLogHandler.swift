//
//  MPVLogHandler.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.09.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

private let DEFINE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\", contents=\"(.*)\", flags=\"(.*)\"\]"#, options: []
)
private let ENABLE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\", flags=\"(.*)\"\]"#, options: []
)
private let DISABLE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\"\]"#, options: []
)
private let FLAGS_REGEX = try! NSRegularExpression(
  pattern: #"[^\+]+"#, options: []
)

private func all(_ string: String) -> NSRange {
  return NSRange(location: 0, length: string.count)
}

class MPVLogHandler {
  /*
   * Change this variable to adjust threshold for *receiving* MPV_EVENT_LOG_MESSAGE messages.
   * NOTE: Lua keybindings require at *least* level "debug", so don't set threshold to be stricter than this level
   */
  static let mpvLogSubscriptionLevel: MPVLogLevel = .debug

  /*
   * Change this variable to adjust threshold for writing MPV_EVENT_LOG_MESSAGE messages in IINA's log.
   * This is unrelated to any log files mpv writes to directly.
   */
  static let iinaMpvLogLevel = MPVLogLevel(rawValue: Preference.integer(for: .iinaMpvLogLevel))!

  private unowned let player: PlayerCore

  /*
   Only used for messages coming directly from the mpv log event stream
   */
  let mpvLogSubsystem: Logger.Subsystem

  init(player: PlayerCore) {
    self.player = player
    mpvLogSubsystem = Logger.Subsystem(rawValue: "mpv\(player.label)")
  }

  // Assumes we are NOT running on the main thread.
  func handleLogMessage(prefix: String, level: String, msg: String) {
    // Reproduce the log line to IINA log only if within the configured mpv logging threshold
    // (and of course only if IINA logging threshold is .debug or above)
    if MPVLogHandler.iinaMpvLogLevel.shouldLog(severity: level) {
      // try to match IINA's log format
      let lev = level[level.index(level.startIndex, offsetBy: 0)]  // Some log levels are spelled out. Others are only 1 char. Shorten all to 1 char
      Logger.log("[\(prefix)][\(lev)] \(msg)", level: .debug, subsystem: mpvLogSubsystem, appendNewlineAtTheEnd: false)
    }
    extractSectionInfo(prefix: prefix, severity: level, msg: msg)
  }

  /**
   Looks for key binding sections set in scripts; extracts them if found & sends them to relevant key input controller.
   Expected to return `true` if parsed & handled, `false` otherwise
   */
  @discardableResult
  private func extractSectionInfo(prefix: String, severity: String, msg: String) -> Bool {
    guard prefix == "cplayer", severity == MPVLogLevel.debug.description else {
      return false
    }

    if msg.starts(with: "Run command: define-section") {
      // Contains key binding definitions
      return handleDefineSection(msg)
    } else if msg.starts(with: "Run command: enable-section") {
      // Enable key binding
      return handleEnableSection(msg)
    } else if msg.starts(with: "Run command: disable-section") {
      // Disable key binding
      return handleDisableSection(msg)
    }
    return false
  }

  private func matchRegex(_ regex: NSRegularExpression, _ msg: String) -> NSTextCheckingResult? {
    return regex.firstMatch(in: msg, options: [], range: all(msg))
  }

  private func parseFlags(_ flagsUnparsed: String) -> [String] {
    let matches = FLAGS_REGEX.matches(in: flagsUnparsed, range: all(flagsUnparsed))
    if matches.isEmpty {
      return [MPVInputSection.FLAG_DEFAULT]
    }
    return matches.map { match in
      return String(flagsUnparsed[Range(match.range, in: flagsUnparsed)!])
    }
  }

  private func parseMappingsFromDefineSectionContents(_ contentsUnparsed: String) -> [KeyMapping] {
    var keyMappings: [KeyMapping] = []
    if contentsUnparsed.isEmpty {
      return keyMappings
    }

    for line in contentsUnparsed.components(separatedBy: "\\n") {
      if !line.isEmpty {
        let tokens = line.split(separator: " ")
        if tokens.count == 3 && tokens[1] == MPVCommand.scriptBinding.rawValue {
          keyMappings.append(KeyMapping(rawKey: String(tokens[0]), rawAction: "\(tokens[1]) \(tokens[2])"))
        } else {
          // "This command can be used to dispatch arbitrary keys to a script or a client API user".
          // Need to figure out whether to add support for these as well.
          Logger.log("Unrecognized mpv command in `define-section`; skipping line: \"\(line)\"", level: .warning, subsystem: player.subsystem)
        }
      }
    }
    return keyMappings
  }

  /*
   "define-section"

   Example log line:
   [cplayer] debug: Run command: define-section, flags=64, args=[name="input_forced_webm",
      contents="e script-binding webm/e\nESC script-binding webm/ESC\n", flags="force"]
   */
  private func handleDefineSection(_ msg: String) -> Bool {
    guard let match = matchRegex(DEFINE_SECTION_REGEX, msg) else {
      Logger.log("Found 'define-section' but failed to parse it: \(msg)", level: .error, subsystem: player.subsystem)
      return false
    }

    guard let nameRange = Range(match.range(at: 1), in: msg),
          let contentsRange = Range(match.range(at: 2), in: msg),
          let flagsRange = Range(match.range(at: 3), in: msg) else {
      Logger.log("Parsed 'define-section' but failed to find capture groups in it: \(msg)", level: .error, subsystem: player.subsystem)
      return false
    }

    let name = String(msg[nameRange])
    let content = String(msg[contentsRange])
    let flags = parseFlags(String(msg[flagsRange]))
    var isForce = false  // defaults to false
    for flag in flags {
      switch flag {
        case MPVInputSection.FLAG_FORCE:
          isForce = true
        case MPVInputSection.FLAG_DEFAULT:
          isForce = false
        default:
          Logger.log("Unrecognized flag in 'define-section': \(flag)", level: .error, subsystem: player.subsystem)
          Logger.log("Offending log line: `\(msg)`", level: .error, subsystem: player.subsystem)
      }
    }

    let section = MPVInputSection(name: name, parseMappingsFromDefineSectionContents(content), isForce: isForce, origin: .libmpv)
    Logger.log("Got 'define-section' from mpv: \"\(section.name)\", keyMappings=\(section.keyMappingList.count), force=\(section.isForce) ", subsystem: player.subsystem)
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      let keyMappingList = section.keyMappingList.map { ("\t<\(section.name)> \($0.normalizedMpvKey) -> \($0.rawAction)") }
      let bindingsString: String
      if keyMappingList.isEmpty {
        bindingsString = " (none)"
      } else {
        bindingsString = "\n\(keyMappingList.joined(separator: "\n"))"
      }
      Logger.log("Bindings for section \"\(section.name)\":\(bindingsString)", level: .verbose, subsystem: player.subsystem)
    }
    player.inputConfig.defineSection(section)
    return true
  }

  /*
   "enable-section"
   */
  private func handleEnableSection(_ msg: String) -> Bool {
    guard let match = matchRegex(ENABLE_SECTION_REGEX, msg) else {
      Logger.log("Found 'enable-section' but failed to parse it: \(msg)", level: .error, subsystem: player.subsystem)
      return false
    }

    guard let nameRange = Range(match.range(at: 1), in: msg),
          let flagsRange = Range(match.range(at: 2), in: msg) else {
      Logger.log("Parsed 'enable-section' but failed to find capture groups in it: \(msg)", level: .error, subsystem: player.subsystem)
      return false
    }

    let name = String(msg[nameRange])
    let flags = parseFlags(String(msg[flagsRange]))

    Logger.log("Got 'enable-section' from mpv: \"\(name)\", flags=\(flags) ", subsystem: player.subsystem)
    player.inputConfig.enableSection(name, flags)
    return true
  }

  /*
   "disable-section"
   */
  private func handleDisableSection(_ msg: String) -> Bool {
    guard let match = matchRegex(DISABLE_SECTION_REGEX, msg) else {
      Logger.log("Found 'disable-section' but failed to parse it: \(msg)", level: .error, subsystem: player.subsystem)
      return false
    }

    guard let nameRange = Range(match.range(at: 1), in: msg) else {
      Logger.log("Parsed 'disable-section' but failed to find capture groups in it: \(msg)", level: .error, subsystem: player.subsystem)
      return false
    }

    let name = String(msg[nameRange])
    Logger.log("disable-section: \"\(name)\"", subsystem: player.subsystem)
    player.inputConfig.disableSection(name)
    return true
  }
}
