//
//  JustExtension.swift
//  iina
//
//  Created by lhc on 11/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import Just

extension Just.HTTPResult {

  var fileName: String? {
    get {
      guard let field = self.headers["Content-Disposition"] else { return nil }
      let unicodeArray: [UInt8] = field.unicodeScalars.map { UInt8($0.value) }
      let unicodeStr = String(bytes: unicodeArray, encoding: String.Encoding.utf8)!
      return Regex.httpFileName.captures(in: unicodeStr).at(1)
    }
  }

}
