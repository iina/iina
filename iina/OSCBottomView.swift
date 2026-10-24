//
//  OSCBottomView.swift
//  iina
//
//  Created by Hechen Li on 2026-06-09.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate extension LayoutValue {
  static let oscPadding = LayoutValue(12, 8)
  static let oscPaddingLeading = LayoutValue(16, 12)
}


class OSCBottomView: NSView {
  weak var mainWindow: MainWindowController!
  private let prefObserver = Preference.Observer()

  var oscView: TimeLabelOverflowedStackView!

  private var translucentView: TranslucentView!
  private var container: NSView!
  private var leadingConstraint: NSLayoutConstraint!
  private var trailingConstraint: NSLayoutConstraint!
  private var verticalConstraint: NSLayoutConstraint!
  private var requestedLeadingInset: CGFloat = 0
  private var requestedTrailingInset: CGFloat = 0
  private var leadingInsetGeneration = 0
  private var trailingInsetGeneration = 0

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    self.translucentView = TranslucentView(liquidGlassCornerRadius: 0, vevCornerRadius: 0, padding: (0, 0))

    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    self.container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    self.oscView = TimeLabelOverflowedStackView()
    oscView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(oscView)
    oscView.padding(.vertical(.oscPadding), .trailing(.oscPadding), .leading(.oscPaddingLeading))
    translucentView.setContent(container)

    addSubview(translucentView)
    translucentView.padding(.vertical)
    leadingConstraint = translucentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0)
    // Insets below fittingSizeCompression cannot enlarge the window minimum.
    leadingConstraint.isActive = true
    trailingConstraint = trailingAnchor.constraint(equalTo: translucentView.trailingAnchor, constant: 0)
    trailingConstraint.isActive = true
    translucentView.leftAnchor.constraint(greaterThanOrEqualTo: leftAnchor).isActive = true
    translucentView.rightAnchor.constraint(lessThanOrEqualTo: rightAnchor).isActive = true

    prefObserver.add(.useLiquidGlassOSC, runNow: true) { [unowned self] _ in
      translucentView.setStyle(Preference.liquidGlass(.osc) ? .liquidGlass : .visualEffect)
    }
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setLeadingConstraint(_ constant: CGFloat, animated: Bool = true) {
    leadingInsetGeneration += 1
    requestedLeadingInset = constant
    if constant > 0 {
      setInsetPriority(leadingConstraint, to: .init(NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1))
    }
    if animated {
      leadingConstraint.animator().constant = constant
    } else {
      leadingConstraint.constant = constant
    }
    if constant == 0 { restoreBaselineInsetPriority(animated: animated, leading: true) }
  }

  func setTrailingConstraint(_ constant: CGFloat, animated: Bool = true) {
    trailingInsetGeneration += 1
    requestedTrailingInset = constant
    if constant > 0 {
      setInsetPriority(trailingConstraint, to: .init(NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1))
    }
    if animated {
      trailingConstraint.animator().constant = constant
    } else {
      trailingConstraint.constant = constant
    }
    if constant == 0 { restoreBaselineInsetPriority(animated: animated, leading: false) }
  }

  /// Reinstall constraints when crossing AppKit's required-priority boundary.
  private func setInsetPriority(_ constraint: NSLayoutConstraint, to priority: NSLayoutConstraint.Priority) {
    guard constraint.priority != priority else { return }
    let reinstall = constraint.isActive && ((constraint.priority == .required) != (priority == .required))
    if reinstall { constraint.isActive = false }
    constraint.priority = priority
    if reinstall { constraint.isActive = true }
  }

  private func restoreBaselineInsetPriority(animated: Bool, leading: Bool) {
    let generation = leading ? leadingInsetGeneration : trailingInsetGeneration
    let restore = { [weak self] in
      guard let self else { return }
      if leading {
        guard requestedLeadingInset == 0, leadingInsetGeneration == generation else { return }
        setInsetPriority(leadingConstraint, to: .required)
      } else {
        guard requestedTrailingInset == 0, trailingInsetGeneration == generation else { return }
        setInsetPriority(trailingConstraint, to: .required)
      }
      needsLayout = true
    }
    let duration = animated ? NSAnimationContext.current.duration : 0
    if duration > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: restore)
    } else {
      restore()
    }
  }

  func updateVerticalConstraint(isDisplaying: Bool) {
    guard let superview else { return }
    if let verticalConstraint {
      superview.removeConstraint(verticalConstraint)
    }
    if isDisplaying {
      verticalConstraint = bottomAnchor.constraint(equalTo: superview.bottomAnchor)
    } else {
      verticalConstraint = topAnchor.constraint(equalTo: superview.bottomAnchor)
    }
    verticalConstraint.isActive = true
  }
}
