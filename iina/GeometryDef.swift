//
//  GeometryDef.swift
//  iina
//
//  Created by Collider LI on 20/12/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

struct GeometryDef {
  var x: String?, y: String?, w: String?, h: String?, xSign: String?, ySign: String?

  static func parse(_ geometryString: String) -> GeometryDef? {
    // guard option value
    guard !geometryString.isEmpty else { return nil }
    // match the string, replace empty group by nil
    let captures: [String?] = Regex.geometry.captures(in: geometryString).map { $0.isEmpty ? nil : $0 }
    // guard matches
    guard captures.count == 10 else { return nil }
    // return struct
    return GeometryDef(x: captures[7],
                       y: captures[9],
                       w: captures[2],
                       h: captures[4],
                       xSign: captures[6],
                       ySign: captures[8])
  }

}
