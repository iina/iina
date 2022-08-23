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

  static private var haveShownAlert = false

  static private var preventedSleep = false

  /// Ask macOS to not dim or sleep the display.
  ///
  /// This method uses the macOS function [IOPMAssertionCreateWithName](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname)
  /// to create a [kIOPMAssertionTypeNoDisplaySleep](https://developer.apple.com/documentation/iokit/kiopmassertiontypenodisplaysleep)
  /// assertion with the macOS power management system.
  /// - Attention: This portion of macOS has proven to be **unreliable**.
  ///
  /// It is important to inform the user that macOS power management is malfunctioning as this can explain
  /// why there is trouble with audio/video playback. For this reason IINA posts an alert if  `IOPMAssertionCreateWithName` fails.
  ///
  /// As this alert can be irritating to users the alert is only displayed once per IINA invocation. In addition
  /// the alert supports a [suppression button](https://developer.apple.com/documentation/appkit/nsalert/1535196-showssuppressionbutton)
  /// to allow the user to permanently suppress this alert. To restore the alert the following preference must
  /// be reset using [Terminal](https://support.apple.com/guide/terminal/welcome/mac):
  /// ```bash
  /// defaults write com.colliderli.iina suppressCannotPreventDisplaySleep 0
  /// ```
  /// Hopefully the quality of macOS will improve and there will not be a need to provide a UI to control this preference.
  ///
  /// See issues [#3842](https://github.com/iina/iina/issues/3842) and [#3478](https://github.com/iina/iina/issues/3478) for details on the macOS failure.
  static func preventSleep() {
    if preventedSleep {
      return
    }

    let success = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as NSString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              reason,
                                              &assertionID)
    guard success != kIOReturnSuccess else {
      preventedSleep = true
      return
    }
    // Something has gone wrong with power management on this Mac.
    Logger.log(String(format: "IOPMAssertionCreateWithName returned 0x%0X8, \(String(cString: mach_error_string(success)))",
                      success), level: .error)
    Logger.log(
      "Cannot prevent display sleep because macOS power management is broken on this machine",
      level: .error)
    // To avoid irritating users only display this alert once per IINA invocation and support a
    // button to allow the alert to be permanently suppressed.
    guard !haveShownAlert else { return }
    haveShownAlert = true
    DispatchQueue.main.async {
      Utility.showAlert("sleep", arguments: [success],
                        suppressionKey: .suppressCannotPreventDisplaySleep)
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
        Logger.log("Cannot allow display sleep", level: .warning)
      }
    }
  }

}
