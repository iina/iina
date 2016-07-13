//
//  EnvironmentChecker.swift
//  mpvx
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Foundation

class Environment {

  static func checkMpvPath() -> Bool {
    // try get path from AppData
    if let pathFromAppData = AppData.mpvPath {
      if (validateMpvPath(path: pathFromAppData)) {
        // valid path from AppData
        return true
      }
    }
    // else try search for mpv path
    if let tryGetMpvPath = getMpvPath() {
      AppData.mpvPath = tryGetMpvPath
      return true
    } else {
      // cannot find mpv path
      return false
    }
  }

  private static func getMpvPath() -> String? {
    let shellPath = ProcessInfo.processInfo.environment["SHELL"]
    let task = Task()
    task.standardOutput = Pipe()
    task.launchPath = shellPath
    task.arguments = ["-l", "-c", "which mpv"]
    task.launch()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
      Utility.log("Cannot locate mpv \(task.terminationStatus)")
      return nil
    } else {
      let output = task.standardOutput?.fileHandleForReading.availableData
      let path = String.init(data: output!, encoding: String.Encoding.utf8)!
      Utility.log("Found mpv path \(path)")
      return path
    }
  }
  
  private static func validateMpvPath(path: String) -> Bool {
    return true;
  }
}
