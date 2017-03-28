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
    let success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as NSString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              reason,
                                              &assertionID)
    if success == kIOReturnSuccess {
      lock += 1
    } else {
      Utility.showAlert("sleep")
    }
  }

  static func allowSleep() {
    guard lock > 0 else { return }
    let success = IOPMAssertionRelease(assertionID)
    if success == kIOReturnSuccess {
      lock -= 1
    } else {
      // do not show alert here
      Utility.log("Cannot allow display sleep")
    }
  }

}
