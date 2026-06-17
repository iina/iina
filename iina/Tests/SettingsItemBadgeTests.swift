//
//  SettingsItemBadgeTests.swift
//  iinaTests
//
//  Created for the ui-driven-mpv-options iteration (SPEC Phase 5 / PLAN
//  Phase 5, requirement 3).
//
//  Verifies the "Overridden by your mpv.conf" badge machinery:
//   - `SettingsItem.Base.mpvName(_:)` stores the mpv option name on the
//     row and is chainable.
//   - `SettingsItem.General.makeView` renders an "Overridden by your
//     mpv.conf" badge when `MPVSentinel.wasSetInConfig(_:)` returns true
//     for the bound mpv option.
//   - The badge does NOT render when MPVSentinel does not report the
//     option (the default no-mpv.conf case).
//   - The badge tooltip substitutes the mpv option name.
//

import XCTest
import AppKit
@testable import IINA

final class SettingsItemBadgeTests: XCTestCase {

  // MPVSentinel is a process-wide static registry. Reset before and after
  // every test so the suite is order-independent.

  override func setUp() {
    super.setUp()
    MPVSentinel.reset()
  }

  override func tearDown() {
    MPVSentinel.reset()
    super.tearDown()
  }

  // MARK: - `.mpvName(_:)` chain

  /// `.mpvName(_:)` stores the supplied option name on the row.
  func testMpvNameStoresValue() {
    let item = SettingsItem.Switch().mpvName("osd-font-size")
    XCTAssertEqual(item.mpvOptionName, "osd-font-size",
                   ".mpvName(_:) must store the option name on `Base.mpvOptionName`")
  }

  /// `.mpvName(_:)` is chainable (returns `Self`) so it slots into the
  /// existing `.bindTo(...).hasDescription().withHelpLink(...)` chain.
  func testMpvNameIsChainable() {
    let item = SettingsItem.Input()
      .bindTo(.osdFontSize)
      .mpvName("osd-font-size")
      .hasDescription()
    XCTAssertEqual(item.mpvOptionName, "osd-font-size",
                   ".mpvName(_:) must return Self so it can be chained after .bindTo()")
  }

  /// Re-calling `.mpvName(_:)` overwrites the previous value (the latest
  /// call wins, matching the rest of the chained accessor API).
  func testMpvNameSecondCallWins() {
    let item = SettingsItem.Input()
      .mpvName("first-option")
      .mpvName("second-option")
    XCTAssertEqual(item.mpvOptionName, "second-option")
  }

  // MARK: - Badge rendering through `General.makeView`

  /// When MPVSentinel reports the option as set in the user's mpv.conf,
  /// `General.makeView` renders an "Overridden by your mpv.conf" badge.
  func testBadgeAppearsWhenSetInConfig() {
    let optionName = "osd-font-size"
    MPVSentinel.recordExplicit(optionName)
    XCTAssertTrue(MPVSentinel.wasSetInConfig(optionName),
                  "MPVSentinel.recordExplicit must register the key")

    let item = SettingsItem.Input()
      .mpvName(optionName)
      .bindTo(.osdFontSize)
    let context = SettingsLocalization.Context(tableName: "SettingsOSDLocalizable")
    let view = item.makeView(context: context)

    let badge = findTextField(in: view, containing: "Overridden by your mpv.conf")
    XCTAssertNotNil(badge,
                    "Badge must appear in `General.makeView` output when MPVSentinel reports the option as set in the user's mpv.conf")
  }

  /// When MPVSentinel does NOT report the option, no badge is rendered
  /// (this is the default state — clean install, no user mpv.conf).
  func testBadgeAbsentWhenNotSetInConfig() {
    // Sentinel is reset in setUp; nothing recorded.
    XCTAssertFalse(MPVSentinel.wasSetInConfig("osd-font-size"),
                   "Sentinel must be empty after setUp reset")

    let item = SettingsItem.Input()
      .mpvName("osd-font-size")
      .bindTo(.osdFontSize)
    let context = SettingsLocalization.Context(tableName: "SettingsOSDLocalizable")
    let view = item.makeView(context: context)

    let badge = findTextField(in: view, containing: "Overridden by your mpv.conf")
    XCTAssertNil(badge,
                 "Badge must NOT appear when MPVSentinel reports the option is NOT set (clean install, no user mpv.conf)")
  }

  /// Without `.mpvName(_:)` the row has no mpv option to query, so no
  /// badge even if MPVSentinel has unrelated keys recorded.
  func testNoBadgeWhenMpvNameNotSet() {
    MPVSentinel.recordExplicit("osd-font-size")

    let item = SettingsItem.Input().bindTo(.osdFontSize)
    let context = SettingsLocalization.Context(tableName: "SettingsOSDLocalizable")
    let view = item.makeView(context: context)

    let badge = findTextField(in: view, containing: "Overridden by your mpv.conf")
    XCTAssertNil(badge,
                 "Badge must NOT appear when the row did not call .mpvName(_:)")
  }

  /// The badge tooltip substitutes the mpv option name so the user can
  /// see exactly which key is overriding the value.
  func testBadgeTooltipContainsOptionName() {
    let optionName = "vd-lavc-software-fallback"
    MPVSentinel.recordExplicit(optionName)

    let item = SettingsItem.Input()
      .mpvName(optionName)
      .bindTo(.vdLavcSoftwareFallback)
    let context = SettingsLocalization.Context(tableName: "SettingsVideoAdvancedLocalizable")
    let view = item.makeView(context: context)

    guard let badge = findTextField(in: view, containing: "Overridden by your mpv.conf") as? NSTextField else {
      XCTFail("Expected to find the badge as an NSTextField")
      return
    }
    let tooltip = badge.toolTip ?? ""
    XCTAssertTrue(tooltip.contains(optionName),
                  "Badge tooltip must include the mpv option name. Got: \"\(tooltip)\"")
  }

  /// The badge is small (12-pt) and uses `secondaryLabelColor` so it
  /// looks subordinate to the row label.
  func testBadgeAppearance() {
    MPVSentinel.recordExplicit("osd-font-size")

    let item = SettingsItem.Input()
      .mpvName("osd-font-size")
      .bindTo(.osdFontSize)
    let context = SettingsLocalization.Context(tableName: "SettingsOSDLocalizable")
    let view = item.makeView(context: context)

    guard let badge = findTextField(in: view, containing: "Overridden by your mpv.conf") as? NSTextField else {
      XCTFail("Expected to find the badge")
      return
    }
    // SPEC Phase 5: "12-pt secondary-label NSTextField".
    let fontSize = badge.font?.pointSize ?? 0
    XCTAssertEqual(fontSize, 12, accuracy: 0.01,
                   "Badge font must be 12 pt. Got: \(fontSize)")
    XCTAssertEqual(badge.textColor, NSColor.secondaryLabelColor,
                   "Badge color must be `secondaryLabelColor`. Got: \(String(describing: badge.textColor))")
  }

  // MARK: - Helpers

  /// Depth-first search for an `NSTextField` whose `stringValue` contains
  /// `substring`. Returns the first match (or nil). Used to locate the
  /// badge label inside the rendered SettingsItem view hierarchy.
  private func findTextField(in root: NSView, containing substring: String) -> NSView? {
    if let label = root as? NSTextField, label.stringValue.contains(substring) {
      return label
    }
    for sub in root.subviews {
      if let found = findTextField(in: sub, containing: substring) {
        return found
      }
    }
    return nil
  }
}
