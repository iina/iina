//
//  ISO639_2Helper.swift
//  iina
//
//  Created by lhc on 14/3/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation


class ISO639_2Helper {

  struct Language {
    var code: String
    var name: [String]

    var description: String {
      return "\(name[0]) (\(code))"
    }
  }

  static let languages: [Language] = {
    var result: [Language] = []
    for (k, v) in dictionary {
      let names = v.characters.split(separator: ";").map { String($0) }
      result.append(Language(code: k, name: names))
    }
    return result
  }()

  static let dictionary: [String: String] = {
    let filePath = Bundle.main.path(forResource: "ISO639_2", ofType: "strings")!
    return NSDictionary(contentsOfFile: filePath) as! [String : String]
  }()

}
