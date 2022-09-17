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
  var data: JSValue { get }
  var desc: JSValue? { get set }
  func __setDownlaodCallback(_ callback: JSValue)
}

class JavascriptPluginSubtitleItem: NSObject, JavascriptPluginSubtitleItemExportable {
  var data: JSValue { _data.value }
  var desc: JSValue? {
    get { _desc?.value }
    set { setDesc(newValue) }
  }

  var _data: JSManagedValue
  var _desc: JSManagedValue?
  var download: JSManagedValue?

  private unowned var owner: JavascriptAPISubtitle

  init(data: JSValue, desc: JSValue?, withOwner owner: JavascriptAPISubtitle) {
    self.owner = owner
    self._data = JSManagedValue(value: data)
    JSContext.current()!.virtualMachine.addManagedReference(self._data, withOwner: owner)
    super.init()
    setDesc(desc)
  }

  func __setDownlaodCallback(_ callback: JSValue) {
    download = JSManagedValue(value: callback);
    JSContext.current()!.virtualMachine.addManagedReference(download, withOwner: owner)
  }

  private func setDesc(_ value: JSValue?) {
    if let currentDesc = _desc {
      JSContext.current()!.virtualMachine.removeManagedReference(currentDesc, withOwner: owner)
    }
    if let value = value {
      self._desc = JSManagedValue(value: value)
      JSContext.current()!.virtualMachine.addManagedReference(self._desc, withOwner: owner)
    }
  }
}
