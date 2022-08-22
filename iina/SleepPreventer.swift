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
  /// In issue [#3478](https://github.com/iina/iina/issues/3478) `IOPMAssertionCreateWithName` was
  /// returning returning the error code `kIOReturnNoMemory`. At that time a`IOPMAssertionCreateWithName` failure resulted
  /// in IINA crashing due to IINA not using the main thread to display a `NSAlert`. That was fixed in IINA 1.3.0.
  ///
  /// The reason why `powerd` had run out of memory was traced to the macOS `coreaudiod` daemon creating thousands of
  /// assertions. The `coreaudiod` daemon was also frequently crashing and restarting. This was traced to audio related software
  /// from [Rogue Amoeba](https://rogueamoeba.com/) which includes the [Audio Capture Engine (ACE)](https://www.rogueamoeba.com/licensing/ace/)
  /// driver that is installed into the macOS daemon `coreaudiod`. The user upgraded to the latest version of ACE and the
  /// problem no longer reproduced.
  ///
  /// In issue [#3842](https://github.com/iina/iina/issues/3842) the same error code, `kIOReturnNoMemory`,
  /// was being returned, but a new root cause was seen. It appears at this time that Apple has introduced a regression into the
  /// `powerd` daemon such that it internally generates thousands of assertions running itself out of memory. Another
  /// symptom of this is the `powerd` daemon consuming 100% CPU causing the Mac's fans to run at full speed. Some of
  /// the other reports from users in that issue appear to be due to the ACE driver.
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
