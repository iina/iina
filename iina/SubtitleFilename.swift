//
//  SubtitleFilename.swift
//  iina
//
//  Copyright © 2026 lhc. All rights reserved.
//

import Foundation

/// The language and track flags encoded in the name of an external subtitle file.
///
/// Subtitle files are conventionally named after the video they belong to, followed by a language
/// tag and any number of flags, as in `Movie.en.srt`, `Movie.en.sdh.srt` or
/// `Movie.pt-BR.forced.srt`. mpv reads this convention when it autoloads subtitles itself, but IINA
/// turns mpv's autoloading off (`sub-auto=no`) and adds the files it finds with `sub-add`, which
/// does not look at the filename. As a result none of this reaches mpv, and a file ending in a flag
/// is worse off than one without: the flag is taken for the language tag, so `Movie.en.sdh.srt`
/// comes out as Southern Kurdish rather than English.
///
/// This type reads the name the way mpv would, so that what IINA loads is described the same as
/// what mpv loads.
struct SubtitleFilename {

  /// A flag a subtitle filename can carry, named as mpv's `sub-add` command names it.
  struct Flags: OptionSet {
    let rawValue: Int

    init(rawValue: Int) {
      self.rawValue = rawValue
    }

    static let hearingImpaired = Flags(rawValue: 1 << 0)
    static let forced = Flags(rawValue: 1 << 1)
    static let `default` = Flags(rawValue: 1 << 2)

    /// The flag the given filename tag stands for, or `nil` if it is not a flag.
    /// - Parameter tag: A lowercased tag from a subtitle filename.
    init?(tag: String) {
      switch tag {
      case "sdh", "hi", "cc": self = .hearingImpaired
      case "forced": self = .forced
      case "default": self = .default
      default: return nil
      }
    }

    /// The names mpv uses for these flags in the `flags` argument of `sub-add`.
    var mpvNames: [String] {
      var names: [String] = []
      if contains(.hearingImpaired) { names.append("hearing-impaired") }
      if contains(.forced) { names.append("forced") }
      if contains(.default) { names.append("default") }
      return names
    }
  }

  /// The language tag found in the filename, such as `en` or `pt-BR`, or `nil` if it does not end
  /// in one.
  let language: String?

  /// The flags found in the filename. Flags are recognized even when no language tag is, as in
  /// `Movie.forced.srt`.
  let flags: Flags

  /// The `flags` argument for mpv's `sub-add` command.
  ///
  /// Always starts with `select`, which is what mpv assumes when the argument is omitted, so a
  /// subtitle added through this keeps being selected as it was before.
  var mpvSubAddFlags: String { (["select"] + flags.mpvNames).joined(separator: "+") }

  /// Reads the language tag and flags from a subtitle filename.
  ///
  /// Everything after the last full stop is the extension and is ignored. What is left is read from
  /// the end: flags are taken off one at a time, and whatever precedes them is the language tag if
  /// it is shaped like one. Tags may also be bracketed, as in `Movie (en)` or `Movie [en][sdh]`.
  ///
  /// - Parameter filename: The last path component of a subtitle file.
  init(_ filename: String) {
    (language, flags) = Self.read(filename)
  }

  private static func read(_ filename: String) -> (language: String?, flags: Flags) {
    var flags: Flags = []

    let name = Array((filename as NSString).deletingPathExtension
      .trimmingCharacters(in: .whitespaces))
    guard name.count >= 2 else { return (nil, flags) }

    var index = name.count - 1
    var delimiter: Character = "."
    if name[index] == ")" {
      delimiter = "("
      index -= 1
    }
    if name[index] == "]" {
      delimiter = "["
      index -= 1
    }

    // The length of the tag currently under the cursor, and of the part of it that is made up of
    // subtags, as a language tag's first subtag is sized differently from the rest.
    var tagLength = 0
    var subtagsLength = 0

    while true {
      while index >= 0, name[index].isASCII, name[index].isLetter {
        tagLength += 1
        index -= 1
      }

      if index >= 0, tagLength >= 2, name[index] == delimiter,
         let flag = Flags(tag: String(name[(index + 1)...(index + tagLength)]).lowercased()) {
        flags.insert(flag)
        // Step over the delimiter, and over the closing bracket of the tag before it.
        index -= delimiter == "." ? 1 : 2
        tagLength = 0
        continue
      }

      // Subtags are one to eight letters each.
      // See https://en.wikipedia.org/wiki/IETF_language_tag#Syntax_of_language_tags
      guard tagLength >= subtagsLength + 1, tagLength <= subtagsLength + 8 else {
        return (nil, flags)
      }

      guard index >= 0, name[index] == "-" else { break }
      tagLength += 1
      index -= 1
      subtagsLength = tagLength
    }

    // The first subtag is two or three letters, and something has to precede it.
    guard tagLength >= subtagsLength + 2, tagLength <= subtagsLength + 3,
          index > 0, name[index] == delimiter else { return (nil, flags) }

    return (String(name[(index + 1)...(index + tagLength)]), flags)
  }
}
