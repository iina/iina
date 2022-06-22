//
//  KeySequence_UITests.swift
//  IINA-UI-Tests
//
//  Created by Matt Svoboda on 2022.06.06.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest

fileprivate let INPUT_CONFIG_NAME = "KeySeq-TestConfig"

// Make sure each window scale factor results in integers when multiplied by 320 and 240
fileprivate let CONFIG_FILE_CONTENT = """
a set window-scale 1.0
b set window-scale 1.5
c set window-scale 2.0

d ignore
e ignore
f ignore
d-e-f set window-scale 1.8
d-d-e set window-scale 2.1
d-d-d-e set window-scale 2.2
d-d-d-d-e set window-scale 1.7

g ignore
h ignore
i ignore
g-h-i set window-scale 1.2
j seek -5

k-l-m-n set window-scale 1.6

m-n-o-p set window-scale 1.8

q-r-s-t-w set window-scale 1.9

"""

fileprivate let VIDEO = QVGA_RED

class KeySequenceApplication: XCUIApplication {
  var windowFrame: CGRect {
    get {
      XCUIApplication().windows.element(boundBy: 0).frame
    }
  }

  func windowWithTitleStartingWith(_ titlePrefix: String) -> XCUIElement {
    return self.windows.element(matching: NSPredicate(format: "title BEGINSWITH '\(titlePrefix)'"))
  }
}

class KeySequence_UITests: XCTestCase {
  private var tempDirPath: String!

  private var inputConfigURL: URL!

  // The most recent app run
  private var app: KeySequenceApplication!

  // The runtime video window
  private var videoWindow: XCUIElement!

  // MARK: Test lifecycle

  override func setUpWithError() throws {
    continueAfterFailure = false
    tempDirPath = try FileManager.default.createTempDirectory()

    inputConfigURL = URL(fileURLWithPath: tempDirPath).appendingPathComponent("\(INPUT_CONFIG_NAME).conf")
    NSLog("Creating custom input config \"\(INPUT_CONFIG_NAME)\" at: \"\(inputConfigURL.path)\"")
    try CONFIG_FILE_CONTENT.write(to: inputConfigURL, atomically: true, encoding: String.Encoding.utf8)

    let prefs = [
      "actionAfterLaunch": "2",  // "Do nothing"
      "resumeLastPosition": "false",
      "currentInputConfigName" : INPUT_CONFIG_NAME,
      "inputConfigs": "{\(INPUT_CONFIG_NAME)=\(inputConfigURL.path);}"  // dictionary
    ]

    let runtimeVideoPath: String = try resolveRuntimeVideoPath(tempDirPath: tempDirPath, videoFilename: VIDEO)
    launchApp(args: [runtimeVideoPath], prefs: prefs)

    videoWindow = app.windowWithTitleStartingWith(VIDEO)
    XCTAssertTrue(videoWindow.exists)

    videoWindow.typeText("a")
    confirmWindowScale(1.0)
  }

  override func tearDownWithError() throws {
    if let failureCount = testRun?.failureCount, failureCount > 0 {
      takeScreenshot()
    } else {
      app.terminate()
    }
  }

  // MARK: Various util functions

  // Note: this unfortunately seems to take a screenshot of the entire screen which contains the window
  private func takeScreenshot() {
    let screenshot = app.windows.firstMatch.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  // Launches a single instance of IINA (via XCUIApplication) with the given args and prefs, if any.
  // The caller is expected to handle termination.
  func launchApp(args: [String] = [], prefs: [String: String] = [:]) {
    app = KeySequenceApplication()
    for arg in args {
      app.launchArguments.append(arg)
    }

    if prefs.count > 0 {
      app.setPrefs(prefs)
    }
    app.launch()
  }

  private func printDimensions(_ label: String, _ videoFrame: CGRect) {
    NSLog("\(label)Origin(x,y)=(\(videoFrame.origin.x),  \(videoFrame.origin.y)). Size(WxH): \(videoFrame.size.width)x\(videoFrame.size.height)")
  }

  private func confirmNoScaling() {
    XCTAssertEqual(QVGA_WIDTH, Int(videoWindow.frame.size.width))
    XCTAssertEqual(QVGA_HEIGHT, Int(videoWindow.frame.size.height))
  }

  private func confirmWindowScale(_ scale: Double) {
    printDimensions("Expecting \(scale)x: ", videoWindow.frame)
    XCTAssertEqual(Int(Double(QVGA_WIDTH)*scale), Int(videoWindow.frame.size.width))
    XCTAssertEqual(Int(Double(QVGA_HEIGHT)*scale), Int(videoWindow.frame.size.height))
  }

  // MARK: Tests

  /*
   Tests that 'a', 'b', and 'c' are mapped correctly, and that they correctly set the window size, which will be needed by other tests.
   */
  func testSingleKeys() throws {
    videoWindow.typeText("c")
    confirmWindowScale(2.0)

    videoWindow.typeText("a")
    confirmWindowScale(1.0)

    videoWindow.typeText("b")
    confirmWindowScale(1.5)
  }

  /*
   Tests the simplest path for a sequence:
   `d-e-f set window-scale 1.8`
   */
  func testSimpleSequence() throws {
    videoWindow.typeText("d")
    confirmNoScaling()

    videoWindow.typeText("e")
    confirmNoScaling()

    videoWindow.typeText("f")
    confirmWindowScale(1.8)
  }

  /*
   Tests that the buffer wraps around. Should match this:
   `d-d-e set window-scale 2.1`
   */
  func testSequenceWrap() throws {
    videoWindow.typeText("d")
    confirmNoScaling()

    videoWindow.typeText("e")
    confirmNoScaling()

    videoWindow.typeText("d")
    confirmNoScaling()

    videoWindow.typeText("d")
    confirmNoScaling()

    videoWindow.typeText("e")
    confirmWindowScale(2.1)
  }

  /*
   Tests that d-d-d-e is never hit becuase d-d-e always covers it up:
   */
  func testSequenceCoversSupersequence() {
    videoWindow.typeText("d")
    confirmNoScaling()

    videoWindow.typeText("d")
    confirmNoScaling()

    videoWindow.typeText("d")
    confirmNoScaling()

    videoWindow.typeText("e")
    confirmWindowScale(2.1)  // new match
  }

  /*
   Tests one long one, then makes sure the sequence is reset so that the overlapping one isn't hit
   k-l-m-n set window-scale 1.6
   m-n-o-p set window-scale 1.8
   */
  func testLongOverlappingSequences() {
    videoWindow.typeText("k")
    confirmNoScaling()

    videoWindow.typeText("l")
    confirmNoScaling()

    videoWindow.typeText("m")
    confirmNoScaling()

    videoWindow.typeText("n")
    confirmWindowScale(1.6)  // match "k-l-m-n"

    videoWindow.typeText("o")
    confirmWindowScale(1.6)

    videoWindow.typeText("p")
    confirmWindowScale(1.6)  // NO match for "m-n-o-p"

    videoWindow.typeText("m")
    confirmWindowScale(1.6)

    videoWindow.typeText("n")
    confirmWindowScale(1.6)

    videoWindow.typeText("o")
    confirmWindowScale(1.6)

    videoWindow.typeText("p")
    confirmWindowScale(1.8)  // match "m-n-o-p"
  }

  /*
   Tests that a sequence of 5 or more is invalid
   q-r-s-t-w set window-scale 1.9
   */
  func testMaxBufferSize4() {
    videoWindow.typeText("q")
    confirmNoScaling()

    videoWindow.typeText("r")
    confirmNoScaling()

    videoWindow.typeText("s")
    confirmNoScaling()

    videoWindow.typeText("t")
    confirmNoScaling()

    videoWindow.typeText("w")
    confirmNoScaling()  // no match
  }

  /*

   g ignore
   h ignore
   i ignore
   g-h-i set window-scale 1.2
   j seek -5
   */
  func testPlaysWellWithMenuKeyEquivalents() {
    videoWindow.typeText("g")
    confirmNoScaling()

    videoWindow.typeText("h")
    confirmNoScaling()

    videoWindow.typeText("j")
    confirmNoScaling()

    videoWindow.typeText("i")
    confirmNoScaling()

    videoWindow.typeText("g")
    confirmNoScaling()

    videoWindow.typeText("h")
    confirmNoScaling()

    videoWindow.typeText("i")
    confirmWindowScale(1.2)
  }
}
