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
  private var _checkboxMargin = true
  private var _checked = false
  private var _switchOnLeft = false

  @IBInspectable var title: String {
    get {
      return _title
    }
    set {
      _title = NSLocalizedString(newValue, comment: newValue)
      if #available(macOS 10.15, *) {
        label?.stringValue = _title
      } else {
        checkbox?.title = (checkboxMargin ? " " : "") + _title
      }
    }
  }

  @IBInspectable var checkboxMargin: Bool {
    get {
      return _checkboxMargin
    }
    set {
      _checkboxMargin = newValue
      guard let checkbox = checkbox else { return }
      if newValue {
        checkbox.title = " " + checkbox.title
      } else {
        checkbox.title = String(checkbox.title.dropFirst())
      }
    }
  }

  var checked: Bool {
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

  private lazy var viewMap: [String: Any] = {
    ["l": label!, "s": nsSwitch!]
  }()
  private lazy var switchOnLeftConstraint = {
    NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[s]-8-[l]-(>=0)-|", options: [], metrics: nil, views: viewMap)
  }()
  private lazy var switchOnRightConstraint = {
    NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[l]-(>=8)-[s]-0-|", options: [], metrics: nil, views: viewMap)
  }()

  @IBInspectable var switchOnLeft: Bool {
    get {
      return _switchOnLeft
    }
    set {
      if #available(macOS 10.15, *) {
        if newValue {
          NSLayoutConstraint.deactivate(switchOnRightConstraint)
          NSLayoutConstraint.activate(switchOnLeftConstraint)
        } else {
          NSLayoutConstraint.deactivate(switchOnLeftConstraint)
          NSLayoutConstraint.activate(switchOnRightConstraint)
        }
      }
      _switchOnLeft = newValue
    }
  }

  override var intrinsicContentSize: NSSize {
    if #available(macOS 10.15, *) {
      return NSSize(width: 0, height: 22)
    } else {
      return NSSize(width: 0, height: 14)
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
      if switchOnLeft {
        NSLayoutConstraint.activate(switchOnLeftConstraint)
      } else {
        NSLayoutConstraint.activate(switchOnRightConstraint)
      }
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
