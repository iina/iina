//
//  SettingsHelper.swift
//  iina
//
//  Created by Hechen Li on 6/23/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

extension NSView {
  @discardableResult
  func fillSuperView(padding: CGFloat = 0) -> Self {
    guard let superview = self.superview else { return self }
    superview.addConstraints([
      self.leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: padding),
      self.trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -padding),
      self.topAnchor.constraint(equalTo: superview.topAnchor, constant: padding),
      self.bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -padding)
    ])
    return self
  }

  @discardableResult
  func paddingToView(_ view: NSView, _ superview: NSView? = nil, top: CGFloat? = nil, bottom: CGFloat? = nil, leading: CGFloat? = nil, trailing: CGFloat? = nil) -> Self {
    let sv = superview ?? view.superview!
    if let leading = leading {
      sv.addConstraint(self.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leading))
    }
    if let trailing = trailing {
      sv.addConstraint(self.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -trailing))
    }
    if let top = top {
      sv.addConstraint(self.topAnchor.constraint(equalTo: view.topAnchor, constant: top))
    }
    if let bottom = bottom {
      sv.addConstraint(self.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -bottom))
    }
    return self
  }

  @discardableResult
  func flexiblePaddingToView(_ view: NSView, _ superview: NSView? = nil, top: CGFloat? = nil, bottom: CGFloat? = nil, leading: CGFloat? = nil, trailing: CGFloat? = nil) -> Self {
    let sv = superview ?? view.superview!
    if let leading = leading {
      sv.addConstraint(self.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: leading))
    }
    if let trailing = trailing {
      sv.addConstraint(self.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -trailing))
    }
    if let top = top {
      sv.addConstraint(self.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: top))
    }
    if let bottom = bottom {
      sv.addConstraint(self.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -bottom))
    }
    return self
  }

  @discardableResult
  func paddingToSuperView(top: CGFloat? = nil, bottom: CGFloat? = nil, leading: CGFloat? = nil, trailing: CGFloat? = nil) -> Self {
    guard let superview = self.superview else { return self }
    return paddingToView(superview, superview, top: top, bottom: bottom, leading: leading, trailing: trailing)
  }

  @discardableResult
  func flexiblePaddingToSuperView(top: CGFloat? = nil, bottom: CGFloat? = nil, leading: CGFloat? = nil, trailing: CGFloat? = nil) -> Self {
    guard let superview = self.superview else { return self }
    return flexiblePaddingToView(superview, superview, top: top, bottom: bottom, leading: leading, trailing: trailing)
  }

  @discardableResult
  func centerInSuperView(x: Bool? = nil, y: Bool? = nil) -> Self {
    guard let superview = self.superview else { return self }
    return centerWithView(superview, superview, x: x, y: y)
  }

  @discardableResult
  func centerWithView(_ view: NSView, _ superview: NSView? = nil, x: Bool? = nil, y: Bool? = nil) -> Self {
    let sv = superview ?? view.superview!
    if x == true {
      sv.addConstraint(self.centerXAnchor.constraint(equalTo: view.centerXAnchor))
    }
    if y == true {
      sv.addConstraint(self.centerYAnchor.constraint(equalTo: view.centerYAnchor))
    }
    return self
  }

  @discardableResult
  func spacingTo(view: NSView, _ superview: NSView? = nil, top: CGFloat? = nil, bottom: CGFloat? = nil, leading: CGFloat? = nil, trailing: CGFloat? = nil) -> Self {
    let sv = superview ?? view.superview!
    if let top = top {
      sv.addConstraint(self.topAnchor.constraint(equalTo: view.bottomAnchor, constant: top))
    }
    if let bottom = bottom {
      sv.addConstraint(self.bottomAnchor.constraint(equalTo: view.topAnchor, constant: -bottom))
    }
    if let leading = leading {
      sv.addConstraint(self.leadingAnchor.constraint(equalTo: view.trailingAnchor, constant: leading))
    }
    if let trailing = trailing {
      sv.addConstraint(self.trailingAnchor.constraint(equalTo: view.leadingAnchor, constant: -trailing))
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
      sv.addConstraint(self.bottomAnchor.constraint(lessThanOrEqualTo: view.topAnchor, constant: bottom))
    }
    if let leading = leading {
      sv.addConstraint(self.leadingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor, constant: leading))
    }
    if let trailing = trailing {
      sv.addConstraint(self.trailingAnchor.constraint(lessThanOrEqualTo: view.leadingAnchor, constant: trailing))
    }
    return self
  }
}

