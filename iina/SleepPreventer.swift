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

  static func preventSleep() {
    let success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as NSString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              reason,
                                              &assertionID)
    if success != kIOReturnSuccess {
      Utility.showAlert(message: "Cannot prevent display sleep")
    }
  }

  static func allowSleep() {
    let success = IOPMAssertionRelease(assertionID)
    if success != kIOReturnSuccess {
      Utility.showAlert(message: "Cannot allow display sleep")
    }
  }

}
