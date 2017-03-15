//
//  Formatters.swift
//  iina
//
//  Created by lhc on 13/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class RestrictedNumberFormatter : NumberFormatter {

  init(_ min: Double?, max: Double?, isDecimal: Bool) {
    super.init()
    if isDecimal {
      self.numberStyle = .decimal
    }
    if let minValue = min {
      minimum = minValue as NSNumber?
    }
    if let maxValue = max {
      maximum = maxValue as NSNumber?
    }
  }

  override init() {
    super.init()
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
    if partialString.isEmpty {
      return true
    }

    var filteredString = partialString
    if self.numberStyle == .decimal {
      filteredString = filteredString.replacingOccurrences(of: ".", with: "")
    }

    if self.minimum == nil || self.minimum!.floatValue < 0 {
      filteredString = filteredString.replacingOccurrences(of: "-", with: "")
    }

    if filteredString.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
      NSBeep()
      return false
    }
    return true
  }

}
