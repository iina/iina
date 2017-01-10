//
//  Logger.swift
//  iina
//
//  Created by skyline on 2017/1/10.
//  Copyright © 2017年 lhc. All rights reserved.
//

import Foundation

class Logger {

  static func log(_ message: String) {
    #if DEBUG
    NSLog("%@", message)
    #endif
  }

  static func fatal(_ message: String, _ block: () -> Void = {}) {
    #if DEBUG
    NSLog("%@", message)
    NSLog(Thread.callStackSymbols.joined(separator: "\n"))
    #endif

    Utility.showAlert(message: "Fatal error: \(message) \nThe application will exit now.")
    block()
    exit(1)
  }

}
