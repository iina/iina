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
    if let path = Bundle.main.path(forResource: name, ofType: "lua", inDirectory: "scripts") {
      self.filePath = path
      self.type = .iina
    } else {
      return nil
    }
  }

  init(filePath: String) {
    self.filePath = filePath
    self.type = .custom
  }

}
