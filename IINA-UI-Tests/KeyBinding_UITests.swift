//
//  KeyBinding_UITests.swift
//  IINA-UI-Tests
//
//  Created by Matt Svoboda on 2022.06.21.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation
import XCTest

fileprivate let INPUT_CONFIG_FILE_PREFIX = "KeyBindingTest"

private let VIDEO = QVGA_BLUE

class KeyBindingApplication: XCUIApplication {
  func windowWithTitleStartingWith(_ titlePrefix: String) -> XCUIElement {
    return self.windows.element(matching: NSPredicate(format: "title BEGINSWITH '\(titlePrefix)'"))
  }

  func menuItem_stepForwardBy(_ secondsLabel: Int) -> XCUIElement {
    self.menuBarItems["Playback"].menuItems["Step Forward \(secondsLabel)s"]
  }

  func menuItem_stepBackwardBy(_ secondsLabel: Int) -> XCUIElement {
    self.menuBarItems["Playback"].menuItems["Step Backward \(secondsLabel)s"]
  }
}

class KeyBinding_UITests: XCTestCase {
  private var tempDirPath: String!

  private var inputConfigURL: URL!

  // The most recent app run
  private var app: KeyBindingApplication!

  // The runtime video window
  private var videoWindow: XCUIElement!

  // MARK: Boilerplate

  override func setUpWithError() throws {
    continueAfterFailure = false
    tempDirPath = try FileManager.default.createTempDirectory()
  }

  override func tearDownWithError() throws {
    if let failureCount = testRun?.failureCount, failureCount > 0 {
      takeScreenshot()
    } else {
      app.terminate()
    }
  }

  // Note: this unfortunately seems to take a screenshot of the entire screen which contains the window
  private func takeScreenshot() {
    let screenshot = app.windows.firstMatch.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  // Launches a single instance of IINA (via XCUIApplication) with the given args and prefs, if any.
  // The caller is expected to handle termination.
  private func launchApp(args: [String] = [], prefs: [String: String] = [:]) {
    app = KeyBindingApplication()
    for arg in args {
      app.launchArguments.append(arg)
    }

    if prefs.count > 0 {
      app.setPrefs(prefs)
    }
    app.launch()
  }

  // MARK: Util functions

  private func launchAppWithConfig(_ configContent: String) throws {
    let configName = "\(INPUT_CONFIG_FILE_PREFIX)-\(UUID().uuidString)"
    let configFileName = "\(configName).conf"
    let inputConfigURL = URL(fileURLWithPath: tempDirPath).appendingPathComponent(configFileName)
    NSLog("Creating custom input config \"\(configFileName)\" at: \"\(tempDirPath!)\"")
    try configContent.write(to: inputConfigURL, atomically: true, encoding: String.Encoding.utf8)

    let prefs = [
      "actionAfterLaunch": "2",  // "Do nothing"
      "resumeLastPosition": "false",
      "currentInputConfigName" : configName,
      "inputConfigs": "{\(configName)=\(inputConfigURL.path);}"  // dictionary
    ]

    let runtimeVideoPath: String = try resolveRuntimeVideoPath(tempDirPath: tempDirPath, videoFilename: VIDEO)
    launchApp(args: [runtimeVideoPath], prefs: prefs)

    // Start video to ensure menu items are enabled
    videoWindow = app.windowWithTitleStartingWith(VIDEO)
    XCTAssertTrue(videoWindow.exists)

//    videoWindow.typeText("a")
//    confirmWindowScale(1.0)
  }

  private func printDimensions(_ label: String, _ videoFrame: CGRect) {
    NSLog("\(label)Origin(x,y)=(\(videoFrame.origin.x),  \(videoFrame.origin.y)). Size(WxH): \(videoFrame.size.width)x\(videoFrame.size.height)")
  }

  private func confirmMinimumWindowScale() {
    printDimensions("Expecting 285: ", videoWindow.frame)
    XCTAssertEqual(285, Int(videoWindow.frame.size.width))
    XCTAssertEqual(214, Int(videoWindow.frame.size.height))
  }

  private func confirmWindowScale(_ scale: Double) {
    printDimensions("Expecting \(scale)x: ", videoWindow.frame)
    XCTAssertEqual(Int(Double(QVGA_WIDTH)*scale), Int(videoWindow.frame.size.width))
    XCTAssertEqual(Int(Double(QVGA_HEIGHT)*scale), Int(videoWindow.frame.size.height))
  }

  // MARK: Tests

  /*
   Tests nominal case of one key binding each
   */
  func testHappyPath() throws {
    let configContent = """
    a set window-scale 1.0
    b set window-scale 2.0
    c set window-scale 0.5
    [ seek -5
    ] seek 6
    """

    try launchAppWithConfig(configContent)

    app.menuBarItems["Video"].menuItems["Half Size"].click()
    // can't go down to half size - vidoe is very small already. At least the minimum size is well-defined.
    confirmMinimumWindowScale()

    app.menuBarItems["Video"].menuItems["Double Size"].click()
    confirmWindowScale(2.0)

    app.menuBarItems["Video"].menuItems["Normal Size"].click()
    confirmWindowScale(1.0)

    videoWindow.typeText("b")
    confirmWindowScale(2.0)

    videoWindow.typeText("a")
    confirmWindowScale(1.0)

    videoWindow.typeText("c")
    confirmMinimumWindowScale()

    XCTAssertEqual(true, app.menuItem_stepBackwardBy(5).exists)
    XCTAssertEqual(false, app.menuItem_stepBackwardBy(6).exists)

    XCTAssertEqual(true, app.menuItem_stepForwardBy(6).exists)
    XCTAssertEqual(false, app.menuItem_stepForwardBy(5).exists)
  }

  /*
   Tests that IINA has same behavior as mpv for duplicate key bindings: last one wins
   */
 func testDuplicateKeyBinding() throws {
   let configContent = """
   a set window-scale 1.0
   [ seek -6
   [ seek -7
   [ seek -5
   [ seek -8

   ] seek 9
   ] seek 11
   ] seek 13
   ] seek 15
   ] seek 14
   ] seek 10
   ] seek 12
   """

   try launchAppWithConfig(configContent)

   XCTAssertEqual(true, app.menuItem_stepBackwardBy(8).exists)

   XCTAssertEqual(true, app.menuItem_stepForwardBy(12).exists)
 }

  /*
   Tests that IINA selects the 1st eligible binding for use in the menu
   */
 func testMenuItemSelection() throws {
   let configContent = """
   a set window-scale 1.0
   b seek -4
   c seek -5
   e seek -6
   f seek -7
   g seek -7

   q seek 2
   r seek 6
   s seek 7
   t seek 9
   u seek 14
   v seek 10
   """

   try launchAppWithConfig(configContent)

   XCTAssertEqual(true, app.menuItem_stepBackwardBy(5).exists) // "c"

   XCTAssertEqual(true, app.menuItem_stepForwardBy(6).exists)  // "r"
 }

  /*
   Tests that the previous tests work but also that other keys work
   */
 func testSameActionWithMultipleBindings() throws {
   let configContent = """
   a set window-scale 1.0
   b seek -4
   c seek -5
   e seek -6
   f seek -7
   g seek -7

   q seek 2
   r seek 6
   s seek 7
   t seek 9
   u seek 14
   v seek 10
   """

   try launchAppWithConfig(configContent)

   XCTAssertEqual(true, app.menuItem_stepBackwardBy(5).exists) // "c"

   XCTAssertEqual(true, app.menuItem_stepForwardBy(6).exists)  // "r"
 }

  /*
   Tests that the previous tests work but also that other keys work
   */
 func testMultipleBindingsWorkWithMenus() throws {
   let configContent = """
   a set window-scale 1.0
   b set window-scale 2.0
   c set window-scale 0.5
   d set window-scale 0.5
   e set window-scale 2.0
   f set window-scale 0.5
   g set window-scale 2.0
   f set window-scale 1.0
   """

   try launchAppWithConfig(configContent)

   app.menuBarItems["Video"].menuItems["Double Size"].click()
   confirmWindowScale(2.0)

   app.menuBarItems["Video"].menuItems["Half Size"].click()
   confirmMinimumWindowScale()

   app.menuBarItems["Video"].menuItems["Normal Size"].click()
   confirmWindowScale(1.0)

   videoWindow.typeText("b")
   confirmWindowScale(2.0)

   videoWindow.typeText("a")
   confirmWindowScale(1.0)

   videoWindow.typeText("c")
   confirmMinimumWindowScale()

   videoWindow.typeText("e")
   confirmWindowScale(2.0)

   videoWindow.typeText("f")
   confirmWindowScale(1.0)

   videoWindow.typeText("g")
   confirmWindowScale(2.0)
 }

  /*
   Tests that different ways of describing the shift modifier are all treated the same
   */
 func testShiftKeySyntax() throws {
   let configContent = """
   a set window-scale 1.0

   B set window-scale 0.5
   Shift+B set window-scale 2.0

   Shift+E set window-scale 2.0
   E set window-scale 0.5

   Shift+F set window-scale 1.0
   F set window-scale 0.5
   Shift+f set window-scale 2.0
   """

   try launchAppWithConfig(configContent)

   videoWindow.typeText("a")
   confirmWindowScale(1.0)

   videoWindow.typeText("B")
   confirmWindowScale(2.0)

   videoWindow.typeText("E")
   confirmMinimumWindowScale()

   videoWindow.typeText("a")
   confirmWindowScale(1.0)

   videoWindow.typeText("F")
   confirmWindowScale(2.0)
 }
}
