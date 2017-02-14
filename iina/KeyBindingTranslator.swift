//
//  KeyBindingTranslator.swift
//  iina
//
//  Created by lhc on 6/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class KeyBindingTranslator {

  static func string(fromCriterions criterions: [Criterion]) -> String {
    var mapped = criterions.filter { !$0.isPlaceholder }.map { $0.mpvCommandValue }

    let firstName = (criterions[0] as! TextCriterion).name

    // special cases

    /// [add property add|minus value] (length: 4)s
    if firstName == "add" {
      // - format the number
      if var doubleValue = Double(mapped.popLast()!) {
        let sign = mapped.popLast()
        if sign == "minus" {
          doubleValue = -doubleValue
        }
        mapped.append(doubleValue.prettyFormat())
      } else {
        mapped.removeLast()
      }
    }

    /// [seek forward|backward|seek-to value flag] (length: 4)
    else if firstName == "seek" {
      // - relative is default value
      if mapped[3] == "relative" {
        mapped.removeLast()
      }
      // - format the number
      if var doubleValue = Double(mapped[2]) {
        if mapped[1] == "backward" {
          doubleValue = -doubleValue
        }
        mapped[2] = doubleValue.prettyFormat()
      }
      mapped.remove(at: 1)
    }
    return mapped.joined(separator: " ")
  }

}
