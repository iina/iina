//
//  UITestUtil.swift
//  IINA-UI-Tests
//
//  Created by Matt Svoboda on 2022.05.31.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest

extension XCUIApplication {
  func setPref(_ prefName: String, _ prefValue: String) {
    launchArguments += ["-\(prefName)", prefValue]
  }

  func setPrefs(_ prefDict: [String: String]) {
    for (prefName, prefValue) in prefDict {
      launchArguments += ["-\(prefName)", prefValue]
    }
  }
}

extension XCTestCase {
  /*
   Finds and returns the absolute path for the given bundle resource. If running from XCode this will be a different path with each execution.
   */
  public func resolveBundleFilePath(_ filename: String) -> String {
    let filenameURL = URL(fileURLWithPath: filename)
    let fileBaseName = filenameURL.deletingPathExtension().lastPathComponent
    let fileExtension = String(filenameURL.pathExtension)
    let testBundle = Bundle(for: type(of: self))
    let path = testBundle.path(forResource: fileBaseName, ofType: fileExtension)
    XCTAssertNotNil(path)
    return path!
  }

  public func resolveRuntimeVideoPath(tempDirPath: String, videoFilename: String) throws -> String {
    let runtimeVideoPath: String
    if let testVideoDirPath = TEST_VIDEO_DIR_PATH {
      runtimeVideoPath = URL(fileURLWithPath: testVideoDirPath).appendingPathComponent(videoFilename).path
      NSLog("Using supplied override for video path: '\(runtimeVideoPath)'")
    } else {
      let bundleVideoPath = resolveBundleFilePath(videoFilename)
      runtimeVideoPath = URL(fileURLWithPath: tempDirPath).appendingPathComponent(videoFilename).path
      try FileManager.default.copyItem(atPath: bundleVideoPath, toPath: runtimeVideoPath)
      NSLog("Copied '\(videoFilename)' to temp location: '\(runtimeVideoPath)'")
    }
    return runtimeVideoPath
  }
}

public extension FileManager {
    /*
     Convenience method for creating and returning a new MacOS temporary directory in Swift
     */
    func createTempDirectory() throws -> String {
        let tempDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        return tempDirectory
    }
}
