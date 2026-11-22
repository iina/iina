// Copyright © 2026 IINA contributors. Licensed under GPLv3.

import Foundation

struct SharePlayMedia: Codable, Equatable {
  let id: UUID
  let title: String
  let duration: Double

  var isValid: Bool {
    !title.isEmpty && title.count <= 512 && duration.isFinite && duration > 0
  }

  func matches(duration other: Double) -> Bool {
    isValid && other.isFinite && abs(duration - other) <= 1
  }
}

struct SharePlaySnapshot {
  var url: URL?
  var position: Double
  var duration: Double
  var speed: Double
  var paused: Bool
  var buffering: Bool
  var loaded: Bool
  var seekable: Bool
}

enum SharePlaySuspension: String, Hashable {
  case buffering, system, automation
}

enum SharePlayControl: Equatable {
  case pause(Bool), speed(Double), seek(Double), chapter(Int), blocked, suspend, passthrough
}

enum SharePlayCommandRouter {
  static func command(_ words: [String], snapshot: SharePlaySnapshot) -> SharePlayControl {
    var words = words
    while let first = words.first, ["osd-auto", "osd-bar", "osd-msg", "osd-msg-bar", "no-osd", "exact", "repeatable", "async", "sync", "raw", "expand-properties"].contains(first) {
      words.removeFirst()
    }
    guard let command = words.first else { return .passthrough }
    if command == "cycle", words.count == 2, words[1] == "pause" { return .pause(!snapshot.paused) }
    if ["set", "set_property", "add", "multiply", "cycle"].contains(command), words.count >= 2 {
      let property = words[1]
      if property == "pause" {
        guard command == "set" || command == "set_property", words.count == 3 else { return .blocked }
        if ["yes", "true", "1"].contains(words[2]) { return .pause(true) }
        if ["no", "false", "0"].contains(words[2]) { return .pause(false) }
        return .blocked
      }
      if ["speed", "time-pos", "playback-time", "percent-pos", "chapter"].contains(property) {
        guard words.count == 3, let number = Double(words[2]), number.isFinite else { return .blocked }
        let current = property == "speed" ? snapshot.speed : snapshot.position
        let value: Double
        switch command {
        case "set", "set_property": value = number
        case "add": value = current + number
        case "multiply": value = current * number
        default: return .blocked
        }
        if property == "speed" { return value > 0 && value <= 100 ? .speed(value) : .blocked }
        if property == "chapter" {
          guard command == "set" || command == "set_property", number >= 0, number < Double(Int.max), number.rounded() == number else { return .blocked }
          return .chapter(Int(number))
        }
        if property == "percent-pos" {
          guard command == "set" || command == "set_property" else { return .blocked }
          return .seek(snapshot.duration * number / 100)
        }
        return value.isFinite ? .seek(value) : .blocked
      }
      if ["playlist-pos", "loop-file", "loop-playlist", "ab-loop-a", "ab-loop-b", "keep-open"].contains(property) { return .blocked }
    }
    if command == "seek" {
      guard (2...3).contains(words.count), let number = Double(words[1]), number.isFinite else { return .blocked }
      let flags = words.count == 3 ? Set(words[2].split(separator: "+").map(String.init)) : ["relative"]
      guard flags.isSubset(of: ["relative", "absolute", "absolute-percent", "relative-percent", "exact", "keyframes"]),
            flags.intersection(["relative", "absolute", "absolute-percent", "relative-percent"]).count <= 1 else { return .blocked }
      if flags.contains("absolute-percent") { return .seek(snapshot.duration * number / 100) }
      if flags.contains("relative-percent") { return .seek(snapshot.position + snapshot.duration * number / 100) }
      return .seek(flags.contains("absolute") ? number : snapshot.position + number)
    }
    if ["ab-loop", "frame-step", "frame-back-step", "playlist-next", "playlist-prev", "playlist-play-index", "loadfile", "loadlist", "revert-seek", "sub-seek", "stop"].contains(command) { return .blocked }
    if command.hasPrefix("script-") || command == "keypress" || command == "keydown" || command == "keyup" { return .suspend }
    if words.contains(where: { ["pause", "speed", "time-pos", "playback-time", "percent-pos", "chapter"].contains($0) }) { return .blocked }
    return .passthrough
  }

  static func raw(_ text: String, snapshot: SharePlaySnapshot) -> SharePlayControl {
    // A compound command is not safe to partially coordinate. Do not implement an mpv interpreter.
    if text.contains(";") || text.contains("\n") || text.contains("${") { return .blocked }
    return command(text.split(whereSeparator: { $0.isWhitespace }).map(String.init), snapshot: snapshot)
  }
}

enum SharePlayTiming {
  static func position(itemTime: Double, hostTime: Double, rate: Double, now: Double, duration: Double) -> Double? {
    guard [itemTime, hostTime, rate, now, duration].allSatisfy({ $0.isFinite }), duration > 0, rate > 0, rate <= 100 else { return nil }
    return min(duration, max(0, itemTime + (now - hostTime) * rate))
  }
}
