//
//  FullLength.swift
//  iina
//
//  The full length of a fragmented MP4 opened from its index.
//

import Foundation

/// A fragmented MP4 that ends in an index is opened from that index, so that opening it does not take
/// longer the longer the file is. The duration `mpv` reports for such a file covers only the fragments
/// `mpv` has read, so once playback has started the full length is worked out off the main thread and
/// replaces it.
enum FullLength {
  /// The value of `mpv`'s `demuxer-lavf-o` option that opens such a file from its index.
  static let demuxerOption = "use_mfra_for=pts"

  /// The duration to show once the full length of a file has been worked out.
  /// - Parameters:
  ///   - shown: The duration shown for the file.
  ///   - fullLength: The full length worked out, negative when the file was not opened from an index.
  /// - Returns: The full length when it is longer than the duration shown, otherwise `nil`.
  static func duration(shown: Double?, fullLength: Double) -> Double? {
    guard fullLength > 0 else { return nil }
    if let shown, shown >= fullLength { return nil }
    return fullLength
  }

  /// The time a seek to the given percentage of a file's full length lands at, kept short of the end so
  /// that the seek does not end the file.
  static func seekTime(percent: Double, fullLength: Double) -> Double {
    fullLength * percent.clamped(to: 0..<100) / 100
  }

  /// The arguments of the seek command for a seek to the given percentage of a file.
  /// - Parameters:
  ///   - percent: The percentage of the file to seek to.
  ///   - fullLength: The full length of the file when it was opened from its index, otherwise `nil`.
  ///   - exact: Whether the seek is exact rather than to a key frame.
  /// - Returns: While the full length is known, an absolute seek to `seekTime(percent:fullLength:)`, because `mpv` takes a
  ///     percentage of the shorter duration it reports; otherwise `mpv`'s own seek to the percentage.
  static func seekArguments(percent: Double, fullLength: Double?, exact: Bool) -> [String] {
    guard let fullLength else { return ["\(percent)", exact ? "absolute-percent+exact" : "absolute-percent"] }
    return ["\(seekTime(percent: percent, fullLength: fullLength))", exact ? "absolute+exact" : "absolute"]
  }

  /// The time remaining in a file of the given full length.
  /// - Parameters:
  ///   - fullLength: The full length of the file.
  ///   - position: The playback position.
  ///   - speed: The playback speed, by which the remaining time is divided when it is scaled.
  static func remaining(fullLength: Double, position: Double, speed: Double?) -> Double {
    let remaining = max(fullLength - position, 0)
    guard let speed, speed > 0 else { return remaining }
    return remaining / speed
  }
}
