//
//  MPVSentinel.swift
//  iina
//
//  Tracks mpv options that the user has explicitly set in their `mpv.conf`
//  so that IINA can avoid clobbering user-supplied values when applying its
//  own hardcoded option overrides. See SPEC requirement 2 and PLAN Phase 2.
//
//  Usage:
//    1. Call `MPVSentinel.recordFromConfigFiles()` once at the start of
//       `MPVController.mpvInit()` (before `mpv_initialize`).
//    2. Before applying each hardcoded option override, check
//       `MPVSentinel.wasSetInConfig(<mpv-option-name>)` and skip the
//       override if it returns `true`.
//

import Foundation

/// Process-wide registry of mpv options that appear explicitly in the
/// bundled or materialized `mpv.conf`. Recording is intentionally limited
/// to the main (top-level) section of the config file — `[profile]`
/// sections are not in scope for this sentinel because their keys are
/// only in effect while the profile is active, which is decided by mpv
/// at file-load time. See the "documented gap" note in PLAN Phase 2.
enum MPVSentinel {

  /// The set of option names that appear explicitly as `key=value` in
  /// the user's `mpv.conf`. Keys are trimmed; inline `# comments` are
  /// stripped before recording. Repeated occurrences are de-duplicated
  /// by the `Set` storage.
  private static var explicitKeys: Set<String> = []

  /// Record an explicit `key=value` pair parsed from `mpv.conf`.
  /// - Parameter key: The option name, e.g. `"sub-auto"` or `"force-window"`.
  static func recordExplicit(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    explicitKeys.insert(trimmed)
  }

  /// Returns `true` if the user has explicitly set the given option
  /// in the main section of their `mpv.conf` (either the bundled
  /// default or the user's customized materialized copy).
  /// - Parameter key: The mpv option name, e.g. `"vo"` or
  ///   `MPVOption.Video.vo`.
  static func wasSetInConfig(_ key: String) -> Bool {
    return explicitKeys.contains(key)
  }

  /// Clear any previously recorded keys. Useful for tests and for
  /// re-scanning after the materialized config file changes.
  static func reset() {
    explicitKeys.removeAll()
  }

  /// Read `mpv.conf` from the materialized location (preferred) and
  /// fall back to the bundled location, recording every explicit
  /// `key=value` line in the main section. `[profile]` sections and
  /// their contents are skipped — profile-level overrides are handled
  /// by mpv's auto-profile mechanism at file-load time and are out of
  /// scope for this sentinel.
  ///
  /// Idempotent: a second call replaces the previously recorded set.
  static func recordFromConfigFiles() {
    reset()
    let candidates: [URL] = [
      Utility.materializedMPVConfigDirURL
        .appendingPathComponent(AppData.mpvConfigFileName),
      Utility.bundledMPVConfigDirURL
        .appendingPathComponent(AppData.mpvConfigFileName),
    ]
    var scanned = false
    for url in candidates {
      if recordFromConfigFile(at: url) {
        // Prefer the user's materialized copy (which reflects any
        // customizations) over the bundled default.
        scanned = true
        break
      }
    }
    if !scanned {
      Logger.log("MPVSentinel: no mpv.conf found in bundled or materialized mpv/ directory",
                 level: .warning)
    }
  }

  // MARK: - Private parsing helpers

  /// Parse a single `mpv.conf` file and record every explicit
  /// `key=value` line outside of `[profile]` sections.
  /// - Parameter url: URL of the `mpv.conf` to scan.
  /// - Returns: `true` if the file existed and was parsed, `false`
  ///   otherwise.
  @discardableResult
  private static func recordFromConfigFile(at url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path),
          let content = try? String(contentsOf: url, encoding: .utf8) else {
      return false
    }
    var inProfileSection = false
    for rawLine in content.components(separatedBy: .newlines) {
      let line = stripTrailingComment(rawLine).trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        continue
      }
      // Section header — `[profile-name]` ends the main section.
      if line.hasPrefix("[") && line.hasSuffix("]") {
        inProfileSection = true
        continue
      }
      // Profile-cond lines (`profile-cond=...`, `profile-restore=...`,
      // `profile-desc=...`) are not user-overridable mpv playback
      // options; record them too for completeness but they are not
      // used as guards by Phase 2.
      if inProfileSection {
        continue
      }
      // Expect `key=value` on each non-empty, non-comment line.
      guard let eqIndex = line.firstIndex(of: "=") else {
        continue
      }
      let key = String(line[..<eqIndex])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      recordExplicit(key)
    }
    return true
  }

  /// Strip a trailing `# comment` from a line, respecting single
  /// quotes so that values like `'#F0FFFFFF'` survive intact.
  private static func stripTrailingComment(_ line: String) -> String {
    var inSingleQuote = false
    var result = ""
    for ch in line {
      if ch == "'" {
        inSingleQuote.toggle()
        result.append(ch)
      } else if ch == "#" && !inSingleQuote {
        break
      } else {
        result.append(ch)
      }
    }
    return result
  }
}
