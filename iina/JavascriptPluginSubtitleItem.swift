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
  var desc: JSValue? { get set }
  func __setDownlaodCallback(_ callback: JSValue)
}

class JavascriptPluginSubtitleItem: NSObject, JavascriptPluginSubtitleItemExportable {
  var data: JSValue
  var desc: JSValue?
  var download: JSValue?

  init(data: JSValue, desc: JSValue?) {
    self.data = data
    self.desc = desc
  }

  func __setDownlaodCallback(_ callback: JSValue) {
    download = callback;
  }
}
