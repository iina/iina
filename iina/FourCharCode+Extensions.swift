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
    self = NSHFSTypeCodeFromFileType("'\(stringLiteral)'")
  }
  
}
