//
//  OSCFloatingView.swift
//  iina
//
//  Created by Hechen Li on 2026-06-09.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate extension LayoutValue {
  static let oscPaddingTop = LayoutValue(14, 10)
  static let oscPaddingBottom = LayoutValue(8, 5)

}


class OSCFloatingView: TranslucentView {
  weak var mainWindow: MainWindowController!

  var oscTopView: NSStackView!
  var oscBottomView: TimeLabelOverflowedStackView!

  var xConstraint: NSLayoutConstraint!
  var yConstraint: NSLayoutConstraint!
//  private leadingTrailingConstraints: NSLayoutConstraint!

  var mousePosRelatedToView: CGPoint?

  var isDragging: Bool = false

  private var isAlignFeedbackSent = false

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let cornerRadius: CGFloat = if #available(macOS 26.0, *) { 12 } else { 6 }
    super.init(liquidGlassCornerRadius: cornerRadius, vevCornerRadius: cornerRadius, padding: (0, 0))

    self.oscTopView = NSStackView()
    oscTopView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(oscTopView)
    oscTopView.padding(.top(.oscPaddingTop), .horizontal(12))

    self.oscBottomView = TimeLabelOverflowedStackView()
    oscBottomView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(oscBottomView)
    oscBottomView.padding(.bottom(.oscPaddingBottom), .horizontal(8))
      .spacing(.top(8), to: oscTopView)

    let widthConstraint = widthAnchor.constraint(equalToConstant: 440)
    widthConstraint.priority = .defaultLow
    widthConstraint.isActive = true

    setContent(container)

    widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
  }

  override func viewDidMoveToSuperview() {
    padding(.horizontal(greaterThan: 1))

    xConstraint = centerXAnchor.constraint(equalTo: superview!.leadingAnchor)
    xConstraint.priority = .defaultLow
    xConstraint.isActive = true

    yConstraint = superview!.bottomAnchor.constraint(equalTo: bottomAnchor)
    yConstraint.priority = .defaultHigh
    yConstraint.isActive = true
  }

  override func mouseDown(with event: NSEvent) {
    mousePosRelatedToView = NSEvent.mouseLocation
    mousePosRelatedToView!.x -= frame.origin.x
    mousePosRelatedToView!.y -= frame.origin.y
    isAlignFeedbackSent = abs(frame.origin.x - (window!.frame.width - frame.width) / 2) <= 5
    isDragging = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard let mousePos = mousePosRelatedToView, let windowFrame = window?.frame else { return }
    let currentLocation = NSEvent.mouseLocation
    var newOrigin = CGPoint(
      x: currentLocation.x - mousePos.x,
      y: currentLocation.y - mousePos.y
    )
    // stick to center
    if Preference.bool(for: .controlBarStickToCenter) {
      let xPosWhenCenter = (windowFrame.width - frame.width) / 2
      if abs(newOrigin.x - xPosWhenCenter) <= 5 {
        newOrigin.x = xPosWhenCenter
        if !isAlignFeedbackSent {
          NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
          isAlignFeedbackSent = true
        }
      } else {
        isAlignFeedbackSent = false
      }
    }
    // bound to window frame
    let xMax = windowFrame.width - frame.width - 10
    let yMax = windowFrame.height - frame.height - 25
    newOrigin = newOrigin.constrained(to: NSRect(x: 10, y: 0, width: xMax, height: yMax))
    // apply position
    let newConstraint = newOrigin.x + frame.width / 2
    xConstraint.constant = userInterfaceLayoutDirection == .rightToLeft ?
      windowFrame.width - newConstraint : newConstraint
    yConstraint.constant = newOrigin.y
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
    guard let windowFrame = window?.frame else { return }
    // save final position
    Preference.set(xConstraint.constant / windowFrame.width, for: .controlBarPositionHorizontal)
    Preference.set(yConstraint.constant / windowFrame.height, for: .controlBarPositionVertical)
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
