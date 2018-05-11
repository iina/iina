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

  static private var preventedSleep = false

  static func preventSleep() {
    if preventedSleep {
      return
    }

    let success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as NSString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              reason,
                                              &assertionID)
    if success == kIOReturnSuccess {
      preventedSleep = true
    } else {
      Utility.showAlert("sleep")
    }
  }

  static func allowSleep() {
    if !preventedSleep {
      return
    } else {
      let success = IOPMAssertionRelease(assertionID)
      if success == kIOReturnSuccess {
        preventedSleep = false
      } else {
        Utility.log("Cannot allow display sleep")
      }
    }
  }

}
