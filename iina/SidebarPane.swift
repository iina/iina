//
//  SidebarPane.swift
//  iina
//
//  Created by Hechen Li on 2026-05-30.
//  Copyright © 2026 lhc. All rights reserved.
//

extension NSImage.SymbolConfiguration {
  static let sidebarIconConfig = {
    if #available(macOS 26.0, *) {
      NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
    } else {
      NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
    }
  }()
}


enum SidebarTabMotion {
  static var duration: TimeInterval {
    AccessibilityPreferences.motionReductionEnabled ? 0 : AccessibilityPreferences.adjustedDuration(0.3)
  }

  static var timingFunction: CAMediaTimingFunction {
    CAMediaTimingFunction(name: .easeInEaseOut)
  }
}

class SidebarTabViewController: NSTabViewController {
  private let prefObserver = Preference.Observer()

  // -1 for the first tab switch, don't show animation in this case
  var previousIndex: Int = -1

  override func viewDidLoad() {
    super.viewDidLoad()

    view.translatesAutoresizingMaskIntoConstraints = false
    tabView.wantsLayer = true
    tabStyle = .unspecified

    prefObserver.add(.disableAnimations, runNow: true) { [unowned self] _ in
      if SidebarTabMotion.duration == 0 {
        transitionOptions = []
      } else {
        transitionOptions = [.slideLeft, .slideRight]
      }
    }
  }

  override func transition(
    from fromVC: NSViewController,
    to toVC: NSViewController,
    options: NSViewController.TransitionOptions = [],
    completionHandler completion: (() -> Void)? = nil
  ) {
    let duration = SidebarTabMotion.duration
    if duration == 0 || previousIndex < 0 {
      fromVC.view.superview?.layer?.removeAnimation(forKey: kCATransition)
      previousIndex = selectedTabViewItemIndex
      super.transition(from: fromVC, to: toVC, options: [], completionHandler: completion)
      return
    }

    let currentIndex = selectedTabViewItemIndex
    let goingRight = currentIndex > previousIndex
    previousIndex = currentIndex

    guard let containerView = fromVC.view.superview else {
      super.transition(from: fromVC, to: toVC, options: options,
                       completionHandler: completion)
      return
    }

    let transition = CATransition()
    transition.type = .push
    transition.subtype = goingRight ? .fromRight : .fromLeft
    transition.duration = duration
    transition.timingFunction = SidebarTabMotion.timingFunction

    containerView.layer?.add(transition, forKey: kCATransition)

    super.transition(from: fromVC, to: toVC, options: [],
                     completionHandler: completion)
  }
}


protocol SidebarPane: NSView {
  var horizontalScroll: ((NSEvent) -> Bool)? { get set }
}

/// Share gesture state across panes so a tab change cannot trigger another switch.
final class SidebarSectionScrollNavigation {
  enum Result {
    case passThrough, consumed, navigate(forward: Bool)

    var isConsumed: Bool {
      if case .passThrough = self { return false }
      return true
    }
  }

  private enum Axis { case undecided, horizontal, vertical }
  private var axis = Axis.undecided
  private var deltaX: CGFloat = 0
  private var deltaY: CGFloat = 0
  private var didSwitch = false
  private var lastUnphasedTime: TimeInterval?
  private weak var lastEvent: NSEvent?
  private var lastEventConsumed = false

  func handle(_ event: NSEvent) -> Result {
    // Vertical events can bubble from the pane to the header's root view.
    if event === lastEvent { return lastEventConsumed ? .consumed : .passThrough }
    let result = process(event)
    lastEvent = event
    lastEventConsumed = result.isConsumed
    return result
  }

  private func reset() {
    axis = .undecided
    deltaX = 0
    deltaY = 0
    didSwitch = false
    lastUnphasedTime = nil
  }

  private func process(_ event: NSEvent) -> Result {
    let x = event.scrollingDeltaX, y = event.scrollingDeltaY
    let horizontal = x != 0 && abs(x) > 5 * abs(y)
    if !event.momentumPhase.isEmpty {
      return axis == .horizontal || horizontal ? .consumed : .passThrough
    }
    if event.phase.contains(.cancelled) {
      let consumed = axis == .horizontal || horizontal
      reset()
      return consumed ? .consumed : .passThrough
    }
    if event.phase.contains(.mayBegin) { return .passThrough }
    if event.phase.isEmpty && !event.hasPreciseScrollingDeltas {
      reset()
      return horizontal ? .navigate(forward: x < 0) : .passThrough
    }
    let unphased = event.phase.isEmpty
    if event.phase.contains(.began) || (unphased &&
      (lastUnphasedTime.map({ event.timestamp - $0 > 0.25 }) != false ||
       (didSwitch && x * deltaX < 0))) {
      reset()
    }
    if unphased { lastUnphasedTime = event.timestamp }
    deltaX += x
    deltaY += y
    if axis == .undecided {
      if abs(deltaX) >= 6 && abs(deltaX) > 5 * abs(deltaY) {
        axis = .horizontal
      } else if abs(deltaY) >= 6 && abs(deltaY) > abs(deltaX) {
        axis = .vertical
      }
    }
    let consumed = axis == .horizontal || (axis == .undecided && horizontal)
    // Phase-free precise wheels have no release event; switch once per burst at a shorter threshold.
    if axis == .horizontal && !didSwitch &&
        ((unphased && abs(deltaX) >= 12) || (event.phase.contains(.ended) && abs(deltaX) >= 80)) {
      didSwitch = true
      return .navigate(forward: deltaX < 0)
    }
    return consumed ? .consumed : .passThrough
  }
}

class SidebarSectionView: NSView, SidebarPane {
  var horizontalScroll: ((NSEvent) -> Bool)?

  override func scrollWheel(with event: NSEvent) {
    if horizontalScroll?(event) == true { return }
    super.scrollWheel(with: event)
  }
}

class SidebarSectionScrollView: NSScrollView, SidebarPane {
  var horizontalScroll: ((NSEvent) -> Bool)?

  override func scrollWheel(with event: NSEvent) {
    // Nested vertical lists inherit the enclosing pane's gesture state before
    // NSScrollView can consume the event. A declined event still scrolls locally.
    var ancestor: NSView? = self
    while let view = ancestor {
      if let handler = (view as? SidebarPane)?.horizontalScroll {
        if handler(event) { return }
        break
      }
      ancestor = view.superview
    }
    super.scrollWheel(with: event)
  }
}

class SidebarScrollView: SidebarSectionScrollView {
  class Container: NSBox {
    init(_ view: NSView, _ block: (NSView) -> Void) {
      super.init(frame: .zero)
      contentView = view
      translatesAutoresizingMaskIntoConstraints = false
      clipsToBounds = true
      boxType = .custom
      borderColor = .sidebarContainerBorder
      cornerRadius = 8
      fillColor = .gray.withAlphaComponent(0.1)
      block(view)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    drawsBackground = false
    hasVerticalScroller = true
    autohidesScrollers = true

    documentView = FlippedView()
    documentView!.translatesAutoresizingMaskIntoConstraints = false
    documentView!.padding(.top, .leading, .trailing, from: contentView)
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
  
}
