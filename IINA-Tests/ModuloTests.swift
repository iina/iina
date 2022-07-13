//
//  ModuloTest.swift
//  IINA-Tests
//
//  Created by Matt Svoboda on 2022.05.27.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest
@testable import IINA

// See Google's online calculator for correct answers to these (e.g., search for "1 mod 5")
class ModuloTests: XCTestCase {
  func testModulo() throws {
    // + %% +
    XCTAssertEqual(1 %% 5, 1)
    XCTAssertEqual(6 %% 5, 1)
    XCTAssertEqual(5 %% 5, 0)
    XCTAssertEqual(4 %% 5, 4)
    // - %% +
    XCTAssertEqual(-1 %% 5, 4)
    XCTAssertEqual(-2 %% 5, 3)
    XCTAssertEqual(-100 %% 5, 0)
    XCTAssertEqual(-101 %% 5, 4)
    // + %% -
    XCTAssertEqual(100 %% -5, 0)
    XCTAssertEqual(1 %% -5, -4)
    XCTAssertEqual(2 %% -5, -3)
    XCTAssertEqual(101 %% -5, -4)
    // - %% -
    XCTAssertEqual(-2 %% -5, -2)
    XCTAssertEqual(-11 %% -5, -1)
    XCTAssertEqual(-15 %% -5, 0)
    XCTAssertEqual(-10 %% -30, -10)
    // 0 %% +/-
    XCTAssertEqual(0 %% 5, 0)
    XCTAssertEqual(0 %% -5, 0)
  }

}
