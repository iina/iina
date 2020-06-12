//
//  Switch.swift
//  iina
//
//  Created by Collider LI on 12/6/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

@IBDesignable
class Switch: NSView {
  private var _title = ""
  private var _checked = false

  @IBInspectable var title: String {
    get {
      return _title
    }
    set {
      _title = newValue
      if #available(macOS 10.15, *) {
        label?.stringValue = _title
      } else {
        checkbox?.title = " " + _title
      }
    }
  }

  @IBInspectable var checked: Bool {
    get {
      return _checked
    }
    set {
      _checked = newValue
      if #available(macOS 10.15, *) {
        (nsSwitch as! NSSwitch).state = _checked ? .on : .off
      } else {
        checkbox?.state = _checked ? .on : .off
      }
    }
  }

  var action: (Bool) -> Void = { _ in }

  private var nsSwitch: Any?
  private var label: NSTextField?
  private var checkbox: NSButton?

  private func setupSubViews() {
    if #available(macOS 10.15, *) {
      let label = NSTextField(labelWithString: title)
      let nsSwitch = NSSwitch()
      nsSwitch.target = self
      nsSwitch.action = #selector(statusChanged)
      label.translatesAutoresizingMaskIntoConstraints = false
      nsSwitch.translatesAutoresizingMaskIntoConstraints = false
      addSubview(label)
      addSubview(nsSwitch)
      self.nsSwitch = nsSwitch
      self.label = label
      Utility.quickConstraints(["H:|-0-[l]-(>=8)-[s]-0-|"], ["l": label, "s": nsSwitch])
      label.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
      nsSwitch.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
    } else {
      let checkbox: NSButton
      if #available(macOS 10.12, *) {
        checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(statusChanged))
      } else {
        checkbox = NSButton()
        checkbox.setButtonType(.switch)
        checkbox.target = self
        checkbox.action = #selector(statusChanged)
      }
      checkbox.translatesAutoresizingMaskIntoConstraints = false
      self.checkbox = checkbox
      addSubview(checkbox)
      Utility.quickConstraints(["H:|-0-[b]-(>=0)-|"], ["b": checkbox])
      checkbox.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupSubViews()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupSubViews()
  }

  @objc func statusChanged() {
    if #available(macOS 10.15, *) {
      _checked = (nsSwitch as! NSSwitch).state == .on
    } else {
      _checked = checkbox!.state == .on
    }
    self.action(_checked)
  }
}
