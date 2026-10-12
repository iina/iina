//
//  MPVReplyCallbacksTests.swift
//  iinaTests
//
//  Tests for the callbacks waiting for mpv to reply to asynchronous requests.
//

import Testing
@testable import IINA

@Suite("Callbacks waiting for mpv's replies")
struct MPVReplyCallbacksTests {

  @Test("Each request is given its own user data, above the fixed user data")
  func distinctUserdata() {
    let callbacks = MPVReplyCallbacks()
    let first = callbacks.register { _, _ in }
    let second = callbacks.register { _, _ in }
    #expect(first == MPVReplyCallbacks.firstUserdata)
    #expect(second == first + 1)
    #expect(first > MPVController.UserData.screenshot)
    #expect(first > MPVController.UserData.scrollSeek)
  }

  @Test("The callback of a reply is taken once and receives the reply's error code")
  func takenOnce() {
    let callbacks = MPVReplyCallbacks()
    var errors: [Int32] = []
    let userdata = callbacks.register { error, _ in errors.append(error) }
    callbacks.take(userdata)?(-12, nil)
    #expect(errors == [-12])
    #expect(callbacks.take(userdata) == nil)
  }

  @Test("User data no request was made with has no callback", arguments: [UInt64(0), 1000000, 1000001, 1999999])
  func unknownUserdata(userdata: UInt64) {
    let callbacks = MPVReplyCallbacks()
    _ = callbacks.register { _, _ in }
    #expect(callbacks.take(userdata) == nil)
  }

  @Test("Taking one callback leaves the others waiting")
  func othersKeepWaiting() {
    let callbacks = MPVReplyCallbacks()
    var replied: [String] = []
    let first = callbacks.register { _, _ in replied.append("first") }
    let second = callbacks.register { _, _ in replied.append("second") }
    callbacks.take(second)?(0, nil)
    callbacks.take(first)?(0, nil)
    #expect(replied == ["second", "first"])
  }
}
