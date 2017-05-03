//
//  SleepPreventer.swift
//  iina
//
//  Created by lhc on 6/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import IOKit.pwr_mgt


class SleepPreventer: NSObject {

  static private let reason = "IINA is playing video" as CFString

  static private var assertionID = IOPMAssertionID()

  static private var lock = 0

  static func preventSleep() {
    if lock != 0 {
      lock += 1
      return
    }
    
    let success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as NSString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              reason,
                                              &assertionID)
    if success == kIOReturnSuccess {
      lock = 1
    } else {
      Utility.showAlert("sleep")
    }
  }

  static func allowSleep() {
    if lock > 1 {
      lock -= 1
      return
    } else {
      let success = IOPMAssertionRelease(assertionID)
      if success == kIOReturnSuccess {
        lock = 0
      } else {
        Utility.log("Cannot allow display sleep")
      }
    }
  }

}
