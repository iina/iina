//
//  Parameter.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class Parameter: NSObject {
  static let basicParameter = [
    "profile": "pseudo-gui",
    "quiet": "",
  ]

  static func defaultParameter() -> [String] {
    var p = basicParameter
    p["vd-lavc-threads"] = String(ProcessInfo.processInfo.processorCount)
    p["cache"] = "8192"
    return parameterFormatter(p)
  }

  private static func parameterFormatter(_ dic: [String: String]) -> [String] {
    var result: [String] = []
    for (k, v) in dic {
      result.append("--\(k)=\(v)")
    }
    return result
  }
}
