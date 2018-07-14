//
//  CollapseView.swift
//  iina
//
//  Created by Collider LI on 8/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

fileprivate let triggerIdentifier = NSUserInterfaceItemIdentifier(rawValue: "Trigger")
fileprivate let contentIdentifier = NSUserInterfaceItemIdentifier(rawValue: "Content")


/// Create a collapse view in xib. To use this class, you need to:
/// - Add a stackview and set its class to `CollapseView`;
/// - Assign the collapseable view an identifier "Content";
/// -
class CollapseView: NSStackView {

  private var trigger: NSView?
  private var contentView: NSView?

  private var originalTarget: AnyObject?
  private var originalAction: Selector?

  var folded = true

  override func viewDidMoveToWindow() {
    guard trigger == nil && contentView == nil else { return }
    findViews()
    guard let trigger = trigger as? NSControl, let _ = contentView else {
      fatalError("FoldableView is not set up correctly.")
    }

    // try to get the state of the control
    if let buttton = trigger as? NSButton {
      folded = buttton.state != .on
    }
    updateContentView(animated: false)

    originalTarget = trigger.target
    originalAction = trigger.action

    trigger.target = self
    trigger.action = #selector(self.triggerAction)
  }

  @objc private func triggerAction(_ sender: NSControl) {
    folded = !folded
    if let action = originalAction {
      _ = originalTarget?.perform(action, with: trigger)
    }
    updateContentView()
  }

  func updateContentView(animated: Bool = true) {
    setVisibilityPriority(folded ? .notVisible : .mustHold, for: contentView!)
    if animated {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.25
        context.allowsImplicitAnimation = true
        self.window?.layoutIfNeeded()
      }, completionHandler: nil)
    }
  }

  private func findViews() {
    var queue: [NSView] = views

    while (queue.count > 0) {
      let view = queue.popLast()!
      if view.identifier == triggerIdentifier {
        trigger = view
      } else if view.identifier == contentIdentifier {
        contentView = view
      } else {
        view.subviews.forEach { queue.insert($0, at: 0) }
      }
    }
  }
}
