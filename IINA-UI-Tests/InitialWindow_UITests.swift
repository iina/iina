//
//  KeyboardNavTest.swift
//  IINA UI Tests
//
//  Created by Matt Svoboda on 2022.05.31.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest

fileprivate let QVGA_RED = "QVGA-Red.mp4"
fileprivate let QVGA_BLUE = "QVGA-Blue.mp4"
fileprivate let QVGA_GREEN = "QVGA-Green.mp4"

// TODO: test XCUIApplication().activate()
class InitialWinXCUIApplication: XCUIApplication {
  var initialWindow: XCUIElement {
    get {
      self.windows.containing(.image, identifier: "iina arrow").element
    }
  }

  // Returns number of recent items in the "Open Recent" menu
  var fileMenu_openRecent_itemCount: Int {
    // subtract for "Clear Menu" and separator (separator is only present if there is at least 1 recent item)
    // (can't yet find a cleaner way to do this)
    max(self.menuItems["Open Recent"].menuItems.count - 2, 0)
  }

  var initialWindow_recentItemsTable_count: Int {
    initialWindow.tables.firstMatch.staticTexts.count
  }

  func initialWindow_recentItemsTable_rowAtIndex(_ index: Int) -> XCUIElement {
    initialWindow.tables.firstMatch.tableRows.element(boundBy: index)
  }

  func initialWindow_recentItemsTable_rowWithText(_ identifier: String) -> XCUIElement {
    self.initialWindow.tables.cells.containing(.staticText, identifier: identifier).element
  }
}

/*
  NOTE ON SIDE EFFECTS: MacOS has generally poor support for integration testing, so note the following:
  - At present, the user account which is running these tests needs to make sure "System Preferences > General > Recent Items" is not set to "None".
  - Wherever possible, these tests make use of application launch arguments to set IINA preferences during testing, which will override the user's
    stored values. Doing so makes use of the volatile NSArgumentDomain which is discarded after running, so those stored user preferences
    should not be affected. However, they won't stop preferences from being written by IINA itself, such as playback position.
  - These tests will clear and ovewrite the current user's recent files for IINA with test data.

  Tips for writing an XCUI test:
  1. Add this line to a test when you want to see the XCUIApplication hierarchy at that moment: `print(app.debugDescription)`
  2. Use XCode (app menu) > Open Developer Tool -> Accessibility Inspector. You can use its target button to inspect any running application
     (although note: the accessibility hierarchy is not exactly the same thing as what XCUI constructs, and should only be used for rough surveying)
  3. Getting labels/titles/strings out of the XCUI hierarchy using queries and predicates does not seem to work at present (MacOS 12.4).
     Assertions can still be written to test for the correct text by querying whether the relevant element exists with that text as the identifier.
  4. XCTAssertTrue(expr, msg) and XCTAssertFalse(expr, msg) don't appear to show their `message` parameter on failure in either the XCode UI or
     in the runtime log. As a workaround, use XCTAssertEquals(true, expr, msg) and XCTAssertEquals(false, expr, msg) when you include a messsage.
 */
class InitialWindow_UITests: XCTestCase {

  private var tempDirPath: String!

  // The most recent app run
  private var app: InitialWinXCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false

    tempDirPath = try FileManager.default.createTempDirectory()
  }

  override func tearDownWithError() throws {
    if let failureCount = testRun?.failureCount, failureCount > 0 {
      print("DEBUG \(app.initialWindow.debugDescription)")
      takeScreenshotOfInitialWindow()
    }
  }

  // MARK: Various util functions

  // Note: this unfortunately seems to take a screenshot of the entire screen which contains the window
  private func takeScreenshotOfInitialWindow() {
    let screenshot = app.initialWindow.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  // Launches a single instance of IINA (via XCUIApplication) with the given args and prefs, if any.
  // The caller is expected to handle termination.
  func launchApp(args: [String] = [], prefs: [String: String] = [:]) {
    app = InitialWinXCUIApplication()
    for arg in args {
      app.launchArguments.append(arg)
    }

    if prefs.count > 0 {
      app.setPrefs(prefs)
    }
    app.launch()
  }

  // MARK: Reusable activities

  // Opens IINA & clears playback history - then quits. Returns nothing on success.
  @discardableResult
  private func clearRecentDocuments() -> Result<Void, Error> {
    return XCTContext.runActivity(named: "ClearRecentDocuments") { activity in
      launchApp()

      // Open Prefs window
      app.initialWindow.typeKey(",", modifierFlags:.command)
      let prefsWin = app.windows["Preferences"]

      // Prefs > Utilities > Clear History
      prefsWin.tables.staticTexts["Utilities"].click()
      prefsWin.buttons["FunctionalButtonClearHistory"].click()
      prefsWin.sheets["alert"].buttons["OK"].click()
      prefsWin.buttons[XCUIIdentifierCloseWindow].click()

      // Just quit. Scripting is extremely limited and cannot click the app icon to restore Welcome window
      app.initialWindow.typeKey("q", modifierFlags:.command)

      return .success(Void())
    }
  }

  /*
   Launches IINA with the given video file and prefs, then quits.
   Useful for building playback history.
   Param `videoName` must be a video whhich is part of the project's bundle resources
   */
  @discardableResult
  private func launchVideoThenQuit(_ videoName: String, prefs: [String: String]) throws -> Result<Void, Error> {
    return try XCTContext.runActivity(named: "LaunchVideoThenQuit") { activity in
      let bundleVideoPath = resolveBundleFilePath(videoName)
      let runtimeVideoPath = URL(fileURLWithPath: tempDirPath).appendingPathComponent(videoName).path
      try FileManager.default.copyItem(atPath: bundleVideoPath, toPath: runtimeVideoPath)
      NSLog("Copied '\(videoName)' to temp location: '\(runtimeVideoPath)'")

      launchApp(args: [runtimeVideoPath], prefs: prefs)

      let videoWindow = app.windows.element(matching: NSPredicate(format: "title BEGINSWITH '\(videoName)'"))
      // this has the nice side effect of failing if the window isn't found
      videoWindow.typeKey("q", modifierFlags:.command)

      return .success(Void())
    }
  }

  /*
   Verifies the current list of recent files in the InitialWindow of the given `InitialWinXCUIApplication`.
   - Assumes that IINA's `recordRecentFiles` preference is enabled, and the MacOS "Recent Items" system preferences is not None.
   - If `isResumePlayEnabled==true`, then the first recent item will be a button, and the remainder will be in the table.
   - If `isResumePlayEnabled==false`, then all recent items will be in the table.
   */
  private func verifyRecentFilesState(_ expectedRecentItems: [String], selectionIndex: Int, isResumeLastPositionEnabled: Bool){
    var expectedRowCountInTable = expectedRecentItems.count
    if isResumeLastPositionEnabled && expectedRowCountInTable > 0 {
      expectedRowCountInTable -= 1
    }

    let _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Waiting!")], timeout: 2.0)

    // InitialWindow: ResumeLastPlayedItem button
    for videoName in expectedRecentItems {
      if isResumeLastPositionEnabled && videoName == expectedRecentItems[0] {
        // This is not actually a button, and most of the hierarchy is invisible to XCUI, but we can be clever.
        // If the button exists we can find a label with value "Resume" and another label with the video name.
        // These will both be inside the InitialWindow element BUT not inside the table.
        XCTAssertEqual(true, app.initialWindow.staticTexts["Resume"].exists, "Resume button is missing: \(videoName) (isResumeLastPositionEnabled=\(isResumeLastPositionEnabled))")

        // We found "Resume", so we know a button exists. Now count the video labels, which will include the button and any in the table.
        // In our tests, the given video should be either a button or a table row, but not both.
        let videoNameLabels = app.initialWindow.staticTexts.matching(NSPredicate(format: "value = '\(videoName)'"))
        XCTAssertEqual(1, videoNameLabels.count, "Expected only 1 listing for \(videoName) (expected Resume Last Playback button only!)")
      } else {
        XCTAssertEqual(false, app.initialWindow.buttons[videoName].exists, "Found Resume button which should not be present: \(videoName)")
      }
    }

    // InitialWindow: RecentItems table
    XCTAssertEqual(app.initialWindow_recentItemsTable_count, expectedRowCountInTable)

    for (itemIndex, label) in expectedRecentItems.enumerated() {
      var tableIndex = itemIndex
      if isResumeLastPositionEnabled {
        if itemIndex == 0 {
          continue
        } else {
          tableIndex -= 1
        }
      }
      let row = app.initialWindow_recentItemsTable_rowAtIndex(tableIndex)
      XCTAssertEqual(true, row.staticTexts[label].exists, "Expected to find \(label) at row \(tableIndex) in table")
      XCTAssertEqual(row.isSelected, selectionIndex == itemIndex)
    }

    // File > Open Recent
    XCTAssertEqual(app.fileMenu_openRecent_itemCount, expectedRecentItems.count)
    for itemName in expectedRecentItems {
      XCTAssertTrue(app.menuItems["Open Recent"].menuItems[itemName].exists)
    }
  }

  private func runLongTestAndVerify_RecentFiles_Yes(resumeLastPosition: Bool) throws {
    let resumeLastPosition = resumeLastPosition
    let prefs = [
      "recordRecentFiles" : "true",
      "resumeLastPosition" : String(resumeLastPosition),
    ]

    // Setup: clear recent documents
    clearRecentDocuments()

    // ------------
    // Part 1: Play RED video

    try launchVideoThenQuit(QVGA_RED, prefs: prefs)
    launchApp(prefs: prefs)

    verifyRecentFilesState([QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: can't go down
    app.initialWindow.typeKey(.downArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: can't go up
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // ------------
    // PART 2: Play BLUE video

    try launchVideoThenQuit(QVGA_BLUE, prefs: prefs)
    launchApp(prefs: prefs)

    // verify initial
    verifyRecentFilesState([QVGA_BLUE, QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: can't go up
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_BLUE, QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: down
    app.initialWindow.typeKey(.downArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_BLUE, QVGA_RED], selectionIndex: 1, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: can't go down
    app.initialWindow.typeKey(.downArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_BLUE, QVGA_RED], selectionIndex: 1, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: up
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_BLUE, QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: can't go up
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_BLUE, QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // ------------
    // PART 3: Play BLACK video

    try launchVideoThenQuit(QVGA_GREEN, prefs: prefs)
    launchApp(prefs: prefs)

    // verify initial
    verifyRecentFilesState([QVGA_GREEN, QVGA_BLUE, QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: can't go UP
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_GREEN, QVGA_BLUE, QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: DOWN to Blue
    app.initialWindow.typeKey(.downArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_GREEN, QVGA_BLUE, QVGA_RED], selectionIndex: 1, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: DOWN to Green
    app.initialWindow.typeKey(.downArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_GREEN, QVGA_BLUE, QVGA_RED], selectionIndex: 2, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: can't go DOWN
    app.initialWindow.typeKey(.downArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_GREEN, QVGA_BLUE, QVGA_RED], selectionIndex: 2, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: UP to Blue
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_GREEN, QVGA_BLUE, QVGA_RED], selectionIndex: 1, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: UP to Red
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_GREEN, QVGA_BLUE, QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

    // verify: can't go UP
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    verifyRecentFilesState([QVGA_GREEN, QVGA_BLUE, QVGA_RED], selectionIndex: 0, isResumeLastPositionEnabled: resumeLastPosition)

  }

  // MARK: UI Tests

  /*
   RecordRecentFiles:NO & ResumeLastFile:NO
   When `recordRecentFiles==false`, all recent files lists should be empty, and stay empty.
   */
  func testListDisplayAndArrowKeys_RecentFilesOff_ResumeLastPositionOff() throws {
    let prefs = [
      "recordRecentFiles": "false",
      "resumeLastPosition": "false"
    ]

    clearRecentDocuments()

    func verifyInitialWindowIsEmpty(_ app: InitialWinXCUIApplication) {
      XCTAssertEqual(app.fileMenu_openRecent_itemCount, 0)
      XCTAssertFalse(app.initialWindow.buttons[QVGA_RED].exists)
      XCTAssertFalse(app.initialWindow.buttons[QVGA_BLUE].exists)
      XCTAssertFalse(app.initialWindow.buttons[QVGA_GREEN].exists)
      XCTAssertEqual(app.initialWindow_recentItemsTable_count, 0)
    }

    launchApp(prefs: prefs)

    // no recent files, no last position
    verifyInitialWindowIsEmpty(app)

    app.initialWindow.typeKey(.downArrow, modifierFlags:.function)
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    app.initialWindow.typeText("\r")
    // make sure welome win is still present (e.g. no video was opened)
    app.initialWindow.images["iina arrow"].click()
    app.initialWindow.typeKey("q", modifierFlags:.command)

    // Play Blue video, which should add a new menu item to File > Recent Items
    try launchVideoThenQuit(QVGA_BLUE, prefs: prefs)

    launchApp(prefs: prefs)
    verifyInitialWindowIsEmpty(app)
  }

  /*
   RecordRecentFiles:NO & ResumeLastFile:YES
   Verifies that when `recordRecentFiles==false`, even if `resumeLastPosition==true`, no recent files will be tracked or displayed.
   */
  func testListDisplayAndArrowKeys_RecentFilesOff_ResumeLastPositionOn() throws {
    let prefs = [
      "recordRecentFiles" : "false",
      "resumeLastPosition" : "true",
    ]

    clearRecentDocuments()

    func verifyInitialWindowIsEmpty() {
      XCTAssertEqual(app.fileMenu_openRecent_itemCount, 0)
      XCTAssertFalse(app.initialWindow.buttons[QVGA_RED].exists)
      XCTAssertFalse(app.initialWindow.buttons[QVGA_BLUE].exists)
      XCTAssertFalse(app.initialWindow.buttons[QVGA_GREEN].exists)
      XCTAssertEqual(app.initialWindow_recentItemsTable_count, 0)
    }

    launchApp(prefs: prefs)

    // no recent files, no last position
    verifyInitialWindowIsEmpty()

    app.initialWindow.typeKey(.downArrow, modifierFlags:.function)
    app.initialWindow.typeKey(.upArrow, modifierFlags:.function)
    app.initialWindow.typeText("\r")
    // make sure welome win is still present (e.g. no video was opened)
    app.initialWindow.images["iina arrow"].click()
    app.initialWindow.typeKey("q", modifierFlags:.command)

    // Play Blue video, which should add a new menu item to File > Recent Items
    try launchVideoThenQuit(QVGA_RED, prefs: prefs)

    launchApp(prefs: prefs)
    verifyInitialWindowIsEmpty()
  }

  /*
   RecordRecentFiles:YES & ResumeLastFile:YES
   */
  func testListDisplayAndArrowKeys_RecentFilesOn_ResumeLastPositionOn() throws {
    try runLongTestAndVerify_RecentFiles_Yes(resumeLastPosition: true)
  }

  /*
   RecordRecentFiles:YES & ResumeLastFile:NO
   */
  func testListDisplayAndArrowKeys_RecentFilesOn_ResumeLastPositionOff() throws {
    try runLongTestAndVerify_RecentFiles_Yes(resumeLastPosition: false)
  }

//  /*
//  RecordRecentFiles:YES & ResumeLastFile:YES
//   */
//  func testListDisplayAndArrowKeys_RecentFilesOn_ResumeLastPositionOn() throws {
//    try runLongTestAndVerify_RecentFiles_Yes(resumeLastPosition: true)
//  }
//
//  /*
//   Recent Files Tracking = enabled
//   Resume Last Position = disabled
//   */
//  func testListDisplayAndArrowKeys_RecentFilesOn_ResumeLastPositionOff() throws {
//    try runLongTestAndVerify_RecentFiles_Yes(resumeLastPosition: false)
//  }

}
