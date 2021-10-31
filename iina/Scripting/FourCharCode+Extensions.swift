//
//  FourCharCode+Extensions.swift
//  iina
//
//  Created by Nate Weaver on 2020-03-08.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation

extension FourCharCode: ExpressibleByStringLiteral {

  public typealias StringLiteralType = String

  public init(stringLiteral: String) {
    // Match NSHFSTypeCodeFromFileType() behavior: Return 0 for invalid codes.
    guard stringLiteral.count == 4, let data = stringLiteral.data(using: .macOSRoman) else {
      self = 0
      return
    }

    self = FourCharCode(data[0]) << 24 | FourCharCode(data[1]) << 16 | FourCharCode(data[2]) << 8 | FourCharCode(data[3])
  }

}
