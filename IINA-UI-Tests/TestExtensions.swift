//
//  UITestUtil.swift
//  IINA-UI-Tests
//
//  Created by Matthew Svoboda on 2022.05.31.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest
import Foundation

// in seconds
let DEFAULT_XCUI_TIMEOUT = TimeInterval(10)

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
