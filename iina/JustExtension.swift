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

  func saveDataToFolder(_ url: URL, index: Int) -> URL {
    let url = url.appendingPathComponent("\(index):\(fileName!)")
    do {
      try self.content?.write(to: url)
    } catch {
      Utility.showAlert(message: "Cannot write data to disk.")
    }
    return url
  }

}
