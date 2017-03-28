//
//  ScriptLoader.swift
//  iina
//
//  Created by lhc on 3/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

class ScriptLoader {

  private var list: [LuaScript] = []

  var stringForOption: String {
    get {
      return list.map { $0.filePath }.joined(separator: ",")
    }
  }

  func add(defaultScript name: String) {
    if let script = LuaScript(defaultName: name) {
      list.append(script)
    } else {
      Utility.showAlert("error_loading_script")
    }
  }

}
