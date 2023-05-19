//
//  PowerSource.swift
//  iina
//
//  Created by Collider LI on 13/12/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa
import IOKit.ps

class PowerSource {

  var type: String?

  var currentCapacity: Int?

  class func getList() -> [PowerSource] {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

    var result: [PowerSource] = []
    for item in list {
      if let desc = IOPSGetPowerSourceDescription(info, item).takeUnretainedValue() as? [String: Any] {
        let ps = PowerSource()
        ps.type = desc[kIOPSTypeKey] as? String
        ps.currentCapacity = desc[kIOPSCurrentCapacityKey] as? Int
        result.append(ps)
      }
    }
    return result
  }

}
