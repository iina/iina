//
//  CoverageAuditTests.swift
//  iinaTests
//
//  Created for the ui-driven-mpv-options iteration (SPEC acceptance
//  criterion 5 / PLAN Phase 6).
//
//  Automated form of SPEC acceptance criterion 5: reads the canonical
//  `mpv/mpv.conf`, extracts every non-comment option name from the
//  main section (excluding `[profile]` sections), and asserts each
//  name is either
//    1. A `.mpvName("...")` argument somewhere in
//       `iina/SettingsPage*.swift`,
//    2. Listed in the `knownGaps` set below with a documented reason,
//       OR
//    3. An alias for a real mpv option (e.g. the long-standing
//       `vd-lavc-software-fallback` typo in the user's mpv.conf, which
//       mpv silently ignores; the new key maps to the real
//       `hwdec-software-fallback` per the SPEC's correction 1).
//
//  The test fails if any option is unmapped (cases 1+2+3 do not cover
//  it). Future edits to `mpv/mpv.conf` that add options will correctly
//  fail the audit until a matching `.mpvName(...)` is added — which is
//  the intended behaviour.
//

import XCTest
@testable import IINA

final class CoverageAuditTests: XCTestCase {

  // Options present in the user's `mpv/mpv.conf` main section that are
  // NOT currently exposed as a `.mpvName(...)` row in any Settings
  // page. Each entry MUST be accompanied by a documented reason in the
  // XCTAssert message below. This list is the negative space of the
  // audit — it must stay small and well-justified. Adding an entry
  // here should be a last-resort action; the preferred remediation is
  // to add the missing `.mpvName(...)` to the relevant SettingsPage.
  //
  // Categories (matching the Phase 5 manual audit):
  //   - "no IINA Settings row": the option has no UI surface at all
  //     in IINA's Settings. The badge machinery has nowhere to attach.
  //   - "custom view": the backing widget is a custom AppKit view
  //     (NSColorWell / NSSwitch / NSStepper / NSOpenPanel etc.) inside
  //     SubtitlesColorView, SubtitlesFontView, SubtitlesShadowView, or
  //     ScreenshotFormatOptionsView. The Phase 5 badge machinery lives
  //     in `SettingsItem.General.makeView`, which these custom views
  //     bypass. Widening the audit would require a separate refactor.
  //   - "SwitchWithInput / LanguageSelector": the option is exposed
  //     through a non-`SettingsItem.General` widget
  //     (SwitchWithInput for `volume`; SettingsAccessory.LanguageSelector
  //     for `alang`).
  private static let knownGaps: Set<String> = [
    // (All "no IINA Settings row" gaps closed in Phase 7: rows added in
    // SettingsPageUI.swift for `border` / `hidpi-window-scale`, and in
    // SettingsPageAudio.swift for `audio-channels` / `audio-file-auto`.)
    // Backing widget is a `SwitchWithInput`, not a `SettingsItem.General`.
    "volume",
    // Backing widget is a custom `SettingsAccessory.LanguageSelector`; not
    // a `SettingsItem.General` row, so the Phase 5 badge machinery can't
    // reach it.
    "alang",
    // Custom view rows that pre-date the Phase 5 badge machinery. The row
    // binds to a real mpv option but is rendered via raw AppKit widgets
    // inside SubtitlesColorView, SubtitlesFontView, SubtitlesShadowView,
    // and ScreenshotFormatOptionsView. The badge machinery lives in
    // `SettingsItem.General.makeView`, which these custom views bypass;
    // widening the audit to include them would require a separate
    // refactor.
    "sub-font-size",
    "sub-shadow-offset",
    "sub-color",
    "screenshot-jpeg-quality",
    "screenshot-jpeg-source-chroma",
    "screenshot-png-compression",
    "screenshot-webp-lossless",
    "screenshot-webp-quality",
    "screenshot-jxl-distance",
    "screenshot-jxl-effort",
    "screenshot-high-bit-depth",
  ]

  // Aliases: option names that appear in mpv.conf but map to a different
  // mpv option. The audit treats the alias as "covered" iff the target
  // is in the badged set.
  //
  // SPEC:Phase-7 revert — the Phase 3 entry below was based on the
  // wrong assumption that `vd-lavc-software-fallback` was a typo for
  // `hwdec-software-fallback`. mpv 0.38.0 (the libmpv IINA ships)
  // actually has the option named `vd-lavc-software-fallback`; the
  // `-append` and `hwdec-software-fallback` names were added in
  // later mpv versions. The alias is therefore redundant (the
  // mpv.conf line is now directly badged in
  // `SettingsPageVideoAdvanced.swift` under
  // `.mpvName("vd-lavc-software-fallback")`) and has been removed.
  private static let aliases: [String: String] = [:]

  /// Path to the repo root, derived from this test file's location
  /// (`iina/Tests/CoverageAuditTests.swift` → up 3 dirs → repo root).
  private var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // iina/
      .deletingLastPathComponent()  // repo root
  }

  /// Path to the canonical `mpv/mpv.conf` curated by the user.
  private var mpvConfURL: URL {
    repoRoot.appendingPathComponent("mpv/mpv.conf")
  }

  /// Directory that contains every `SettingsPage*.swift`.
  private var iinaDir: URL {
    repoRoot.appendingPathComponent("iina")
  }

  // MARK: - Helpers

  /// Read every `.mpvName("...")` argument from the Settings page
  /// files and return them as a `Set<String>`. Tests run in the
  /// `iinaTests` bundle on the same machine that has the source tree
  /// checked out, so reading from `#filePath`-relative paths works.
  private func collectMpvNames() throws -> Set<String> {
    let entries = try FileManager.default.contentsOfDirectory(
      at: iinaDir,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    let settingsFiles = entries
      .filter { $0.lastPathComponent.hasPrefix("SettingsPage") && $0.pathExtension == "swift" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    XCTAssertFalse(
      settingsFiles.isEmpty,
      "No SettingsPage*.swift files found at \(iinaDir.path) — check the test path resolution."
    )

    // Match `.mpvName("...")` with optional whitespace inside the
    // parens. The captured group is the option-name literal.
    let pattern = #"\.mpvName\(\s*"([^"]+)"\s*\)"#
    let regex = try NSRegularExpression(pattern: pattern)

    var found = Set<String>()
    var totalHits = 0
    for file in settingsFiles {
      let text = try String(contentsOf: file, encoding: .utf8)
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      regex.enumerateMatches(in: text, range: range) { match, _, _ in
        guard let match = match,
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text)
        else { return }
        found.insert(String(text[r]))
        totalHits += 1
      }
    }
    // Sanity: Phase 5 reported 62 .mpvName calls across 9 files. A
    // future regression that drops the call count below that floor
    // should be caught here. We use a soft floor of 50 to allow
    // future scope shrinkage without breaking the test, but the
    // primary assertion is the structural coverage check below.
    XCTAssertGreaterThanOrEqual(
      totalHits, 50,
      "Suspiciously low .mpvName call count (\(totalHits)). Phase 5 reported 62 — investigate before continuing."
    )
    return found
  }

  /// Parse the main section of `mpv.conf` (excluding `[profile]`
  /// blocks) and return the list of option names actually set in the
  /// curated config, in source order. Inline `#` comments and
  /// surrounding whitespace are stripped; values can be quoted.
  private func parseMainSectionOptionNames() throws -> [String] {
    let text = try String(contentsOf: mpvConfURL, encoding: .utf8)
    var names: [String] = []
    var inProfile = false
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
      var line = raw.trimmingCharacters(in: .whitespaces)
      // Strip inline `#` comments. A `#` may appear unquoted inside a
      // value (e.g. `sub-color='#F0FFFFFF' # note`), so we only treat
      // the first `#` as a comment delimiter — which is what every
      // mpv.conf parser does for the main section.
      if let hashIdx = line.firstIndex(of: "#") {
        line = String(line[..<hashIdx]).trimmingCharacters(in: .whitespaces)
      }
      if line.isEmpty { continue }
      // Profile section toggle: `[name]` opens a profile block that
      // is applied by mpv's auto-profile engine and is out of scope
      // for this audit (see SPEC Non-Goals). Toggle on; the next
      // non-empty line that is itself a `[xxx]` header is fine
      // (re-toggle), and we never re-enter the main section.
      if line.hasPrefix("[") && line.hasSuffix("]") {
        inProfile = true
        continue
      }
      if inProfile { continue }
      // First `=` separates name from value. The value can itself
      // contain `=` (e.g. `ytdl-raw-options-append = cookies-from-
      // browser=edge`); split on the FIRST occurrence only.
      guard let eq = line.firstIndex(of: "=") else { continue }
      let name = line[..<eq].trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty else { continue }
      names.append(name)
    }
    return names
  }

  // MARK: - Tests

  /// Every option in the main section of `mpv/mpv.conf` must be
  /// either badged (`.mpvName(...)`), in the `knownGaps` set with a
  /// documented reason, or an alias for a real mpv option that is
  /// itself badged. The test fails with a quoted list of unmapped
  /// options if any are found.
  func testMainSectionOptionsAllCoveredOrKnownGap() throws {
    let optionNames = try parseMainSectionOptionNames()
    let distinctNames = Set(optionNames)
    XCTAssertGreaterThan(
      distinctNames.count, 0,
      "No options parsed from mpv.conf at \(mpvConfURL.path) — check the test path."
    )
    let badged = try collectMpvNames()

    var unmapped: [String] = []
    for name in distinctNames.sorted() {
      // Apply alias: `vd-lavc-software-fallback` → `hwdec-software-fallback`.
      let resolved = Self.aliases[name] ?? name
      if badged.contains(resolved) { continue }
      if Self.knownGaps.contains(name) { continue }
      unmapped.append(name)
    }
    XCTAssertEqual(
      unmapped, [],
      """
      \(unmapped.count) mpv.conf main-section option(s) are NOT covered by any .mpvName(...) row and NOT in the knownGaps set.
      Fix by adding a `.mpvName("<name>")` call to the relevant SettingsPage*.swift, or add the option to knownGaps with a documented reason.
      Unmapped options (\(unmapped.count)): \(unmapped)
      """
    )
  }

  /// Sanity: every `.mpvName(...)` argument we tag must look like a
  /// plausible mpv option name (letters / digits / hyphens /
  /// underscores only, non-empty). This catches typos in the
  /// `.mpvName("")` argument string that would otherwise go
  /// unnoticed because the string is the only link between the
  /// Settings row and `MPVSentinel.wasSetInConfig(_:)`.
  func testMpvNameArgumentsAreWellFormed() throws {
    let badged = try collectMpvNames()
    XCTAssertFalse(badged.isEmpty, "No .mpvName arguments found — investigate.")
    for name in badged.sorted() {
      XCTAssertFalse(
        name.isEmpty,
        "Empty .mpvName(...) argument found — that row will never show the badge."
      )
      XCTAssertTrue(
        name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" },
        "Invalid characters in .mpvName(\"\(name)\") — mpv option names allow only letters, digits, hyphens, underscores."
      )
    }
  }

  /// Cross-check: the curated main-section options minus the gap
  /// set minus the alias keys must all appear in the badged set.
  /// This is the positive form of the audit — it catches the case
  /// where a row's `.mpvName("...")` typo (e.g. `osd-fon-size`)
  /// accidentally matches no curated option, and the typo silently
  /// ships.
  func testCuratedMainSectionOptionsAreAllBadged() throws {
    let optionNames = try parseMainSectionOptionNames()
    let distinctNames = Set(optionNames)
    let badged = try collectMpvNames()
    let expected = distinctNames
      .subtracting(Self.knownGaps)
      .subtracting(Self.aliases.keys)
    let missing = expected.subtracting(badged)
    XCTAssertEqual(
      missing, [],
      """
      These main-section options are expected to be badged but are not. Likely causes: a .mpvName("...") typo, or a recent refactor dropped the chain.
      Missing (\(missing.count)): \(missing.sorted())
      """
    )
  }

  /// Self-consistency: every entry in the `knownGaps` set must
  /// actually appear in `mpv/mpv.conf` (so the set cannot rot
  /// silently). A gap that no longer exists in the curated config
  /// is dead documentation and should be removed.
  func testKnownGapsAreContainedInMPVConf() throws {
    let optionNames = Set(try parseMainSectionOptionNames())
    let stale = Self.knownGaps.subtracting(optionNames).sorted()
    XCTAssertEqual(
      stale, [],
      """
      knownGaps contains option names that do NOT appear in mpv/mpv.conf. Either the config was edited and the gap is now stale (remove the entry), or the entry is a typo (fix the name).
      Stale entries: \(stale)
      """
    )
  }

  /// Self-consistency: every key in the `aliases` map must also
  /// appear in `mpv/mpv.conf` (the alias is defined to handle a
  /// specific line in the curated config).
  func testAliasKeysAreContainedInMPVConf() throws {
    let optionNames = Set(try parseMainSectionOptionNames())
    let stale = Set(Self.aliases.keys).subtracting(optionNames).sorted()
    XCTAssertEqual(
      stale, [],
      """
      aliases has keys that do NOT appear in mpv/mpv.conf. Either the config was edited (remove the alias), or the key is a typo.
      Stale entries: \(stale)
      """
    )
  }

  /// Self-consistency: every alias target must be in the badged set
  /// (otherwise the alias is meaningless — the line would still
  /// fail the main coverage check).
  func testAliasTargetsAreBadged() throws {
    let badged = try collectMpvNames()
    let unresolved = Self.aliases.values.filter { !badged.contains($0) }.sorted()
    XCTAssertEqual(
      unresolved, [],
      """
      aliases maps to mpv options that are NOT badged in any SettingsPage. The alias exists to cover an mpv.conf line, but the target has no .mpvName(...) call so the line is still effectively unmapped.
      Unresolved alias targets: \(unresolved)
      """
    )
  }
}
