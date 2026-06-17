//
//  KeyMappingTests.swift
//  iinaTests
//
//  Created for the mpv-config-driven-refactor iteration (SPEC Phase 5).
//
//  Verifies that `KeyMapping.parseInputConf` recognises mpv's
//  `#@click` / `#@press` / `#@release` action suffix and produces
//  one `KeyMapping` row per suffix with the matching `BindingKind`.
//

import XCTest
@testable import IINA

final class KeyMappingTests: XCTestCase {

  /// Writes the SPACE triplet (verbatim from `mpv/input.conf:79-81`)
  /// to a temp file and returns its path.
  private func writeSpaceTripletFixture() throws -> String {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("iinaKeyMappingTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("space-triplet.input.conf")
    // Verbatim from mpv/input.conf lines 79-81.
    let content = """
    SPACE cycle pause #@click
    SPACE no-osd set speed 4; set pause no #@press
    SPACE ignore #@release
    """
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url.path
  }

  /// SPEC acceptance criterion 12 / PLAN Phase 5: the SPACE triplet
  /// must parse into 3 distinct `KeyMapping` rows, none dropped, each
  /// carrying the correct `BindingKind`.
  func testParseClickPressReleaseSpace() throws {
    let path = try writeSpaceTripletFixture()
    guard let rows = KeyMapping.parseInputConf(at: path) else {
      XCTFail("parseInputConf must return a non-nil array")
      return
    }

    let spaceRows = rows.filter { $0.rawKey == "SPACE" }
    XCTAssertEqual(spaceRows.count, 3,
                   "SPACE triplet must produce exactly 3 rows, got \(spaceRows.count)")

    let kinds = Set(spaceRows.map { $0.binding })
    XCTAssertEqual(kinds, [.click, .press, .release],
                   "expected {.click, .press, .release}, got \(kinds)")

    // The `#@<kind>` suffix must NOT leak into the action text.
    for row in spaceRows {
      XCTAssertFalse(row.rawAction.contains("#@"),
                     "action leaked the suffix: \(row.rawAction)")
      XCTAssertFalse(row.action.joined(separator: " ").contains("#@"),
                     "action components leaked the suffix")
    }

    // Spot-check the click row's action is the plain mpv command.
    let clickRow = spaceRows.first { $0.binding == .click }
    XCTAssertEqual(clickRow?.action, ["cycle", "pause"])
  }

  /// A plain row with no suffix must keep `BindingKind.command` so the
  /// new default does not regress existing bindings.
  func testPlainCommandRowDefaultsToCommandBinding() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("iinaKeyMappingTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("plain.input.conf")
    try "RIGHT seek 5".write(to: url, atomically: true, encoding: .utf8)

    guard let rows = KeyMapping.parseInputConf(at: url.path) else {
      XCTFail("parseInputConf must return a non-nil array")
      return
    }
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.binding, .command)
    XCTAssertEqual(rows.first?.rawAction, "seek 5")
  }

  /// SPEC Phase 5: round-tripping a `.click` row through
  /// `confFileFormat` must re-emit the `#@click` suffix so the binding
  /// kind survives save+reload from IINA's keybinding editor.
  func testConfFileFormatRoundTripsBindingSuffix() {
    let km = KeyMapping(
      rawKey: "SPACE", rawAction: "cycle pause", binding: .click)
    let rendered = km.confFileFormat
    XCTAssertTrue(rendered.hasSuffix("#@click"),
                  "expected #@click suffix, got \(rendered)")
    XCTAssertTrue(rendered.contains("SPACE cycle pause"),
                  "expected key+action before suffix, got \(rendered)")
  }
}
