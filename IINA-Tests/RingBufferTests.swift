//
//  IINA_Tests.swift
//  IINA-Tests
//
//  Created by Matt Svoboda on 2022.05.27.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest
@testable import IINA

class RingBufferTests: XCTestCase {

  var rb_1: RingBuffer<String>!
  var rb_5: RingBuffer<String>!

  override func setUpWithError() throws {
    rb_1 = RingBuffer<String>(capacity: 1)
    rb_5 = RingBuffer<String>(capacity: 5)
  }

  func testEmpty() throws {
    // rb_1
    XCTAssertNil(rb_1.head)
    XCTAssertNil(rb_1.tail)
    XCTAssertNil(rb_1.removeHead())
    XCTAssertNil(rb_1.removeTail())
    XCTAssertEqual(rb_1.count, 0)
    XCTAssertTrue(rb_1.isEmpty)
    XCTAssertFalse(rb_1.isFull)
    XCTAssertEqual(rb_1.description, "[]")

    // rb_5
    XCTAssertNil(rb_5.head)
    XCTAssertNil(rb_5.tail)
    XCTAssertNil(rb_5.removeHead())
    XCTAssertNil(rb_5.removeTail())
    XCTAssertEqual(rb_5.count, 0)
    XCTAssertTrue(rb_5.isEmpty)
    XCTAssertFalse(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[]")
  }

  func testOneElementCapacity() throws {
    let H = "Head"
    let T = "Tail"

    // rb_1: capacity of 1. Insert Head first
    rb_1.insertHead(H)

    XCTAssertEqual(rb_1.head, H)
    XCTAssertEqual(rb_1.tail, H)
    XCTAssertEqual(rb_1.count, 1)
    XCTAssertFalse(rb_1.isEmpty)
    XCTAssertTrue(rb_1.isFull)
    XCTAssertEqual(rb_1.description, "[\(H)]")

    // Overwrite Head with Tail
    rb_1.insertTail(T)

    XCTAssertEqual(rb_1.head, T)
    XCTAssertEqual(rb_1.tail, T)
    XCTAssertEqual(rb_1.count, 1)
    XCTAssertFalse(rb_1.isEmpty)
    XCTAssertTrue(rb_1.isFull)
    XCTAssertEqual(rb_1.description, "[\(T)]")

    XCTAssertEqual(rb_1.removeTail(), T)

    // Overwrite Tail with Head
    rb_1.insertTail(H)

    XCTAssertEqual(rb_1.head, H)
    XCTAssertEqual(rb_1.tail, H)
    XCTAssertEqual(rb_1.count, 1)
    XCTAssertFalse(rb_1.isEmpty)
    XCTAssertTrue(rb_1.isFull)
    XCTAssertEqual(rb_1.description, "[\(H)]")

    // Pop off the only element
    XCTAssertEqual(rb_1.removeHead(), H)
    XCTAssertNil(rb_1.head)
    XCTAssertNil(rb_1.tail)
    XCTAssertNil(rb_1.removeHead())
    XCTAssertNil(rb_1.removeTail())
    XCTAssertEqual(rb_1.count, 0)
    XCTAssertTrue(rb_1.isEmpty)
    XCTAssertFalse(rb_1.isFull)
    XCTAssertEqual(rb_1.description, "[]")
  }

  func testSimpleHeadAndTail() throws {
    let H = "Head"
    let T = "Tail"

    // rb_5: 2 of 5 slots full, Head and Tail.
    rb_5.insertHead(H)
    rb_5.insertTail(T)

    XCTAssertEqual(rb_5.head, H)
    XCTAssertEqual(rb_5.tail, T)
    XCTAssertEqual(rb_5.count, 2)
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertFalse(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[\(T), \(H)]")

    // Pop off Head, leaving only Tail
    XCTAssertEqual(rb_5.removeHead(), H)
    XCTAssertEqual(rb_5.head, T)
    XCTAssertEqual(rb_5.tail, T)
    XCTAssertEqual(rb_5.count, 1)
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertFalse(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[\(T)]")

    // Now pop off only remaining element (Tail)
    XCTAssertEqual(rb_5.removeHead(), T)
    XCTAssertNil(rb_1.head)
    XCTAssertNil(rb_1.tail)
    XCTAssertNil(rb_1.removeHead())
    XCTAssertNil(rb_1.removeTail())
    XCTAssertEqual(rb_1.count, 0)
    XCTAssertTrue(rb_1.isEmpty)
    XCTAssertFalse(rb_1.isFull)
    XCTAssertEqual(rb_1.description, "[]")
  }

  func testAppendAndClear() throws {
    rb_5.insertHead("A")
    rb_5.insertHead("B")
    rb_5.insertHead("C")
    rb_5.insertTail("D")

    XCTAssertEqual(rb_5.count, 4)
    XCTAssertEqual(rb_5.head, "C")
    XCTAssertEqual(rb_5.tail, "D")
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertFalse(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[D, A, B, C]")

    rb_5.clear()
    XCTAssertNil(rb_1.head)
    XCTAssertNil(rb_1.tail)
    XCTAssertNil(rb_1.removeHead())
    XCTAssertNil(rb_1.removeTail())
    XCTAssertEqual(rb_1.count, 0)
    XCTAssertTrue(rb_1.isEmpty)
    XCTAssertFalse(rb_1.isFull)
    XCTAssertEqual(rb_1.description, "[]")
  }

  func testOverwriteTail() throws {
    rb_5.insertHead("A")
    rb_5.insertHead("B")
    rb_5.insertHead("C")
    rb_5.insertHead("D")
    rb_5.insertHead("E")

    XCTAssertEqual(rb_5.count, 5)
    XCTAssertEqual(rb_5.head, "E")
    XCTAssertEqual(rb_5.tail, "A")
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertTrue(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[A, B, C, D, E]")

    // Add 2 elements, overwriting tail
    rb_5.insertHead("F")
    rb_5.insertHead("G")

    XCTAssertEqual(rb_5.count, 5)
    XCTAssertEqual(rb_5.head, "G")
    XCTAssertEqual(rb_5.tail, "C")
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertTrue(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[C, D, E, F, G]")

    // Pop off one element from head and tail each
    XCTAssertEqual(rb_5.removeTail(), "C")
    XCTAssertEqual(rb_5.removeHead(), "G")

    XCTAssertEqual(rb_5.count, 3)
    XCTAssertEqual(rb_5.head, "F")
    XCTAssertEqual(rb_5.tail, "D")
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertFalse(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[D, E, F]")
  }

  func testOverwriteHead() throws {
    rb_5.insertHead("A")
    rb_5.insertHead("B")
    rb_5.insertHead("C")
    rb_5.insertHead("D")
    rb_5.insertHead("E")
    XCTAssertEqual(rb_5.description, "[A, B, C, D, E]")

    // Add 3 elements, overwriting head
    rb_5.insertTail("Z")
    rb_5.insertTail("Y")
    rb_5.insertTail("X")

    XCTAssertEqual(rb_5.count, 5)
    XCTAssertEqual(rb_5.head, "B")
    XCTAssertEqual(rb_5.tail, "X")
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertTrue(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[X, Y, Z, A, B]")

    // Pop off one element from head and tail each
    XCTAssertEqual(rb_5.removeTail(), "X")
    XCTAssertEqual(rb_5.removeHead(), "B")

    XCTAssertEqual(rb_5.count, 3)
    XCTAssertEqual(rb_5.head, "A")
    XCTAssertEqual(rb_5.tail, "Y")
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertFalse(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[Y, Z, A]")
  }
}
