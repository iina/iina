// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import XCTest

final class TouchPlaybackTests: XCTestCase {
    func testPlaybackToolsAndSavedPlaylistUI() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This UI case uses a loopback fixture server on the simulator host.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.terminate()
        func tapCenter(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 3))
            // The simulator's computed AX hit point can fall at the edge of a
            // neighboring sidebar/menu item. Use the visible element's center.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        app.open(URL(string: "iinapad://open?url=http%3A%2F%2F127.0.0.1%3A8769%2Fplayback.mp4")!)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 12))
        app.buttons["Pause"].tap()
        app.buttons["Quick settings"].firstMatch.tap()
        tapCenter(app.buttons["quickSettingsTab_layout"])
        let dock = app.switches["Dock playback controls"]
        if !dock.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.30)))
        }
        XCTAssertTrue(dock.waitForExistence(timeout: 3))
        if dock.value as? String != "1" { dock.tap() }
        let layout = XCTAttachment(screenshot: app.screenshot())
        layout.name = "Touch controls and docked layout"
        layout.lifetime = .keepAlways; add(layout)
        app.buttons["Close sidebar"].tap()

        func tools() {
            let button = app.descendants(matching: .any).matching(identifier: "playbackToolsMenu").firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            tapCenter(button)
        }
        tools(); app.buttons["Jump to Time…"].tap()
        let field = app.textFields["jumpTimestamp"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        if let value = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText("00:04")
        app.buttons["Jump"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let position = try XCTUnwrap(Double(try XCTUnwrap(app.sliders["Playback position"].value as? String)))
        XCTAssertEqual(position, 4, accuracy: 0.15)
        tools(); tapCenter(app.buttons["Next Frame"])
        Thread.sleep(forTimeInterval: 0.5)
        if !app.buttons["Capture Frame…"].exists { tools() }
        tapCenter(app.buttons["Capture Frame…"])
        XCTAssertTrue(app.buttons["Save or Share"].waitForExistence(timeout: 5))
        let frame = XCTAttachment(screenshot: app.screenshot())
        frame.name = "Clean frame capture"
        frame.lifetime = .keepAlways; add(frame)
        app.buttons["Done"].tap()

        app.buttons["Playlist and chapters"].firstMatch.tap()
        tapCenter(app.buttons["savePlaylistButton"])
        app.alerts.textFields.firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText("UI smoke playlist")
        app.alerts.buttons["Save"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        tapCenter(app.buttons["savedPlaylistsButton"])
        XCTAssertTrue(app.staticTexts["UI smoke playlist"].waitForExistence(timeout: 5))
        let playlist = XCTAttachment(screenshot: app.screenshot())
        playlist.name = "Saved playlist library"
        playlist.lifetime = .keepAlways; add(playlist)
        app.cells.containing(.staticText, identifier: "UI smoke playlist").firstMatch.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        app.buttons["Done"].tap()
        app.terminate()
        #endif
    }

    func testBottomSpeedMenuDuringPlayback() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This UI case uses a loopback fixture server on the simulator's host.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        let speed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback speed,")).firstMatch
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        func position() throws -> Double {
            let value = try XCTUnwrap(app.sliders["Playback position"].value as? String)
            return try XCTUnwrap(Double(value))
        }
        for ext in ["mp4", "mkv"] {
            app.open(URL(string: "iinapad://open?url=http%3A%2F%2F127.0.0.1%3A8769%2Fplayback.\(ext)")!)
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 12))
            center.doubleTap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 2))
            if !speed.exists { center.tap() }
            XCTAssertTrue(speed.waitForExistence(timeout: 3))
            speed.tap()
            app.buttons["0.25×"].tap()
            XCTAssertTrue(speed.label.contains("0.25"))
            app.buttons["Back 10 seconds"].tap()
            app.buttons["Play"].tap()
            // Keep the menu open beyond the controls' four-second hide timer.
            speed.tap()
            Thread.sleep(forTimeInterval: 4.5)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Bottom playback speed picker \(ext)"
            capture.lifetime = .keepAlways
            add(capture)
            app.buttons["2×"].tap()
            if !speed.exists { center.tap() }
            XCTAssertTrue(speed.waitForExistence(timeout: 2))
            XCTAssertTrue(speed.label.contains("2 times"))
            XCTAssertTrue(app.buttons["Pause"].exists, "The speed choice paused playback")
            let start = try position(), wall = Date()
            Thread.sleep(forTimeInterval: 1)
            let measured = (try position() - start) / Date().timeIntervalSince(wall)
            XCTAssertEqual(measured, 2, accuracy: 0.75, "The bottom menu changed its label without applying 2×")
        }
        app.terminate()
        #endif
    }

    func testVideoTouchGestures() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This UI case uses a loopback fixture server on the simulator's host.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        let media = URL(string: "iinapad://open?url=http%3A%2F%2F127.0.0.1%3A8769%2Fplayback.mp4")!
        let speed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Playback speed,")).firstMatch
        func openVideo() throws {
            app.open(media)
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 12))
            // The twelve-second fixture must not run out during UI-driver setup.
            app.buttons["Pause"].tap()
            if !speed.exists {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
            }
            XCTAssertTrue(speed.waitForExistence(timeout: 3))
            speed.tap()
            app.buttons["0.5×"].tap()
            XCTAssertTrue(speed.label.contains("0.5"))
            app.buttons["Back 10 seconds"].tap()
            XCTAssertLessThanOrEqual(try position(), 0.1)
            app.buttons["Play"].tap()
        }
        func position() throws -> Double {
            let value = try XCTUnwrap(app.sliders["Playback position"].value as? String)
            return try XCTUnwrap(Double(value), "The timeline did not report a numeric playback position: \(value)")
        }
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.42))
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.42))

        try openVideo()
        let start = try position()
        center.press(forDuration: 2)
        XCTAssertGreaterThanOrEqual(try position() - start, 2, "The actual long press did not speed up playback")
        XCTAssertTrue(speed.label.contains("0.5"), "Release did not restore the selected rate")
        XCTAssertTrue(app.buttons["Pause"].exists, "The hold accidentally paused playback")

        try openVideo()
        left.press(forDuration: 0.05, thenDragTo: right)
        let forward = app.staticTexts["Fast forward 10 seconds"]
        XCTAssertTrue(forward.waitForExistence(timeout: 1))
        XCTAssertGreaterThanOrEqual(try position(), 10)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Swipe forward 10 seconds"
        capture.lifetime = .keepAlways
        add(capture)

        try openVideo()
        app.buttons["Forward 10 seconds"].tap()
        right.press(forDuration: 0.05, thenDragTo: left)
        XCTAssertTrue(app.staticTexts["Rewind 10 seconds"].waitForExistence(timeout: 1))
        XCTAssertLessThanOrEqual(try position(), 3)
        center.doubleTap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 2), "Double-tap pause stopped working")
        app.terminate()
        #endif
    }
}
