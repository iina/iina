//
//  OSCBottomView.swift
//  iina
//
//  Created by Hechen Li on 2026-06-09.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate extension LayoutValue {
  static let oscPadding = LayoutValue(12, 8)
}


class OSCBottomView: NSView {
  weak var mainWindow: MainWindowController!
  var oscView: TimeLabelOverflowedStackView!

  private var translucentView: TranslucentView!
  private var container: NSView!
  private var leadingConstraint: NSLayoutConstraint!
  private var trailingConstraint: NSLayoutConstraint!

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
    oscView.padding(.all(.oscPadding))
    translucentView.setContent(container)

    addSubview(translucentView)
    translucentView.padding(.vertical)
    leadingConstraint = translucentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0)
    leadingConstraint.isActive = true
    trailingConstraint = trailingAnchor.constraint(equalTo: translucentView.trailingAnchor, constant: 0)
    trailingConstraint.isActive = true
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setLeadingConstraint(_ constant: CGFloat, animated: Bool = true) {
    if animated {
      leadingConstraint.animator().constant = constant
    }
  }

  func setTrailingConstraint(_ constant: CGFloat, animated: Bool = true) {
    if animated {
      trailingConstraint.animator().constant = constant
    }
  }
}
