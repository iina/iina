//
//  SettingsHelper.swift
//  iina
//
//  Created by Hechen Li on 6/23/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

struct ALConstraint {
  struct Direction: OptionSet {
    let rawValue: Int
    static let minX = Direction(rawValue: 1 << 0)
    static let maxX = Direction(rawValue: 1 << 1)
    static let minY = Direction(rawValue: 1 << 2)
    static let maxY = Direction(rawValue: 1 << 3)
    static let horizontal: Direction = [.minX, .maxX]
    static let vertical: Direction = [.minY, .maxY]
    static let all: Direction = [.horizontal, .vertical]
    static let list: [Direction] = [.minX, .maxX, .minY, .maxY]
  }

  let direction: Direction
  let relation: NSLayoutConstraint.Relation
  let constant: CGFloat

  init(direction: Direction, relation: NSLayoutConstraint.Relation, constant: CGFloat) {
    self.direction = direction
    self.relation = relation
    self.constant = constant
  }

  var isMax: Bool {
    self.direction.contains(.maxX) || self.direction.contains(.maxY)
  }

  static let top = top(0)
  static let bottom = bottom(0)
  static let leading = leading(0)
  static let trailing = trailing(0)
  static let horizontal = horizontal(0)
  static let vertical = vertical(0)
  static let all = all(0)

  static func top(_ val: CGFloat? = nil, lessThan lessVal: CGFloat? = nil, greaterThan greatVal: CGFloat? = nil) -> ALConstraint {
    return getConstraint(.minY, val, lessVal, greatVal)
  }

  static func bottom(_ val: CGFloat? = nil, lessThan lessVal: CGFloat? = nil, greaterThan greatVal: CGFloat? = nil) -> ALConstraint {
    return getConstraint(.maxY, val, lessVal, greatVal)
  }

  static func leading(_ val: CGFloat? = nil, lessThan lessVal: CGFloat? = nil, greaterThan greatVal: CGFloat? = nil) -> ALConstraint {
    return getConstraint(.minX, val, lessVal, greatVal)
  }

  static func trailing(_ val: CGFloat? = nil, lessThan lessVal: CGFloat? = nil, greaterThan greatVal: CGFloat? = nil) -> ALConstraint {
    return getConstraint(.maxX, val, lessVal, greatVal)
  }

  static func horizontal(_ val: CGFloat? = nil, lessThan lessVal: CGFloat? = nil, greaterThan greatVal: CGFloat? = nil) -> ALConstraint {
    return getConstraint(.horizontal, val, lessVal, greatVal)
  }

  static func vertical(_ val: CGFloat? = nil, lessThan lessVal: CGFloat? = nil, greaterThan greatVal: CGFloat? = nil) -> ALConstraint {
    return getConstraint(.vertical, val, lessVal, greatVal)
  }

  static func all(_ val: CGFloat? = nil, lessThan lessVal: CGFloat? = nil, greaterThan greatVal: CGFloat? = nil) -> ALConstraint {
    return getConstraint(.all, val, lessVal, greatVal)
  }

  private static func getConstraint(_ direction: Direction, _ val: CGFloat?, _ lessVal: CGFloat?, _ greatVal: CGFloat?) -> ALConstraint {
    let rel: NSLayoutConstraint.Relation
    let constant: CGFloat
    if let val = val { (rel, constant) = (.equal, val) }
    else if let lessVal = lessVal { (rel, constant) = (.lessThanOrEqual, lessVal) }
    else if let greatVal = greatVal { (rel, constant) = (.greaterThanOrEqual, greatVal) }
    else { fatalError("A constraint must has a value") }
    return .init(direction: direction, relation: rel, constant: constant)
  }
}

extension NSView {
  @discardableResult
  func padding(to aView: NSView? = nil, _ constraintList: ALConstraint...) -> Self {
    let constraints = constraintList.flatMap { c in
      ALConstraint.Direction.list.compactMap {
        c.direction.contains($0) ? ALConstraint(direction: $0, relation: c.relation, constant: c.constant)  : nil
      }
    }
    for constraint in constraints {
      let attr1: NSLayoutConstraint.Attribute
      let attr2: NSLayoutConstraint.Attribute
      switch constraint.direction {
      case .minX:
        attr1 = .leading; attr2 = .leading
      case .maxX:
        attr1 = .trailing; attr2 = .trailing
      case .minY:
        attr1 = .top; attr2 = .top
      case .maxY:
        attr1 = .bottom; attr2 = .bottom
      default:
        fatalError()
      }
      let aView = aView ?? self.superview!
      let view1 = constraint.isMax ? aView : self
      let view2 = constraint.isMax ? self : aView
      NSLayoutConstraint(item: view1, attribute: attr1, relatedBy: constraint.relation,
                         toItem: view2, attribute: attr2,
                         multiplier: 1, constant: constraint.constant).isActive = true
    }

    return self
  }

  @discardableResult
  func size(width: CGFloat? = nil, height: CGFloat? = nil) -> Self {
    if let width = width {
      self.widthAnchor.constraint(equalToConstant: width).isActive = true
    }
    if let height = height {
      self.heightAnchor.constraint(equalToConstant: height).isActive = true
    }
    return self
  }

  @discardableResult
  func center(with aView: NSView? = nil, x: Bool? = nil, y: Bool? = nil) -> Self {
    let aView = aView ?? self.superview!
    let noArg = x == nil && y == nil
    if x == true || noArg {
      self.superview!.addConstraint(self.centerXAnchor.constraint(equalTo: aView.centerXAnchor))
    } else if y == true || noArg {
      self.superview!.addConstraint(self.centerYAnchor.constraint(equalTo: aView.centerYAnchor))
    }
    return self
  }

  @discardableResult
  func flexibleSpacingTo(view: NSView, _ superview: NSView? = nil, top: CGFloat? = nil, bottom: CGFloat? = nil, leading: CGFloat? = nil, trailing: CGFloat? = nil) -> Self {
    let sv = superview ?? view.superview!
    if let top = top {
      sv.addConstraint(self.topAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor, constant: top))
    }
    if let bottom = bottom {
      sv.addConstraint(self.bottomAnchor.constraint(lessThanOrEqualTo: view.topAnchor, constant: -bottom))
    }
    if let leading = leading {
      sv.addConstraint(self.leadingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor, constant: leading))
    }
    if let trailing = trailing {
      sv.addConstraint(self.trailingAnchor.constraint(lessThanOrEqualTo: view.leadingAnchor, constant: -trailing))
    }
    return self
  }

  @discardableResult
  func spacing(to aView: NSView? = nil, _ constraintList: ALConstraint...) -> Self {
    for constraint in constraintList {
      let attr1: NSLayoutConstraint.Attribute
      let attr2: NSLayoutConstraint.Attribute
      switch constraint.direction {
      case .minX: fallthrough
      case .maxX:
        attr1 = .leading; attr2 = .trailing
      case .minY: fallthrough
      case .maxY:
        attr1 = .top; attr2 = .bottom
      default:
        fatalError()
      }
      let aView = aView ?? self.superview!
      let view1 = constraint.isMax ? aView : self
      let view2 = constraint.isMax ? self : aView
      NSLayoutConstraint(item: view1, attribute: attr1, relatedBy: constraint.relation,
                         toItem: view2, attribute: attr2, multiplier: 1,
                         constant: constraint.constant).isActive = true
    }

    return self
  }
}

extension NSTextField {
  @discardableResult
  func makeMultiLine() -> Self {
    self.lineBreakMode = .byWordWrapping
    self.usesSingleLineMode = false
    self.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return self
  }

}

class SettingsUIHelper {
  private var l10n: SettingsLocalization.Context

  init(_ l10n: SettingsLocalization.Context) {
    self.l10n = l10n
  }

  func popupButton(_ items: [(SettingsLocalization.Key, Int)]) -> NSPopUpButton {
    let button = NSPopUpButton()
    button.bezelStyle = .accessoryBarAction
    button.controlSize = .small
    button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    for (key, value) in items {
      let item = NSMenuItem()
      item.title = l10n.localized(key)
      item.tag = value
      button.menu!.addItem(item)
    }
    return button
  }

  func textInput(value: String = "", width: CGFloat = 64) -> NSTextField {
    let textField = NSTextField()
    textField.stringValue = value
    textField.controlSize = .small
    textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    textField.size(width: width)
    return textField
  }

  func label(_ key: SettingsLocalization.Key) -> NSTextField {
    let textField = NSTextField(labelWithString: l10n.localized(key))
    textField.controlSize = .small
    textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    return textField
  }

  func hStack(align: NSLayoutConstraint.Attribute = .firstBaseline, _ views: NSView...) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.orientation = .horizontal
    stackView.alignment = align
    return stackView
  }

  func vStack(_ views: NSView...) -> NSStackView {
    let stackView = NSStackView(views: views)
    stackView.orientation = .vertical
    stackView.alignment = .leading
    return stackView
  }

  func space(width: CGFloat = 0, height: CGFloat = 0) -> NSView {
    let view = NSView()
    view.size(width: width, height: height)
    return view
  }

  func image(_ symbol: String, size: CGFloat = 16) -> NSImageView {
    let imageView = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
    imageView.size(width: size, height: size)
    return imageView
  }

  func radioGroup(target: AnyObject?, action: Selector?, size: NSControl.ControlSize = .small, _ items: [(SettingsLocalization.Key, Int)]) -> [NSButton] {
    return items.map { key, value in
      let button = NSButton(radioButtonWithTitle: l10n.localized(key), target: target, action: action)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.controlSize = size
      return button
    }
  }

  static func hEquallySpaced(_ views: [NSView], _ space: CGFloat = 8, leading: CGFloat? = nil, trailing: CGFloat? = nil) {
    if let leading = leading {
      views.first!.padding(.leading(leading))
    }
    for (i, view) in views.enumerated() {
      if i == 0 { continue }
      view.spacing(to: views[i - 1], .leading(space))
    }
    if let trailing = trailing {
      views.last!.padding(.trailing(greaterThan: trailing))
    }
  }

  static func vEquallySpaced(_ views: [NSView], _ space: CGFloat = 8, top: CGFloat? = nil, bottom: CGFloat? = nil) {
    if let top = top {
      views.first!.padding(.top(top))
    }
    for (i, view) in views.enumerated() {
      if i == 0 { continue }
      view.spacing(to: views[i - 1], .top(space))
    }
    if let bottom = bottom {
      views.last!.padding(.bottom(bottom))
    }
  }
}
