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
    let visibilityHandler: ((State) -> Void)?
    var state: State = .auto

    init(view: NSView, visibilityHandler: ((State) -> Void)?, criteria: @escaping () -> State) {
      self.view = view
      self.criteria = criteria
      self.visibilityHandler = visibilityHandler
    }
  }

  private var items: [Item] = []

  func add(_ view: NSView, visibilityHandler: ((State) -> Void)? = nil, criteria: @escaping () -> State) {
    guard !(items.contains { $0.view == view }) else { return }
    items.append(Item(view: view, visibilityHandler: visibilityHandler, criteria: criteria))
  }

  func update() {
    items.forEach {
      $0.state = $0.criteria()
      if let handler = $0.visibilityHandler {
        handler($0.state)
        return
      }
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
