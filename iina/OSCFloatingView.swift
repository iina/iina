//
//  OSCFloatingView.swift
//  iina
//
//  Created by Hechen Li on 2026-06-09.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate extension LayoutValue {
  static let oscPaddingTop = LayoutValue(14, 10)
  static let oscPaddingBottom = LayoutValue(16, 10)
}

/// Button used by the floating OSC so AppKit keeps the native tracking path active.
class OSCButton: NSButton {
  enum Role {
    case standard
    case transport
    case primary

    var floatingSize: CGFloat {
      switch self {
      case .standard: 24
      case .transport: 32
      case .primary: 48
      }
    }
  }

  private var originalImageScaling: NSImageScaling?
  private var originalImagePosition: NSControl.ImagePosition?
  private var originalBezelStyle: NSButton.BezelStyle?
  private var originalIsBordered: Bool?
  private var originalContentTintColor: NSColor?
  private var originalConstraintSizes: [ObjectIdentifier: CGFloat] = [:]
  private var usesQuickTimeStyle = false
  private var isPressed = false
  @objc dynamic private var visualScale: CGFloat = 1 {
    didSet { needsDisplay = true }
  }

  override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
    if key == "visualScale" {
      return CABasicAnimation()
    }
    return super.defaultAnimation(forKey: key)
  }

  func setQuickTimeStyle(_ enabled: Bool, role: Role = .standard) {
    if originalImageScaling == nil {
      originalImageScaling = imageScaling
      originalImagePosition = imagePosition
      originalBezelStyle = bezelStyle
      originalIsBordered = isBordered
      originalContentTintColor = contentTintColor
    }

    usesQuickTimeStyle = enabled
    if enabled {
      imagePosition = .imageOnly
      imageScaling = .scaleProportionallyDown
      bezelStyle = .shadowlessSquare
      isBordered = false
      contentTintColor = .white.withAlphaComponent(0.84)
    } else {
      imagePosition = originalImagePosition!
      imageScaling = originalImageScaling!
      bezelStyle = originalBezelStyle!
      isBordered = originalIsBordered!
      contentTintColor = originalContentTintColor
      setPressed(false)
    }

    for constraint in constraints where (constraint.firstItem as? NSButton) === self {
      guard constraint.secondItem == nil,
            constraint.firstAttribute == .width || constraint.firstAttribute == .height else { continue }
      let key = ObjectIdentifier(constraint)
      if originalConstraintSizes[key] == nil {
        originalConstraintSizes[key] = constraint.constant
      }
      constraint.constant = enabled ? role.floatingSize : originalConstraintSizes[key]!
    }
  }

  override func mouseDown(with event: NSEvent) {
    if usesQuickTimeStyle {
      setPressed(true)
      super.mouseDown(with: event)
      setPressed(false)
      return
    }
    super.mouseDown(with: event)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard usesQuickTimeStyle, visualScale != 1 else {
      super.draw(dirtyRect)
      return
    }
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: bounds.midX, yBy: bounds.midY)
    transform.scale(by: visualScale)
    transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
    transform.concat()
    super.draw(dirtyRect)
    NSGraphicsContext.restoreGraphicsState()
  }

  private func setPressed(_ pressed: Bool) {
    guard isPressed != pressed else { return }
    isPressed = pressed
    highlight(pressed)
    let scale: CGFloat = pressed ? 0.94 : 1
    guard !Preference.bool(for: .disableAnimations) else {
      visualScale = scale
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = pressed ? 0.1 : 0.15
      context.timingFunction = CAMediaTimingFunction(name: pressed ? .easeInEaseOut : .easeOut)
      animator().visualScale = scale
    }
  }
}

private final class OSCFloatingContentView: NSView {
  private weak var mainWindow: MainWindowController?
  weak var dragSurface: NSView?

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point), let mainWindow else { return nil }

    var controls: [NSView] = mainWindow.oscToolbarView?.subviews ?? []
    controls.append(contentsOf: [mainWindow.volumeSlider, mainWindow.muteButton,
                                 mainWindow.leftArrowButton, mainWindow.playButton,
                                 mainWindow.rightArrowButton, mainWindow.leftLabel,
                                 mainWindow.rightLabel, mainWindow.playSlider].compactMap { $0 })
    for control in controls.reversed()
      where control.isDescendant(of: self) && !control.isHiddenOrHasHiddenAncestor {
      let localPoint = control.convert(point, from: self)
      if control.bounds.contains(localPoint) {
        return control.hitTest(localPoint) ?? control
      }
    }

    return dragSurface
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }
}

private final class OSCFloatingDragSurface: NSView {
  weak var owner: OSCFloatingView?

  override var mouseDownCanMoveWindow: Bool { false }

  override func mouseDown(with event: NSEvent) {
    owner?.mouseDown(with: event)
  }

  override func mouseDragged(with event: NSEvent) {
    owner?.mouseDragged(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    owner?.mouseUp(with: event)
  }
}


class OSCFloatingView: TranslucentView {
  static let preferredWidth: CGFloat = 460
  private let width = preferredWidth
  weak var mainWindow: MainWindowController!
  private let prefObserver = Preference.Observer()

  var oscTopView: NSStackView!
  var oscBottomView: TimeLabelOverflowedStackView!

  private var xConstraint: NSLayoutConstraint!
  private var yConstraint: NSLayoutConstraint!

  var mousePosRelatedToView: CGPoint?

  var isDragging: Bool = false

  private var isAlignFeedbackSent = false

  @discardableResult
  func routeMouseDown(_ event: NSEvent) -> Bool {
    let point = convert(event.locationInWindow, from: nil)
    guard bounds.contains(point), let content else { return false }
    let contentPoint = content.convert(point, from: self)
    guard let targetView = content.hitTest(contentPoint) else { return false }
    if targetView === content {
      mouseDown(with: event)
    } else {
      targetView.mouseDown(with: event)
    }
    return true
  }

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    let container = OSCFloatingContentView(mainWindow: mainWindow)
    container.translatesAutoresizingMaskIntoConstraints = false

    super.init(liquidGlassCornerRadius: 24, vevCornerRadius: 20,
               liquidGlassInteractive: true, padding: (0, 0))

    let dragSurface = OSCFloatingDragSurface()
    dragSurface.translatesAutoresizingMaskIntoConstraints = false
    dragSurface.owner = self
    container.addSubview(dragSurface, positioned: .below, relativeTo: nil)
    dragSurface.padding(.all)
    container.dragSurface = dragSurface

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

  override func setStyle(_ newStyle: TranslucentView.Style, force: Bool = false) {
    super.setStyle(newStyle, force: force)
    guard case .visualEffect = newStyle,
          let visualEffectView = container as? NSVisualEffectView else { return }
    visualEffectView.material = .hudWindow
    visualEffectView.appearance = NSAppearance(named: .darkAqua)
  }

  func setupConstraints() {
    let videoView = mainWindow.videoViewContainer!
    padding(.horizontal(greaterThan: 1), from: videoView)

    xConstraint = centerXAnchor.constraint(equalTo: videoView.leadingAnchor)
    xConstraint.priority = .defaultLow
    xConstraint.isActive = true

    yConstraint = videoView.bottomAnchor.constraint(equalTo: bottomAnchor)
    yConstraint.priority = .defaultHigh
    yConstraint.isActive = true
  }

  func initPosition() {
    let videoView = mainWindow.videoViewContainer!
    let cph = Preference.float(for: .controlBarPositionHorizontal)
    let cpv = Preference.float(for: .controlBarPositionVertical)
    xConstraint.constant = videoView.frame.width * CGFloat(cph)
    yConstraint.constant = videoView.frame.height * CGFloat(cpv)
  }

  func updatePosition() {
    let videoView = mainWindow.videoViewContainer!
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
    let newConstraint = newOrigin.x + frame.width / 2
    xConstraint.constant = userInterfaceLayoutDirection == .rightToLeft ?
      windowFrame.width - newConstraint : newConstraint
    yConstraint.constant = newOrigin.y
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
    let windowFrame = mainWindow.videoViewContainer.frame
    // save final position
    Preference.set(xConstraint.constant / windowFrame.width, for: .controlBarPositionHorizontal)
    Preference.set(yConstraint.constant / windowFrame.height, for: .controlBarPositionVertical)
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
