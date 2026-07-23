//
//  KeyCodeHelperTests.swift
//  iinaTests
//

import XCTest
@testable import IINA

class KeyCodeHelperTests: XCTestCase {

  // MARK: - mpvKeyCode(from:) numpad handling

  func testNumpadDigitsProduceKPKeyNames() {
    let numpadKeyCodes: [UInt16: String] = [
      0x52: "0", 0x53: "1", 0x54: "2", 0x55: "3", 0x56: "4",
      0x57: "5", 0x58: "6", 0x59: "7", 0x5B: "8", 0x5C: "9",
    ]
    for (keyCode, digit) in numpadKeyCodes {
      let result = mpvKeyCode(keyCode: keyCode, characters: digit, modifiers: [.numericPad])
      XCTAssertEqual(result, "KP\(digit)")
    }
  }

  func testNumpadPeriodProducesKPDec() {
    XCTAssertEqual(mpvKeyCode(keyCode: 0x41, characters: ".", modifiers: [.numericPad]), "KP_DEC")
  }

  func testNumberRowDigitsAreUnchanged() {
    XCTAssertEqual(mpvKeyCode(keyCode: 0x19, characters: "9", modifiers: []), "9")
    XCTAssertEqual(mpvKeyCode(keyCode: 0x12, characters: "1", modifiers: []), "1")
  }

  func testNumpadDigitKeepsModifiers() {
    XCTAssertEqual(mpvKeyCode(keyCode: 0x5C, characters: "9", modifiers: [.numericPad, .option]), "Alt+KP9")
    XCTAssertEqual(mpvKeyCode(keyCode: 0x5C, characters: "9", modifiers: [.numericPad, .shift]), "Shift+KP9")
  }

  func testArrowKeysAreUnchangedByNumericPadFlag() {
    // Arrow keys carry the .numericPad flag but must keep their own key names
    let up = mpvKeyCode(keyCode: 0x7E, characters: "\u{F700}", modifiers: [.numericPad, .function])
    XCTAssertEqual(up, "UP")
  }

  func testNumpadEnterProducesKPEnter() {
    XCTAssertEqual(mpvKeyCode(keyCode: 0x4C, characters: "\r", modifiers: [.numericPad]), "KP_ENTER")
  }

  // MARK: - numpadAlternative(for:)

  func testNumpadAlternativeMapsKPKeysToNumberRow() {
    XCTAssertEqual(KeyCodeHelper.numpadAlternative(for: "KP9"), "9")
    XCTAssertEqual(KeyCodeHelper.numpadAlternative(for: "KP_DEC"), ".")
    XCTAssertEqual(KeyCodeHelper.numpadAlternative(for: "KP_ENTER"), "ENTER")
    XCTAssertEqual(KeyCodeHelper.numpadAlternative(for: "Alt+KP9"), "Alt+9")
  }

  func testNumpadAlternativeMapsNumberRowKeysToKP() {
    XCTAssertEqual(KeyCodeHelper.numpadAlternative(for: "9"), "KP9")
    XCTAssertEqual(KeyCodeHelper.numpadAlternative(for: "."), "KP_DEC")
    XCTAssertEqual(KeyCodeHelper.numpadAlternative(for: "ENTER"), "KP_ENTER")
    XCTAssertEqual(KeyCodeHelper.numpadAlternative(for: "Ctrl+Alt+3"), "Ctrl+Alt+KP3")
  }

  func testNumpadAlternativeReturnsNilForKeysWithoutTwin() {
    XCTAssertNil(KeyCodeHelper.numpadAlternative(for: "a"))
    XCTAssertNil(KeyCodeHelper.numpadAlternative(for: "SPACE"))
    XCTAssertNil(KeyCodeHelper.numpadAlternative(for: "Alt+UP"))
  }

  private func mpvKeyCode(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> String {
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
      windowNumber: 0, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    return KeyCodeHelper.mpvKeyCode(from: event)
  }
}

class PlayerCoreKeyBindingTests: XCTestCase {

  private var savedKeyBindings: [String: KeyMapping] = [:]

  override func setUp() {
    super.setUp()
    savedKeyBindings = PlayerCore.keyBindings
  }

  override func tearDown() {
    PlayerCore.keyBindings = savedKeyBindings
    super.tearDown()
  }

  func testExactMatchWinsOverNumpadTwin() {
    let rotate = KeyMapping(rawKey: "KP9", rawAction: "add video-rotate 90")
    let volume = KeyMapping(rawKey: "9", rawAction: "add volume 5")
    PlayerCore.keyBindings = ["KP9": rotate, "9": volume]

    XCTAssertEqual(PlayerCore.keyBinding(for: "KP9")?.rawAction, "add video-rotate 90")
    XCTAssertEqual(PlayerCore.keyBinding(for: "9")?.rawAction, "add volume 5")
  }

  func testNumpadKeyFallsBackToNumberRowBinding() {
    PlayerCore.keyBindings = ["9": KeyMapping(rawKey: "9", rawAction: "add volume 5")]

    XCTAssertEqual(PlayerCore.keyBinding(for: "KP9")?.rawAction, "add volume 5")
  }

  func testNumberRowKeyFallsBackToNumpadBinding() {
    PlayerCore.keyBindings = ["KP9": KeyMapping(rawKey: "KP9", rawAction: "add video-rotate 90")]

    XCTAssertEqual(PlayerCore.keyBinding(for: "9")?.rawAction, "add video-rotate 90")
  }

  func testUnboundKeyReturnsNil() {
    PlayerCore.keyBindings = [:]

    XCTAssertNil(PlayerCore.keyBinding(for: "KP9"))
    XCTAssertNil(PlayerCore.keyBinding(for: "SPACE"))
  }
}
