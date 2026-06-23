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

  private var xConstraint: NSLayoutConstraint!
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

    NotificationCenter.default
      .addObserver(forName: .iinaSidebarStatusChanged, object: nil, queue: .main) { [weak self] _ in
      self?.initPosition()
    }
  }

  private var constraintParent: NSView?
  private var constraintsAll: [NSLayoutConstraint] = []

  func setupConstraints() {
    if let constraintParent {
      removeConstraint(xConstraint)
      constraintParent.removeConstraints(constraintsAll)
      constraintsAll.removeAll()
    }

    let videoView = if mainWindow.pipStatus == .inPIP || mainWindow.player.isInMiniPlayer {
      mainWindow.window!.contentView!
    } else {
      mainWindow.videoView
    }
    constraintParent = videoView
    constraintsAll.append(videoView.leadingAnchor.constraint(lessThanOrEqualTo: leadingAnchor))
    constraintsAll.append(videoView.trailingAnchor.constraint(greaterThanOrEqualTo: trailingAnchor))

    xConstraint = centerXAnchor.constraint(equalTo: videoView.leadingAnchor)
    xConstraint.priority = .defaultLow
    xConstraint.isActive = true

    yConstraint = videoView.bottomAnchor.constraint(equalTo: bottomAnchor)
    yConstraint.priority = .defaultHigh
    constraintsAll.append(yConstraint)

    constraintsAll.forEach { $0.isActive = true }
  }

  func initPosition() {
    let videoView = mainWindow.videoView
    let cph = Preference.float(for: .controlBarPositionHorizontal)
    let cpv = Preference.float(for: .controlBarPositionVertical)
    xConstraint.constant = videoView.frame.width * CGFloat(cph)
    yConstraint.constant = videoView.frame.height * CGFloat(cpv)
  }

  func updatePosition() {
    let videoView = mainWindow.videoView
    let windowWidth = videoView.frame.width
    let windowHeight = videoView.frame.height
    let cph = Preference.float(for: .controlBarPositionHorizontal)
    let cpv = Preference.float(for: .controlBarPositionVertical)

    let margin: CGFloat = 0
    let minWindowWidth: CGFloat = width
    var xPos: CGFloat

    if windowWidth < minWindowWidth {
      // osc is compressed
      xPos = windowWidth / 2
    } else {
      // osc has full width
      let oscHalfWidth: CGFloat = width * 0.5
      xPos = windowWidth * CGFloat(cph)
      if xPos - oscHalfWidth < margin {
        xPos = oscHalfWidth + margin
      } else if xPos + oscHalfWidth + margin > windowWidth {
        xPos = windowWidth - oscHalfWidth - margin
      }
    }

    var yPos = windowHeight * CGFloat(cpv)
    let oscHeight: CGFloat = 67
    let yMargin: CGFloat = 25

    if yPos < 0 {
      yPos = 0
    } else if yPos + oscHeight + yMargin > windowHeight {
      yPos = windowHeight - oscHeight - yMargin
    }

    xConstraint.constant = xPos
    yConstraint.constant = yPos
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
    let windowFrame = mainWindow.videoView.frame
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
    let xMax = windowFrame.width - frame.width
    let yMax = windowFrame.height - frame.height - 25
    newOrigin = newOrigin.constrained(to: NSRect(x: 0, y: 0, width: xMax, height: yMax))
    // apply position
    let newConstraint = newOrigin.x + frame.width / 2
    xConstraint.constant = userInterfaceLayoutDirection == .rightToLeft ?
      windowFrame.width - newConstraint : newConstraint
    yConstraint.constant = newOrigin.y
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
    let windowFrame = mainWindow.videoView.frame
    // save final position
    Preference.set(xConstraint.constant / windowFrame.width, for: .controlBarPositionHorizontal)
    Preference.set(yConstraint.constant / windowFrame.height, for: .controlBarPositionVertical)
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
