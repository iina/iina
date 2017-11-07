//
//  BooleanColorTransformer.swift
//  iina
//
//  Created by Yuze Jiang on 11/7/17.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

@objc(BooleanColorTransformer) class BooleanColorTransformer : ValueTransformer {

  override class func allowsReverseTransformation() -> Bool {
    return false
  }

  override class func transformedValueClass() -> AnyClass {
    return NSColor.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    return (value as! Bool) ? NSColor.controlTextColor : NSColor.disabledControlTextColor
  }
}
