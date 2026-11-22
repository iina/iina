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
  private let width: CGFloat = 460
  weak var mainWindow: MainWindowController!
  private let prefObserver = Preference.Observer()

  var oscTopView: NSStackView!
  var oscBottomView: TimeLabelOverflowedStackView!

  private let xGuide = NSLayoutGuide()
  private var xConstraint: NSLayoutConstraint?
  private var yConstraint: NSLayoutConstraint!

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

    let widthConstraint = widthAnchor.constraint(equalToConstant: width)
    widthConstraint.priority = .init(300)
    widthConstraint.isActive = true

    setContent(container)

    widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

    prefObserver.add(.useLiquidGlassOSC, runNow: true) { [unowned self] _ in
      setStyle(Preference.liquidGlass(.osc) ? .liquidGlass : .visualEffect)
    }
  }

  func setupConstraints() {
    let videoView = mainWindow.videoViewContainer!
    padding(.horizontal(greaterThan: 1), from: videoView)

    superview!.addLayoutGuide(xGuide)
    xGuide.leadingAnchor.constraint(equalTo: videoView.leadingAnchor).isActive = true
    let centerXConstraint = centerXAnchor.constraint(equalTo: xGuide.trailingAnchor)
    centerXConstraint.priority = .defaultLow
    centerXConstraint.isActive = true
    setHorizontalPosition(CGFloat(Preference.float(for: .controlBarPositionHorizontal)))

    yConstraint = videoView.bottomAnchor.constraint(equalTo: bottomAnchor)
    yConstraint.priority = .defaultHigh
    yConstraint.isActive = true
  }

  func initPosition() {
    let videoView = mainWindow.videoViewContainer!
    let cph = Preference.float(for: .controlBarPositionHorizontal)
    let cpv = Preference.float(for: .controlBarPositionVertical)
    setHorizontalPosition(CGFloat(cph))
    yConstraint.constant = videoView.frame.height * CGFloat(cpv)
  }

  func updatePosition() {
    let videoView = mainWindow.videoViewContainer!
    let windowHeight = videoView.frame.height
    let cph = Preference.float(for: .controlBarPositionHorizontal)
    let cpv = Preference.float(for: .controlBarPositionVertical)

    setHorizontalPosition(CGFloat(cph))

    var yPos = windowHeight * CGFloat(cpv)
    let oscHeight: CGFloat = 67
    let yMargin: CGFloat = 25

    if yPos < 0 {
      yPos = 0
    } else if yPos + oscHeight + yMargin > windowHeight {
      yPos = windowHeight - oscHeight - yMargin
    }

    yConstraint.constant = yPos
  }

  private func setHorizontalPosition(_ ratio: CGFloat) {
    let videoView = mainWindow.videoViewContainer!
    xConstraint?.isActive = false
    xConstraint = xGuide.widthAnchor.constraint(equalTo: videoView.widthAnchor, multiplier: ratio.clamped(to: 0...1))
    xConstraint!.isActive = true
  }

  override func mouseDown(with event: NSEvent) {
    mousePosRelatedToView = NSEvent.mouseLocation
    mousePosRelatedToView!.x -= frame.origin.x
    mousePosRelatedToView!.y -= frame.origin.y
    isAlignFeedbackSent = abs(frame.origin.x - (window!.frame.width - frame.width) / 2) <= 5
    isDragging = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard let mousePos = mousePosRelatedToView else { return }
    let windowFrame = mainWindow.videoViewContainer.frame
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
    let newCenterX = newOrigin.x + frame.width / 2
    let distanceFromLeading = userInterfaceLayoutDirection == .rightToLeft ?
      windowFrame.width - newCenterX : newCenterX
    setHorizontalPosition(distanceFromLeading / windowFrame.width)
    yConstraint.constant = newOrigin.y
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
    let windowFrame = mainWindow.videoViewContainer.frame
    // save final position
    if let xConstraint {
      Preference.set(xConstraint.multiplier, for: .controlBarPositionHorizontal)
    }
    Preference.set(yConstraint.constant / windowFrame.height, for: .controlBarPositionVertical)
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
