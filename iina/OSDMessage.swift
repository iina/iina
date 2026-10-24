//
//  OSDMessage.swift
//  iina
//
//  Created by lhc on 27/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

/// Available constants in OSD messages:
///
/// {{duration}}
/// {{preciseDuration}}
/// {{position}}
/// {{precisePosition}}
/// {{percentPos}}
/// {{currChapter}}
/// {{chapterCount}}

import Foundation

/// Capture provenance at mutation/observation time, before asynchronous UI delivery.
enum OSDFeedbackOrigin { case command, sidebar }

enum OSDFeedbackValue: Equatable {
  case number(Double)
  case text(String)

  init(_ text: String) {
    if let number = Double(text), number.isFinite { self = .number(number) }
    else if text == "yes" { self = .number(1) }
    else if text == "no" { self = .number(0) }
    else { self = .text(text) }
  }

  func matches(_ other: Self) -> Bool {
    switch (self, other) {
    case (.number(let lhs), .number(let rhs)):
      return lhs.isFinite && rhs.isFinite && abs(lhs - rhs) <= 0.000001 * max(1, abs(lhs), abs(rhs))
    default: return self == other
    }
  }
}

/// Only matching acknowledgements inherit a sidebar control's quiet feedback.
/// A later ordinary command supersedes that property, never unrelated controls.
final class OSDFeedbackOrigins {
  private struct Intent { let token: UUID; let value: OSDFeedbackValue }
  private let lock = NSLock()
  private var properties: [String: [Intent]] = [:]

  static func propertyKey(_ property: String) -> String {
    for prefix in ["options/", "file-local-options/"] where property.hasPrefix(prefix) {
      return String(property.dropFirst(prefix.count))
    }
    return property
  }

  @discardableResult
  func record(_ property: String, value: OSDFeedbackValue?, origin: OSDFeedbackOrigin) -> UUID? {
    let key = Self.propertyKey(property)
    lock.lock(); defer { lock.unlock() }
    guard origin == .sidebar, let value else { properties.removeValue(forKey: key); return nil }
    let token = UUID()
    properties[key, default: []].append(Intent(token: token, value: value))
    return token
  }

  func origin(for property: String, value: OSDFeedbackValue?) -> OSDFeedbackOrigin {
    lock.lock(); defer { lock.unlock() }
    let key = Self.propertyKey(property)
    guard let value, let intents = properties[key] else { return .command }
    guard let index = intents.firstIndex(where: { $0.value.matches(value) }) else {
      properties.removeValue(forKey: key)
      return .command
    }
    // Property events may arrive after several slider writes, or coalesce to the latest.
    // Keep the acknowledgement for duplicate events and any still-pending UI values.
    properties[key] = Array(intents[index...])
    return .sidebar
  }

  func cancel(_ property: String, token: UUID?) {
    guard let token else { return }
    lock.lock(); defer { lock.unlock() }
    let key = Self.propertyKey(property)
    guard var intents = properties[key] else { return }
    intents.removeAll { $0.token == token }
    if intents.isEmpty { properties.removeValue(forKey: key) }
    else { properties[key] = intents }
  }

  func reset() {
    lock.lock(); defer { lock.unlock() }
    properties.removeAll()
  }
}

/// Inspect command structure; execution always receives the original text.
enum OSDCommandRouting {
  private static let prefixes: Set<String> = ["no-osd", "osd-auto", "osd-bar", "osd-msg", "osd-msg-bar",
    "raw", "expand-properties", "repeatable", "nonrepeatable", "nonscalable", "async", "sync"]

  private static func normalized(_ words: [String]) -> [String] {
    var words = Array(words.drop(while: { prefixes.contains($0) }))
    if !words.isEmpty { words[0] = words[0].replacingOccurrences(of: "_", with: "-") }
    return words
  }

  static func commands(in text: String) -> [[String]] {
    // Match input/cmd.c token boundaries. Newlines are whitespace; a comment
    // ends the flat command string. Backslashes escape only inside double quotes.
    let input = Array(text.utf8)
    var index = 0, commands: [[String]] = [], words: [String] = []
    func isWhitespace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
    func skipWhitespace() {
      while index < input.count, isWhitespace(input[index]) { index += 1 }
    }
    func flushCommand() {
      let command = normalized(words)
      if !command.isEmpty { commands.append(command) }
      words = []
    }
    func readHex(_ length: Int) -> UInt32? {
      guard index + length <= input.count else { return nil }
      let digits = input[index..<(index + length)]
      guard digits.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
            let value = UInt32(String(decoding: digits, as: UTF8.self), radix: 16) else { return nil }
      index += length
      return value
    }
    func readWord() -> String? {
      var value: [UInt8] = []
      let quote = input[index]
      if quote == 34 {
        index += 1
        let escapes: [UInt8: UInt8] = [34: 34, 92: 92, 47: 47, 98: 8, 102: 12,
                                     110: 10, 114: 13, 116: 9, 101: 27, 39: 39]
        while index < input.count {
          let byte = input[index]; index += 1
          if byte == 34 { return String(decoding: value, as: UTF8.self) }
          guard byte == 92 else { value.append(byte); continue }
          guard index < input.count else { return nil }
          let escape = input[index]; index += 1
          if let replacement = escapes[escape] { value.append(replacement) }
          else if escape == 120, let byte = readHex(2) { value.append(UInt8(byte)) }
          else if escape == 117, var scalar = readHex(4) {
            if (0xD800...0xDBFF).contains(scalar) {
              guard index + 2 <= input.count, input[index] == 92, input[index + 1] == 117 else { return nil }
              index += 2
              guard let low = readHex(4), (0xDC00...0xDFFF).contains(low) else { return nil }
              scalar = 0x10000 + ((scalar - 0xD800) << 10) + low - 0xDC00
            }
            guard let decoded = UnicodeScalar(scalar) else { return nil }
            value.append(contentsOf: String(decoded).utf8)
          } else { return nil }
        }
        return nil
      }
      if quote == 39 || quote == 96 {
        index += 1
        let delimiter: UInt8
        if quote == 96 {
          guard index < input.count else { return nil }
          delimiter = input[index]; index += 1
        } else { delimiter = quote }
        while index < input.count {
          if input[index] == delimiter,
             quote == 39 || (index + 1 < input.count && input[index + 1] == 96) {
            index += quote == 39 ? 1 : 2
            return String(decoding: value, as: UTF8.self)
          }
          value.append(input[index]); index += 1
        }
        return nil
      }
      let start = index
      while index < input.count, !isWhitespace(input[index]), input[index] != 35, input[index] != 59 { index += 1 }
      return String(decoding: input[start..<index], as: UTF8.self)
    }
    while index < input.count {
      skipWhitespace()
      guard index < input.count, input[index] != 35 else { break }
      if input[index] == 59 {
        guard !words.isEmpty else { return commands }
        flushCommand(); index += 1; skipWhitespace()
        // mpv ignores an empty trailing command and the remaining text after it.
        if index == input.count || input[index] == 35 || input[index] == 59 { break }
      } else {
        // A malformed quote invalidates the whole native command list.
        guard let word = readWord() else { return [] }
        words.append(word)
      }
    }
    flushCommand()
    return commands
  }

  static func explicitlySeeks(_ words: [String]) -> Bool {
    let words = normalized(words)
    guard let command = words.first else { return false }
    switch command {
    case "seek", "frame-back-step", "sub-seek": return true
    case "revert-seek":
      let flags = words.dropFirst().first?.split(separator: "+") ?? []
      return !flags.contains("mark") && !flags.contains("mark-permanent")
    case "frame-step":
      let frames = words.count > 1 ? Int(words[1]) : 1
      guard let frames, frames != 0 else { return false }
      return frames < 0 || (words.count > 2 && words[2] == "seek")
    default:
      guard let (property, _) = propertyMutation(words) else { return false }
      return ["time-pos", "playback-time", "percent-pos", "chapter"].contains(property)
    }
  }

  static func propertyMutation(_ words: [String]) -> (String, OSDFeedbackValue?)? {
    let words = normalized(words)
    guard words.count >= 2 else { return nil }
    switch words[0] {
    case "set", "set-property":
      return (words[1], words.count >= 3 ? OSDFeedbackValue(words[2]) : nil)
    case "cycle-values":
      let propertyIndex = words[1] == "!reverse" ? 2 : 1
      return words.count > propertyIndex ? (words[propertyIndex], nil) : nil
    case "add", "multiply", "cycle", "change-list":
      return (words[1], nil)
    default: return nil
    }
  }

  static func changesVideoGeometry(property: String) -> Bool {
    let property = OSDFeedbackOrigins.propertyKey(property)
    let name = property.split(separator: "/").first.map(String.init) ?? property
    return ["vid", "video", "edition", "vf", "lavfi-complex", "video-aspect", "video-aspect-override",
      "video-aspect-method", "video-rotate", "video-crop", "panscan", "video-zoom", "video-pan-x",
      "video-pan-y", "video-scale-x", "video-scale-y", "video-align-x", "video-align-y", "video-unscaled",
      "video-recenter", "video-margin-ratio-left", "video-margin-ratio-right", "video-margin-ratio-top",
      "video-margin-ratio-bottom", "playlist-pos", "playlist-pos-1", "playlist-current-pos"].contains(name) ||
      property.contains("$")
  }

  /// A Crop/Delogo editor owns the source geometry until its transition finishes.
  /// Appending media and unrelated playback controls leave that ownership intact.
  static func changesVideoGeometry(_ words: [String], playlistIndex: Int) -> Bool {
    let words = normalized(words)
    guard let command = words.first else { return false }
    if let (property, _) = propertyMutation(words) { return changesVideoGeometry(property: property) }
    switch command {
    case "del":
      return words.count > 1 && changesVideoGeometry(property: words[1])
    case "vf", "vf-command", "video-add", "video-remove", "video-reload", "playlist-next", "playlist-prev",
         "playlist-next-playlist", "playlist-prev-playlist", "playlist-play-index", "apply-profile", "load-config-file":
      return true
    case "loadfile", "loadlist":
      let mode = words.count > 2 ? words[2] : "replace"
      return !["append", "append-play", "insert-next", "insert-next-play", "insert-at", "insert-at-play"].contains(mode)
    case "playlist-remove":
      guard words.count > 1, let index = Int(words[1]) else { return true }
      return index == playlistIndex
    default:
      return false
    }
  }
}


fileprivate func toPercent(_ value: Double, _ bound: Double) -> Double {
  return (value + bound).clamped(to: 0...(bound * 2)) / (bound * 2)
}


fileprivate func makeAttributedString(
  part1: String,
  fontSize part1FontSize: CGFloat,
  isSecondary part1IsSecondary: Bool,
  part2: String,
  fontSize part2FontSize: CGFloat,
  isSecondary part2IsSecondary: Bool,
) -> NSAttributedString? {
  let attrString = NSMutableAttributedString()
  attrString.append(NSAttributedString(string: part1, attributes: [
    .font: NSFont.monospacedDigitSystemFont(ofSize: part1FontSize, weight: .regular),
    .foregroundColor: part1IsSecondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
  ]))
  attrString.append(NSAttributedString(string: part2, attributes: [
    .font: NSFont.monospacedDigitSystemFont(ofSize: part2FontSize, weight: .regular),
    .foregroundColor: part2IsSecondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
  ]))
  return attrString
}


fileprivate func defaultAttributedString(_ string: String, separator: Character, fontSize: CGFloat, smallFontSize: CGFloat) -> NSAttributedString? {
  let parts = string.split(separator: separator, maxSplits: 1)
  if parts.count == 2 {
    return makeAttributedString(
      part1: String(parts[0]), fontSize: smallFontSize, isSecondary: true,
      part2: String(parts[1]), fontSize: fontSize, isSecondary: false,
    )
  }
  return nil
}


enum OSDType {
  case normal
  case withText(String)
  case withProgress(Double)
  case withPosition(Double)
  case withLeftToRightText(String)
}

enum OSDMessage {

  case fileStart(String)

  case pause
  case resume
  case seek(String, String, Double)  // current, total, percentage
  case showTime(Double) // percentage
  case volume(Double)
  case speed(Double)
  case aspect(String)
  case crop(String)
  case rotate(Int)
  case deinterlace(Bool)
  case hwdec(Bool)
  case audioDelay(Double)
  case subDelay(Double)
  case subScale(Double)
  case subHidden
  case subVisible
  case secondSubDelay(Double)
  case secondSubHidden
  case secondSubPos(Double)
  case secondSubVisible
  case subPos(Double)
  case mute
  case unMute
  case screenshot
  case abLoop(PlaybackInfo.LoopStatus)
  case abLoopUpdate(PlaybackInfo.LoopStatus, String)
  case stop
  case chapter(String)
  case track(MPVTrack, position: Int? = nil)
  case addToPlaylist(Int)
  case clearPlaylist

  case contrast(Int)
  case hue(Int)
  case saturation(Int)
  case brightness(Int)
  case gamma(Int)

  case addFilter(String)
  case removeFilter

  case startFindingSub(String)  // sub source
  case foundSub(Int)
  case downloadingSub(Int, String)  // download count, sub source
  case downloadedSub(String)  // filename
  case savedSub
  case cannotLogin
  case fileError
  case networkError
  case canceled
  case cannotConnect
  case timedOut
  case onlineSubQuotaExceeded(String?)

  case fileLoop
  case playlistLoop
  case noLoop

  case custom(String)
  case customWithDetail(String, String)

  var isSettingFeedback: Bool {
    switch self {
    case .volume, .speed, .aspect, .crop, .rotate, .deinterlace, .hwdec,
         .audioDelay, .subDelay, .subScale, .subHidden, .subVisible,
         .secondSubDelay, .secondSubHidden, .secondSubPos, .secondSubVisible, .subPos,
         .mute, .unMute, .track, .contrast, .hue, .saturation, .brightness, .gamma,
         .fileLoop, .playlistLoop, .noLoop, .clearPlaylist, .addFilter, .removeFilter:
      return true
    default: return false
    }
  }

  /// `True` if this OSD message has been suppressed by the user, otherwise `false`.
  ///
  /// Through settings on the `UI` tab a user can choose to not have certain OSD messages shown. This is useful in certain
  /// applications such as looping in a kiosk or scrubbing through a video without distractions.
  var isDisabled: Bool {
    switch self {
    case .fileStart: return Preference.bool(for: .disableOSDFileStartMsg)
    case .pause: return Preference.bool(for: .disableOSDPauseResumeMsgs)
    case .resume: return Preference.bool(for: .disableOSDPauseResumeMsgs)
    case .seek: return Preference.bool(for: .disableOSDSeekMsg)
    case .speed: return Preference.bool(for: .disableOSDSpeedMsg)
    default: return false
    }
  }

  /// `True` if this message must always be shown, otherwise `false`.
  ///
  /// A user may disable the OSD by unchecking the `Enable OSD` setting found on the `UI` tab in the `On Screen Display`
  /// section of IINA's settings. Or they may check the `Use mpv's OSD` setting found on the `Advanced` tab which implicitly
  /// disables IINA's OSD. _However_ not all OSD messages are optional notifications. The `Find Online Subtitles` feature
  /// uses the OSD for its user interface. These messages must still be displayed when the OSD is disabled.
  var alwaysEnabled: Bool {
    switch self {
    case .canceled: fallthrough
    case .cannotConnect: fallthrough
    case .cannotLogin: fallthrough
    case .downloadedSub: fallthrough
    case .fileError: fallthrough
    case .foundSub: fallthrough
    case .networkError: fallthrough
    case .onlineSubQuotaExceeded: fallthrough
    case .savedSub: fallthrough
    case .startFindingSub: fallthrough
    case .timedOut:
      return true
    default: return false
    }
  }

  func titleAndType() -> (String, OSDType) {
    switch self {
    case .fileStart(let filename):
      return (filename, .normal)

    case .pause:
      return (NSLocalizedString("osd.pause", comment: "Pause"),
              .withLeftToRightText("{{position}} / {{duration}}"))

    case .resume:
      return (NSLocalizedString("osd.resume", comment: "Resume"),
              .withLeftToRightText("{{position}} / {{duration}}"))

    case .seek(let current, let total, let percent):
      return (current + " / " + total, .withPosition(percent))

    case .showTime(let percent):
      return ("{{precisePosition}} / {{preciseDuration}}", .withPosition(percent))

    case .volume(let value):
      let text = String(format: NSLocalizedString("osd.volume", comment: "Volume: %@"), String(format: "%.0f", value))
      return (text, .withProgress(value / Preference.double(for: .maxVolume)))

    case .speed(let value):
      return (
        String(format: NSLocalizedString("osd.speed", comment: "Speed: %@x"), value.groupedStringUpTo6Decimals),
        .normal
      )

    case .aspect(var value):
      if value == "Default" {
        value = Constants.String.default
      }
      return (
        String(format: NSLocalizedString("osd.aspect", comment: "Aspect Ratio: %@"), value),
        .normal
      )

    case .crop(var value):
      if value == "None" {
        value = Constants.String.none
      }
      return (
        String(format: NSLocalizedString("osd.crop", comment: "Crop: %@"), value),
        .normal
      )

    case .rotate(let value):
      return (
        String(format: NSLocalizedString("osd.rotate", comment: "Rotate: %i°"), value),
        .normal
      )

    case .deinterlace(let enabled):
      return (
        String(format: NSLocalizedString("osd.deinterlace", comment: "Deinterlace: %@"), enabled ? NSLocalizedString("general.on", comment: "On") : NSLocalizedString("general.off", comment: "Off")),
        .normal
      )

    case .hwdec(let enabled):
      return (
        String(format: NSLocalizedString("osd.hwdec", comment: "Hardware Decoding: %@"), enabled ? NSLocalizedString("general.on", comment: "On") : NSLocalizedString("general.off", comment: "Off")),
        .normal
      )

    case .audioDelay(let value):
      if value == 0 {
        return (
          NSLocalizedString("osd.audio_delay.nodelay", comment: "Audio Delay: No Delay"),
          .withProgress(0.5)
        )
      } else {
        let valueStr = abs(value).groupedStringUpTo6Decimals
        let text: String
        if value > 0 {
          text = String(format: NSLocalizedString("osd.audio_delay.later", comment: "Audio Delay: %@s Later"), valueStr)
        } else {
          text = String(format: NSLocalizedString("osd.audio_delay.earlier", comment: "Audio Delay: %@s Earlier"), valueStr)
        }
        return (text, .withProgress(toPercent(value, 10)))
      }

    case .secondSubDelay(let value):
      if value == 0 {
        return (
          NSLocalizedString("osd.sub_second_delay.nodelay", comment: "Secondary Subtitle Delay: No Delay"),
          .withProgress(0.5)
        )
      } else {
        let valueStr = abs(value).groupedStringUpTo6Decimals
        let text: String
        if value > 0 {
          text = String(format: NSLocalizedString("osd.sub_second_delay.later", comment: "Secondary Subtitle Delay: %@s Later"), valueStr)
        } else {
          text = String(format: NSLocalizedString("osd.sub_second_delay.earlier", comment: "Secondary Subtitle Delay: %@s Earlier"), valueStr)
        }
        return (text, .withProgress(toPercent(value, 10)))
      }

    case .secondSubPos(let value):
      let text = String(format: NSLocalizedString("osd.sub_second_pos", comment: "Secondary Subtitle Position: %@"), value.groupedStringUpTo6Decimals)
      return (text, .withProgress(value / 100))

    case .subDelay(let value):
      if value == 0 {
        return (
          NSLocalizedString("osd.sub_delay.nodelay", comment: "Subtitle Delay: No Delay"),
          .withProgress(0.5)
        )
      } else {
        let valueStr = abs(value).groupedStringUpTo6Decimals
        let text: String
        if value > 0 {
          text = String(format: NSLocalizedString("osd.sub_delay.later", comment: "Subtitle Delay: %@s Later"), valueStr)
        } else {
          text = String(format: NSLocalizedString("osd.sub_delay.earlier", comment: "Subtitle Delay: %@s Earlier"), valueStr)
        }
        return (text, .withProgress(toPercent(value, 10)))
      }

    case .subPos(let value):
      let text = String(format: NSLocalizedString("osd.subtitle_pos", comment: "Subtitle Position: %@"), value.groupedStringUpTo6Decimals)
      return (text, .withProgress(value / 100))

    case .subHidden:
      return (NSLocalizedString("osd.sub_hidden", comment: "Subtitles Hidden"), .normal)

    case .subVisible:
      return (NSLocalizedString("osd.sub_visible", comment: "Subtitles Visible"), .normal)

    case .secondSubHidden:
      return (NSLocalizedString("osd.sub_second_hidden", comment: "Second Subtitles Hidden"), .normal)

    case .secondSubVisible:
      return (NSLocalizedString("osd.sub_second_visible", comment: "Second Subtitles Visible"), .normal)

    case .mute:
      return (NSLocalizedString("osd.mute", comment: "Mute"), .normal)

    case .unMute:
      return (NSLocalizedString("osd.unmute", comment: "Unmute"), .normal)

    case .screenshot:
      return (NSLocalizedString("osd.screenshot", comment: "Screenshot Captured"), .normal)

    case .abLoop(let value):
      // The A-B loop command was invoked.
      switch (value) {
      case .cleared:
        return (NSLocalizedString("osd.abloop.clear", comment: "AB-Loop: Cleared"), .normal)
      case .aSet:
        return (NSLocalizedString("osd.abloop.a", comment: "AB-Loop: A"),
                .withLeftToRightText("{{position}} / {{duration}}"))
      case .bSet:
        return (NSLocalizedString("osd.abloop.b", comment: "AB-Loop: B"),
                .withLeftToRightText("{{position}} / {{duration}}"))
      }

    case .abLoopUpdate(let value, let position):
      // One of the A-B loop points has been updated to the given position.
      switch (value) {
      case .cleared:
        Logger.fatal("Attempt to display invalid OSD message, type: .abLoopUpdate value: .cleared position \(position)")
      case .aSet:
        return (NSLocalizedString("osd.abloop.a", comment: "AB-Loop: A"),
                .withLeftToRightText("\(position) / {{duration}}"))
      case .bSet:
        return (NSLocalizedString("osd.abloop.b", comment: "AB-Loop: B"),
                .withLeftToRightText("\(position) / {{duration}}"))
      }

    case .stop:
      return (NSLocalizedString("osd.stop", comment: "Stop"), .normal)

    case .chapter(let name):
      return (
        String(format: NSLocalizedString("osd.chapter", comment: "Chapter: %@"), name),
        .withLeftToRightText("({{currChapter}}/{{chapterCount}}) {{position}} / {{duration}}")
      )

    case .track(let track, let position):
      let keySuffix: String
      switch track.type {
      case .video: keySuffix = "video"
      case .audio: keySuffix = "audio"
      case .sub: keySuffix = "sub"
      case .secondSub:
        // This enum constant is only used for setting the secondary subtitle. No track should use
        // this type. This is an internal error.
        Logger.log("Invalid subtitle track type: secondSub", level: .error)
        keySuffix = "sub"
      }
      let trackTypeStr = String(format: NSLocalizedString("track." + keySuffix,
        comment: "Kind of track (Audio, Video, Subtitle)"))
      let title = position.map { "#\($0) \(track.readableString())" } ?? track.readableTitle
      return (trackTypeStr + ": " + title, .normal)

    case .subScale(let value):
      let text = String(format: NSLocalizedString("osd.subtitle_scale", comment: "Subtitle Scale: %@x"), value.groupedStringUpTo6Decimals)
      return (text, .normal)

    case .addToPlaylist(let count):
      return (
        String(format: NSLocalizedString("osd.add_to_playlist", comment: "Added %i Files to Playlist"), count),
        .normal
      )

    case .clearPlaylist:
      return (NSLocalizedString("osd.clear_playlist", comment: "Cleared Playlist"), .normal)

    case .contrast(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.contrast", comment: "Contrast: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .gamma(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.gamma", comment: "Grama: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .hue(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.hue", comment: "Hue: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .saturation(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.saturation", comment: "Saturation: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .brightness(let value):
      return (
        String(format: NSLocalizedString("osd.video_eq.brightness", comment: "Brightness: %i"), value),
        .withProgress(toPercent(Double(value), 100))
      )

    case .addFilter(let name):
      return (
        String(format: NSLocalizedString("osd.filter_added", comment: "Added Filter: %@"), name),
        .normal
      )

    case .removeFilter:
      return (
        NSLocalizedString("osd.filter_removed", comment: "Removed Filter"),
        .normal
      )

    case .startFindingSub(let source):
      return (
        NSLocalizedString("osd.find_online_sub", comment: "Finding online subtitles..."),
        .withText(NSLocalizedString("osd.find_online_sub.source", comment: "from") + " " + source)
      )

    case .foundSub(let count):
      let str = count == 0 ?
        NSLocalizedString("osd.sub_not_found", comment: "No subtitles found.") :
        String(format: NSLocalizedString("osd.sub_found", comment: "%d subtitle(s) found."), count)
      return (str, .normal)

    case .downloadingSub(let count, let source):
      let str = String(format: NSLocalizedString("osd.sub_downloading", comment: "Downloading %d subtitles"), count)
      return (str, .withText(NSLocalizedString("osd.find_online_sub.source", comment: "from") + " " + source))

    case .downloadedSub(let filename):
      return (
        NSLocalizedString("osd.sub_downloaded", comment: "Subtitle downloaded"),
        .withText(filename)
      )

    case .savedSub:
      return (
        NSLocalizedString("osd.sub_saved", comment: "Subtitle saved"),
        .normal
      )

    case .networkError:
      return (
        NSLocalizedString("osd.network_error", comment: "Network error"),
        .normal
      )

    case .fileError:
      return (
        NSLocalizedString("osd.file_error", comment: "Error reading file"),
        .normal
      )

    case .cannotLogin:
      return (
        NSLocalizedString("osd.cannot_login", comment: "Cannot login"),
        .normal
      )

    case .canceled:
      return (
        NSLocalizedString("osd.canceled", comment: "Canceled"),
        .normal
      )

    case .cannotConnect:
      return (
        NSLocalizedString("osd.cannot_connect", comment: "Cannot connect"),
        .normal
      )

    case .timedOut:
      return (
        NSLocalizedString("osd.timed_out", comment: "Timed out"),
        .normal
      )

    case .onlineSubQuotaExceeded(let resetTime):
      let detail: String
      if let resetTime, !resetTime.isEmpty {
        detail = String(format: NSLocalizedString("osd.sub_quota_exceeded.detail", comment: "Try again after %@"), resetTime)
      } else {
        detail = NSLocalizedString("osd.sub_quota_exceeded.detail_unknown", comment: "Try again later")
      }
      return (
        NSLocalizedString("osd.sub_quota_exceeded", comment: "Subtitle download limit reached"),
        .withText(detail)
      )

    case .fileLoop:
      return (
        NSLocalizedString("osd.file_loop", comment: "Enable file looping"),
          .normal
      )

    case .playlistLoop:
      return (
        NSLocalizedString("osd.playlist_loop", comment: "Enable playlist looping"), 
          .normal
      )

    case .noLoop:
      return (
        NSLocalizedString("osd.no_loop", comment: "Disable loop"),
          .normal
      )

    case .custom(let message):
      return (message, .normal)

    case .customWithDetail(let message, let detail):
      return (message, .withText(detail))
    }
  }

  func attributedTitle(_ label: String, fontSize: CGFloat, smallFontSize: CGFloat) -> NSAttributedString? {
    switch self {
    case .seek(let current, let total, _):
      return makeAttributedString(
        part1: current, fontSize: fontSize, isSecondary: false,
        part2: " / " + total, fontSize: smallFontSize, isSecondary: true
      )
    case .volume, .speed, .aspect, .crop, .rotate, .deinterlace,
        .audioDelay, .subPos, .subDelay, .secondSubPos, .secondSubDelay,
        .brightness, .contrast, .saturation, .gamma, .hue,
        .track, .chapter,
        .hwdec, .abLoop, .abLoopUpdate:
      return defaultAttributedString(label, separator: ":", fontSize: fontSize, smallFontSize: smallFontSize)
    default:
      return nil
    }
  }

  func image() -> NSImage? {
    // icons don't look great in OSDs
    return nil

//    switch self {
//    case .volume(let val):
//      let intVal = (Int(val / 30) + 1).clamped(to: 1...3)
//      return .sf("speaker.wave.\(intVal).fill")
//    case .mute: return .sf("speaker.slash.fill")
//    case .unMute: return .sf("speaker.fill")
//    case .speed: return .sf("chevron.forward.dotted.chevron.forward")
//    case .pause: return .sf("pause.fill")
//    case .resume: return .sf("play.fill")
//    case .stop: return .sf("stop.fill")
//    case .abLoop, .abLoopUpdate: return .sf("arrow.2.squarepath")
//    case .playlistLoop: return .sf("repeat")
//    case .fileLoop: return .sf("repeat.1")
//    case .noLoop: return .sf("repeat.badge.xmark", "repeat.badge.xmark.circle.fill")
//    case .audioDelay, .subDelay, .secondSubDelay:
//      return .sf("clock.arrow.trianglehead.counterclockwise.rotate.90")
//    default:
//      return nil
//    }
  }
}
