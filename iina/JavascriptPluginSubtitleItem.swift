//
//  JavascriptPluginSubtitleItem.swift
//  iina
//
//  Created by Collider LI on 11/7/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa
import JavaScriptCore

@objc protocol JavascriptPluginSubtitleItemExportable: JSExport {
  var data: JSValue { get set }
  var __iinsSubItem: Bool { get }
}

class JavascriptPluginSubtitleItem: NSObject, JavascriptPluginSubtitleItemExportable {
  var data: JSValue
  var __iinsSubItem: Bool

  init(data: JSValue) {
    self.data = data
    self.__iinsSubItem = true
  }
}
