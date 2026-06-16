//
//  SimpleTime.swift
//  iina
//
//  Created by lhc on 25/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class VideoTime {
  static let infinite = VideoTime(999, 0, 0)
  static let zero = VideoTime(0)

  var second: Double

  var stringRepresentation: String {
    stringRepresentationWithPrecision(0)
  }

  /// Return this time as a string with the given precision.
  ///
  /// The value of the `precision` parameter controls the number of fractional digits in the seconds portion of the returned time
  /// string and is interpreted as follows:
  /// | Value | Precision |
  /// | --- | --- |
  /// | 0 | 1 second  |
  /// | 1 | 100 milliseconds |
  /// | 2 | 10 milliseconds |
  /// | 3 | 1 millisecond |
  /// - Important: The time is also displayed in the macOS
  ///     [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
  ///     Now Playing module. Now Playing uses 1 second precision. When the IINA OSC is also configured to use 1 second precision
  ///     it is important that the times displayed match. This means IINA **must** use the same rounding method that Now Playing
  ///     uses, [rounding half down](https://en.wikipedia.org/wiki/Rounding#Rounding_half_down).  IINA must
  ///     round 0.5 to 0 and 0.51 to 1.
  /// - Parameter precision: Precision to use for the seconds portion of the returned string.
  /// - Returns: A string containing the time in the format "hh:mm:ss.sss", with the number of digits in the fraction controlled by the
  ///     precision parameter.
  func stringRepresentationWithPrecision(_ precision: UInt) -> String {
    if self == Constants.Time.infinite {
      return "End"
    }

    // Whether to include fractional seconds.
    let precise = precision >= 1 && precision <= 3

    // When rounding to seconds IINA must do so by rounding half down in order to match up with the
    // time displayed in the Control Center Now Playing module. At this time the Swift rounded
    // method does not support such a rounding rule.
    let rounded = precise ? Int(second) : Int(second.roundedHalfDown())

    let h = rounded / 3600
    let remaining = rounded % 3600
    let m = remaining / 60

    let h_ = h > 0 ? "\(h):" : ""
    let m_ = m < 10 ? "0\(m)" : "\(m)"
    let s_: String
    if precise {
      s_ = String(format: "%0\(precision + 3).\(precision)f", fmod(second, 60))
    } else {
      let s = remaining % 60
      s_ = s < 10 ? "0\(s)" : "\(s)"
    }

    return h_ + m_ + ":" + s_
  }

  convenience init?(_ format: String) {
    let split = Array(format.split(separator: ":").reversed())

    let hour: Int? = split.count > 2 ? Int(split[2]) : nil
    let minute: Int? = split.count > 1 ? Int(split[1]) : nil
    let second: Double? = !split.isEmpty ? Double(split[0]) : nil

    if hour == nil && minute == nil && second == nil {
      return nil
    }

    self.init(hour ?? 0, minute ?? 0, second ?? 0.0)
  }

  init(_ second: Double) {
    self.second = second

  }

  init(_ hour: Int, _ minute: Int, _ second: Double) {
    self.second = Double(hour * 3600 + minute * 60) + second
  }

  /** whether self in [min, max) */
  func between(_ min: VideoTime, _ max: VideoTime) -> Bool {
    return self >= min && self < max
  }

}

extension VideoTime: Comparable { }

func <(lhs: VideoTime, rhs: VideoTime) -> Bool {
  // ignore additional digits and compare the time in milliseconds
  return Int(lhs.second * 1000) < Int(rhs.second * 1000)
}

func ==(lhs: VideoTime, rhs: VideoTime) -> Bool {
  // ignore additional digits and compare the time in milliseconds
  return Int(lhs.second * 1000) == Int(rhs.second * 1000)
}

func *(lhs: VideoTime, rhs: Double) -> VideoTime {
  return VideoTime(lhs.second * rhs)
}

func /(lhs: VideoTime?, rhs: VideoTime?) -> Double? {
  if let lhs = lhs, let rhs = rhs {
    return lhs.second / rhs.second
  } else {
    return nil
  }
}

func -(lhs: VideoTime, rhs: VideoTime) -> VideoTime {
  return VideoTime(lhs.second - rhs.second)
}

struct SMPTETimecode {
  private let startFrame: Int
  private let fps: Double
  private let nominalFramesPerSecond: Int
  private let separator: Character

  private var isDropFrame: Bool {
    (separator == ";" || separator == ",") && nominalFramesPerSecond % 30 == 0
  }

  init?(_ string: String, fps: Double, at position: VideoTime = .zero) {
    guard fps > 0, fps.isFinite else { return nil }

    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let separators = trimmed.filter { $0 == ":" || $0 == ";" || $0 == "." || $0 == "," }
    guard separators.count == 3, let separator = separators.last else { return nil }

    let parts = trimmed.split(whereSeparator: { $0 == ":" || $0 == ";" || $0 == "." || $0 == "," })
    guard parts.count == 4,
          let hours = Int(parts[0]),
          let minutes = Int(parts[1]),
          let seconds = Int(parts[2]),
          let frames = Int(parts[3]) else {
      return nil
    }

    let nominalFramesPerSecond = Int(fps.rounded())
    guard nominalFramesPerSecond > 0,
          (0..<60).contains(minutes),
          (0..<60).contains(seconds),
          (0..<nominalFramesPerSecond).contains(frames) else {
      return nil
    }

    self.fps = fps
    self.nominalFramesPerSecond = nominalFramesPerSecond
    self.separator = separator == "," ? ";" : (separator == "." ? ":" : separator)
    let frame = SMPTETimecode.frameNumber(hours: hours,
                                          minutes: minutes,
                                          seconds: seconds,
                                          frames: frames,
                                          nominalFramesPerSecond: nominalFramesPerSecond,
                                          dropFrame: separator == ";" || separator == ",")
    startFrame = frame - max(0, Int((position.second * fps).rounded(.down)))
  }

  func stringValue(at position: VideoTime) -> String {
    let elapsedFrames = frameCount(for: position)
    return SMPTETimecode.stringValue(for: startFrame + elapsedFrames,
                                     nominalFramesPerSecond: nominalFramesPerSecond,
                                     separator: separator,
                                     dropFrame: isDropFrame)
  }

  func durationStringValue(for duration: VideoTime) -> String {
    SMPTETimecode.stringValue(for: frameCount(for: duration),
                              nominalFramesPerSecond: nominalFramesPerSecond,
                              separator: ":",
                              dropFrame: false)
  }

  private func frameCount(for time: VideoTime) -> Int {
    max(0, Int((time.second * fps).rounded(.down)))
  }

  private static func frameNumber(hours: Int, minutes: Int, seconds: Int, frames: Int,
                                  nominalFramesPerSecond: Int, dropFrame: Bool) -> Int {
    let totalMinutes = hours * 60 + minutes
    let totalFrames = ((hours * 3600) + (minutes * 60) + seconds) * nominalFramesPerSecond + frames
    guard dropFrame, nominalFramesPerSecond % 30 == 0 else { return totalFrames }

    let droppedFrames = 2 * (nominalFramesPerSecond / 30)
    return totalFrames - droppedFrames * (totalMinutes - totalMinutes / 10)
  }

  private static func stringValue(for frameNumber: Int, nominalFramesPerSecond: Int,
                                  separator: Character, dropFrame: Bool) -> String {
    var frameNumber = frameNumber
    let framesPerHour = nominalFramesPerSecond * 60 * 60
    let framesPer24Hours = framesPerHour * 24
    frameNumber = ((frameNumber % framesPer24Hours) + framesPer24Hours) % framesPer24Hours

    if dropFrame, nominalFramesPerSecond % 30 == 0 {
      let droppedFrames = 2 * (nominalFramesPerSecond / 30)
      let framesPer10Minutes = nominalFramesPerSecond * 60 * 10 - droppedFrames * 9
      let framesPerMinute = nominalFramesPerSecond * 60 - droppedFrames
      let tenMinuteChunks = frameNumber / framesPer10Minutes
      let remainingFrames = frameNumber % framesPer10Minutes
      frameNumber += droppedFrames * 9 * tenMinuteChunks
      if remainingFrames >= droppedFrames {
        frameNumber += droppedFrames * ((remainingFrames - droppedFrames) / framesPerMinute)
      }
    }

    let hours = frameNumber / framesPerHour
    let minutes = (frameNumber / (nominalFramesPerSecond * 60)) % 60
    let seconds = (frameNumber / nominalFramesPerSecond) % 60
    let frames = frameNumber % nominalFramesPerSecond

    return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, String(separator), frames)
  }
}
