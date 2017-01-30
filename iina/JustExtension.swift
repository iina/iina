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
      return Regex.httpFileName.captures(in: field).at(1)
    }
  }

  func saveDataToFolder(_ url: URL, index: Int) -> URL {
    let url = url.appendingPathComponent("\(index):\(fileName!)")
    do {
      try self.content?.write(to: url)
    } catch {
      Utility.showAlertByKey("cannot_write_to_disk")
    }
    return url
  }
  
}
