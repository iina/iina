//
//  FileSize.swift
//  iina
//
//  Created by lhc on 26/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class FileSize {

  enum Unit: Int {
    case b = 1
    case kb = 1024
    case mb = 1048576
    case gb = 1073741824

    var string: String {
      get {
        switch self {
        case .b: return "B"
        case .kb: return "K"
        case .mb: return "M"
        case .gb: return "G"
        }
      }
    }
  }

  static private let unitValues = [Unit.gb, Unit.mb, Unit.kb, Unit.b]

  static func format(_ number: Int, unit: Unit, digits: Int = 2) -> String {
    let bytes = number * unit.rawValue
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = digits

    for (_, v) in unitValues.enumerated() {
      if bytes >= v.rawValue {
        let num = NSNumber(value: Double(bytes) / Double(v.rawValue))
        let str = formatter.string(from: num)
        return str == nil ? "Error" : "\(str!)\(v.string)"
      }
    }

    return "0B"
  }

}
