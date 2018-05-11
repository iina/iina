//
//  LuaScript.swift
//  iina
//
//  Created by lhc on 3/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class LuaScript {

  enum ScriptType {
    case iina, custom
  }

  var filePath: String
  var type: ScriptType

  init?(defaultName name: String) {
    guard let path = Bundle.main.path(forResource: name, ofType: "lua", inDirectory: "scripts") else { return nil }
    self.filePath = path
    self.type = .iina
  }

  init(filePath: String) {
    self.filePath = filePath
    self.type = .custom
  }
}
