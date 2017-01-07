//
//  Formatters.swift
//  iina
//
//  Created by lhc on 13/8/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class DecimalFormatter : NumberFormatter {

  override init() {
    super.init()
    self.numberStyle = .decimal
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
    return true
  }
}
