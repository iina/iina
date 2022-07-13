//
//  TestConstants.swift
//  IINA-UI-Tests
//
//  Created by Matthew Svoboda on 2022.06.06.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest

// Supply a path to local videos directory here if you want to use a custom path to the test videos,
// instead of copying videos stored in the bundle to a temp directory, which can introduce complications
let TEST_VIDEO_DIR_PATH: String? = nil

let QVGA_RED = "QVGA-Red.mp4"
let QVGA_BLUE = "QVGA-Blue.mp4"
let QVGA_GREEN = "QVGA-Green.mp4"
let QVGA_BLACK = "QVGA-Black.mp4"

let QVGA_WIDTH: Int = 320
let QVGA_HEIGHT: Int = 240

// in seconds
let DEFAULT_XCUI_TIMEOUT = TimeInterval(10)
