//
//  MPVFilter.swift
//  mpvx
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class MPVFilter: NSObject {
  
  enum FilterType: String {
    case crop = "crop"
  }
  
  static func crop(w: Int?, h: Int?, x: Int?, y: Int?) -> MPVFilter {
    let f = MPVFilter(.crop)
    f.params = ["w": w?.toStr() ?? "", "h": h?.toStr() ?? "", "x": x?.toStr() ?? "", "y": y?.toStr() ?? ""]
    return f
  }
  
  var type: FilterType
  var name: String {
    get {
      return type.rawValue
    }
  }
  var label: String?
  var params: [String: String]?
  
  var stringFormat: String {
    get {
      var str = ""
      if let label = label { str += "@\(label):" }
      str += name
      if params != nil && params!.count > 0 {
        let format = MPVFilter.formats[type]!
        str += "="
        str += format.components(separatedBy: ":").map { params![$0] ?? "" }.joined(separator: ":")
      }
      return str
    }
  }
  
  init(_ type: FilterType) {
    self.type = type
  }
  
  init?(name: String) {
    if let type = FilterType(rawValue: name) {
      self.type = type
    } else {
      return nil
    }
  }
  
  static let formats: [FilterType: String] = [
    .crop: "w:h:x:y"
  ]

}
