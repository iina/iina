//
//  KeyBindingCriterion.swift
//  iina
//
//  Created by lhc on 3/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class Criterion: NSObject {

  var children: [Criterion]

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


  init(name: String) {
    self.name = name
    super.init()
  }

  init(name: String, children: Criterion...) {
    self.name = name
    super.init()

    for child in children {
      self.children.append(child)
    }
  }

  override func displayValue() -> Any {
    return name
  }

}


class TextFieldCriterion: Criterion {

  override func displayValue() -> Any {
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 18))
    field.focusRingType = .none
    field.bezelStyle = .roundedBezel
    return field
  }

}
