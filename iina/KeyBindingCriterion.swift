//
//  KeyBindingCriterion.swift
//  iina
//
//  Created by lhc on 3/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class Criterion: NSObject {

  var isPlaceholder = false
  var isIINACommand = false

  var children: [Criterion]

  var mpvCommandValue: String { get { return "" } }

  override init() {
    children = []
    super.init()
  }

  func childrenCount() -> Int {
    return children.count
  }

  func child(at index: Int) -> Criterion {
    return children[index]
  }

  func addChild(_ child: Criterion) {
    children.append(child)
  }

  func displayValue() -> Any { return "" }

}


class TextCriterion: Criterion {

  var name: String
  var localizedName: String

  override var mpvCommandValue: String {
    get {
      return name
    }
  }

  init(name: String, localizedName: String) {
    self.name = name
    self.localizedName = localizedName
    super.init()
  }

  override func displayValue() -> Any {
    return localizedName
  }

}


class TextFieldCriterion: Criterion, NSTextFieldDelegate, NSControlTextEditingDelegate {

  private lazy var field = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 18))

  override var mpvCommandValue: String {
    get {
      return field.stringValue
    }
  }

  override func displayValue() -> Any {
    field.delegate = self
    field.focusRingType = .none
    field.bezelStyle = .roundedBezel
    field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
    return field
  }

  func controlTextDidChange(_ obj: Notification) {
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingInputChanged))
  }

}

class SeparatorCriterion: Criterion {

  override func displayValue() -> Any {
    return NSMenuItem.separator()
  }

}
