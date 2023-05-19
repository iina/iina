//
//  MPVHook.swift
//  iina
//
//  Created by Collider LI on 28/2/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation

struct MPVHook: RawRepresentable {
  typealias RawValue = String
  var rawValue: RawValue

  init(_ string: String) { self.rawValue = string }
  init?(rawValue: RawValue) { self.rawValue = rawValue }
}
