//
//  AnimatedTabViewController.swift
//  iina
//
//  Created by Hechen Li on 2026-05-30.
//  Copyright © 2026 lhc. All rights reserved.
//


class AnimatedTabViewController: NSTabViewController {
  var transitionDuration: TimeInterval = 0.3
  private var previousIndex: Int = -1

  override func viewDidLoad() {
    super.viewDidLoad()

    view.translatesAutoresizingMaskIntoConstraints = false
    tabView.wantsLayer = true
    tabStyle = .unspecified
    transitionOptions = [.slideLeft, .slideRight]
  }

  override func transition(
    from fromVC: NSViewController,
    to toVC: NSViewController,
    options: NSViewController.TransitionOptions = [],
    completionHandler completion: (() -> Void)? = nil
  ) {
    if Preference.bool(for: .disableAnimations) || previousIndex < 0 {
      previousIndex = selectedTabViewItemIndex
      super.transition(from: fromVC, to: toVC, options: options, completionHandler: completion)
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
    transition.duration = transitionDuration
    transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    containerView.layer?.add(transition, forKey: kCATransition)

    super.transition(from: fromVC, to: toVC, options: [],
                     completionHandler: completion)
  }
}


class SidebarScrollView: NSScrollView {
  // swipe gesture callback, argument is true if is forward
  var horizontalScroll: ((Bool) -> Void)?

  private var deltaX: CGFloat = 0
  private let swipeThreshold: CGFloat = 30.0

  override func scrollWheel(with event: NSEvent) {
    super.scrollWheel(with: event)

    // only handle trackpad events
    guard event.phase != [] || event.momentumPhase != [] else { return }

    switch event.phase {
    case .began:
      deltaX = 0
    case .changed:
      deltaX += event.scrollingDeltaX
    case .ended:
      if deltaX > swipeThreshold {
        horizontalScroll?(false)
      } else if deltaX < -swipeThreshold {
        horizontalScroll?(true)
      }
      deltaX = 0
    default:
      break
    }
  }
}
