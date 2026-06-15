//
//  AnimatedTabViewController.swift
//  iina
//
//  Created by Hechen Li on 2026-05-30.
//  Copyright © 2026 lhc. All rights reserved.
//


class AnimatedTabViewController: NSTabViewController {
  let transitionDuration: TimeInterval = 0.3
  private let prefObserver = Preference.Observer()

  private var previousIndex: Int = -1

  override func viewDidLoad() {
    super.viewDidLoad()

    view.translatesAutoresizingMaskIntoConstraints = false
    tabView.wantsLayer = true
    tabStyle = .unspecified

    prefObserver.add(.disableAnimations, runNow: true) { [unowned self] _ in
      if Preference.bool(for: .disableAnimations) {
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
  class Container: NSBox {
    init(_ view: NSView, _ block: (NSView) -> Void) {
      super.init(frame: .zero)
      contentView = view
      translatesAutoresizingMaskIntoConstraints = false
      clipsToBounds = true
      boxType = .custom
      borderColor = .separatorColor
      cornerRadius = 8
      fillColor = .gray.withAlphaComponent(0.1)
      block(view)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  // swipe gesture callback, argument is true if is forward
  var horizontalScroll: ((Bool) -> Void)?

  private var deltaX: CGFloat = 0
  private var deltaY: CGFloat = 0
  private let angleThreshold: CGFloat = 5
  private let normThreshold: CGFloat = 80

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    drawsBackground = false

    documentView = FlippedView()
    documentView!.translatesAutoresizingMaskIntoConstraints = false
    documentView!.padding(.top, .leading, .trailing, from: contentView)
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
  
  override func scrollWheel(with event: NSEvent) {
    super.scrollWheel(with: event)

    // only handle trackpad events
    guard event.phase != [] || event.momentumPhase != [] else { return }

    switch event.phase {
    case .began:
      deltaX = 0
      deltaY = 0
    case .changed:
      deltaX += event.scrollingDeltaX
      deltaY += event.scrollingDeltaY
    case .ended:
      let angle = abs(deltaX / deltaY)
      let norm = sqrt(deltaX * deltaX + deltaY * deltaY)
      if angle > angleThreshold && norm > normThreshold {
        horizontalScroll?(deltaX < 0)
      }
      deltaX = 0
      deltaY = 0
    default:
      break
    }
  }
}
