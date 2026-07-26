//
//  FadeableViewController.swift
//  iina
//
//  Created by Hechen Li on 2026-06-11.
//  Copyright © 2026 lhc. All rights reserved.
//

class FadeableViewController {
  enum State {
    case alwaysShown
    case alwaysHidden
    case auto
  }
  class Item {
    let view: NSView
    let criteria: () -> State
    var state: State = .auto

    init(view: NSView, criteria: @escaping () -> State) {
      self.view = view
      self.criteria = criteria
    }
  }

  private var items: [Item] = []

  func add(_ view: NSView, criteria: @escaping () -> State) {
    guard !(items.contains { $0.view == view }) else { return }
    items.append(Item(view: view, criteria: criteria))
  }

  func update() {
    items.forEach {
      $0.state = $0.criteria()
      switch $0.state {
      case .alwaysShown:
        $0.view.isHidden = false
      case .alwaysHidden:
        $0.view.isHidden = true
      case .auto:
        break
      }
    }
  }

  func forEach(_ body: (NSView) -> Void) {
    items.filter { $0.state == .auto }.forEach { body($0.view) }
  }
}
