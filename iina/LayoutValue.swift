//
//  Layout.swift
//  iina
//
//  Created by Hechen Li on 2026-06-05.
//  Copyright © 2026 lhc. All rights reserved.
//


struct LayoutValue {
  let value: CGFloat
  let compactValue: CGFloat?

  var isFixed: Bool {
    compactValue == nil
  }

  private struct Listener {
    let layout: LayoutValue
    let block: (CGFloat) -> Void
  }

  private final class Store: NSObject {
    static let shared = Store()
    var listeners: [Listener] = []

    override init() {
      super.init()
      UserDefaults.standard.addObserver(
        self, forKeyPath: Preference.Key.compactUI.rawValue, options: [.new], context: nil)
    }

    deinit {
      UserDefaults.standard.removeObserver(self, forKeyPath: Preference.Key.compactUI.rawValue)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
      guard let keyPath, keyPath == Preference.Key.compactUI.rawValue else { return }
      let isCompact = Preference.bool(for: .compactUI)
      listeners.forEach {
        $0.layout.apply(isCompact: isCompact, $0.block)
      }
    }
  }

  init(_ value: CGFloat, _ compactValue: CGFloat? = nil) {
    self.value = value
    self.compactValue = compactValue
  }

  func get() -> CGFloat {
    isFixed ? value :
    Preference.bool(for: .compactUI) ? compactValue! : value
  }

  func use(_ block: @escaping (CGFloat) -> Void, applyNow: Bool = true) {
    if isFixed {
      block(value)
    } else {
      let listener = Listener(layout: self, block: block)
      Store.shared.listeners.append(listener)
      if applyNow {
        apply(isCompact: Preference.bool(for: .compactUI), listener.block)
      }
    }
  }

  private func apply(isCompact: Bool, _ block: (CGFloat) -> Void) {
    guard !isFixed else { return }
    block(isCompact ? compactValue! : value)
  }
}


extension LayoutValue {
  static let panelCornerRadius: LayoutValue = .init(0)
  static let sidebarMargin = LayoutValue(16, 14)
  static let sidebarStackViewSpacing = LayoutValue(18, 16)
  static let sidebarContainerPadding = LayoutValue(12, 10)
  static let sidebarItemSpacing = LayoutValue(12, 8)
}
