//
//  KeyCodeTests.swift
//  IINA-Tests
//
//  Created by Matt Svoboda on 2022.07.12.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest
@testable import IINA

class KeyCodeTests: XCTestCase {
  func testOne_HappyPath() throws {
    let result = KeyCodeHelper.splitKeystrokes("T")
    XCTAssertEqual(result.count, 1)
    if result.count == 1 {  // avoid fatal error when indexing array
      XCTAssertEqual(result[0], "T")
    }
  }

  func testTwo_HappyPath() throws {
    let result = KeyCodeHelper.splitKeystrokes("Ctrl+T-L")
    XCTAssertEqual(result.count, 2)
    if result.count == 2 {  // avoid fatal error when indexing array
      XCTAssertEqual(result[0], "Ctrl+T")
      XCTAssertEqual(result[1], "L")
    }
  }

  func testDashes_HappyPath() throws {
    let result = KeyCodeHelper.splitKeystrokes("Test-1-2-3")
    XCTAssertEqual(result.count, 4)
    if result.count == 4 {  // avoid fatal error when indexing array
      XCTAssertEqual(result[0], "Test")
      XCTAssertEqual(result[1], "1")
      XCTAssertEqual(result[2], "2")
      XCTAssertEqual(result[3], "3")
    }
  }

  // second dash is punctuation
  func testDashes_3Dashes() throws {
    let result = KeyCodeHelper.splitKeystrokes("---")
    XCTAssertEqual(result.count, 2)
    if result.count == 2 {
      XCTAssertEqual(result[0], "-")
      XCTAssertEqual(result[1], "-")
    }
  }

  // test that fourth dash is extraneous and is discarded
  func testDashes_4Dashes() throws {
    let result = KeyCodeHelper.splitKeystrokes("----")
    XCTAssertEqual(result.count, 2)
    if result.count == 2 {
      XCTAssertEqual(result[0], "-")
      XCTAssertEqual(result[1], "-")
    }
  }

  // this should be the maximum number of dashes (4) with 3 being used as punctuation
  func testDashes_7Dashes() throws {
    let result = KeyCodeHelper.splitKeystrokes("-------")
    XCTAssertEqual(result.count, 4)
    if result.count == 4 {
      XCTAssertEqual(result[0], "-")
      XCTAssertEqual(result[1], "-")
      XCTAssertEqual(result[2], "-")
      XCTAssertEqual(result[3], "-")
    }
  }

  // test that additional dashes are discarded
  func testDashes_8Dashes() throws {
    let result = KeyCodeHelper.splitKeystrokes("--------")
    XCTAssertEqual(result.count, 4)
    if result.count == 4 {
      XCTAssertEqual(result[0], "-")
      XCTAssertEqual(result[1], "-")
      XCTAssertEqual(result[2], "-")
      XCTAssertEqual(result[3], "-")
    }
  }

  // test that additional dashes are discarded
  func testDashes_9Dashes() throws {
    let result = KeyCodeHelper.splitKeystrokes("---------")
    XCTAssertEqual(result.count, 4)
    if result.count == 4 {
      XCTAssertEqual(result[0], "-")
      XCTAssertEqual(result[1], "-")
      XCTAssertEqual(result[2], "-")
      XCTAssertEqual(result[3], "-")
    }
  }

  // test that additional dashes are discarded
  func testDashes_Invalid() throws {
    let result = KeyCodeHelper.splitKeystrokes("-+-----")
    XCTAssertEqual(result.count, 1)
    if result.count == 4 {
      XCTAssertEqual(result[0], "-+-----")
    }
  }

}
