//
//  SimpleViewController.swift
//  iina
//
//  Created by luca on 07.10.2025.
//  Copyright © 2025 lhc. All rights reserved.
//

import AppKit

class SimpleViewController: NSViewController {
  let wrappedView: NSView

  init(wrapped wrappedView: NSView) {
    self.wrappedView = wrappedView
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = wrappedView
  }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
class SimpleSplitAccessoryViewController: NSSplitViewItemAccessoryViewController {
  let wrappedView: NSView

  init(wrapped wrappedView: NSView) {
    self.wrappedView = wrappedView
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView()
    wrappedView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(wrappedView)
    NSLayoutConstraint.activate([
      wrappedView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      wrappedView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      wrappedView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      wrappedView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      wrappedView.heightAnchor.constraint(equalToConstant: 30),
    ])
    automaticallyAppliesContentInsets = false
  }
}
#endif
