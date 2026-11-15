//
//  OSCMinimalView.swift
//  iina
//
//  Created by Hechen Li on 2026-11-12.
//  Copyright © 2026 lhc. All rights reserved.
//


fileprivate extension LayoutValue {
  static let oscPaddingVertical = LayoutValue(6, 4)
  static let oscPaddingHorizontal = LayoutValue(10, 6)
  static let toolbarPaddingVertical = LayoutValue(8, 6)
  static let toolbarPaddingHorizontal = LayoutValue(12, 8)
}


class OSCMinimalView: NSView {
  weak var mainWindow: MainWindowController!
  private let prefObserver = Preference.Observer()

  private var mainView: TranslucentView!
  private var toolbarView: TranslucentView!
  private var playButtonView: TranslucentView!
  private var leftArrowView: TranslucentView!
  private var rightArrowView: TranslucentView!

  private var container: NSView!
  private var toolbarContainer: NSView!

  private var playSlider: TimeLabelOverflowedStackView!
  private var toolbar: NSStackView!
  private var playButton: NSStackView!
  private var leftArrow: NSStackView!
  private var rightArrow: NSStackView!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    self.mainView = TranslucentView(liquidGlassCornerRadius: 24, vevCornerRadius: 12, padding: (0, 0))
    self.toolbarView = TranslucentView(liquidGlassCornerRadius: 24, vevCornerRadius: 12, padding: (0, 0))
    self.playButtonView = TranslucentView(liquidGlassCornerRadius: 32, padding: (20, 20))
    self.leftArrowView = TranslucentView(liquidGlassCornerRadius: 32, padding: (12, 12))
    self.rightArrowView = TranslucentView(liquidGlassCornerRadius: 32, padding: (12, 12))

    super.init(frame: .zero)

    postsFrameChangedNotifications = true
    translatesAutoresizingMaskIntoConstraints = false

    NotificationCenter.default.addObserver(
      forName: NSView.frameDidChangeNotification,
      object: self,
      queue: .main
    ) { [unowned self] _ in
      toolbarView.isHidden = frame.height < 280
      mainView.isHidden = frame.height < 180
    }

    self.container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    self.toolbarContainer = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    self.toolbar = NSStackView()
    toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
    self.playButton = NSStackView()
    playButton.translatesAutoresizingMaskIntoConstraints = false
    self.leftArrow = NSStackView()
    leftArrow.translatesAutoresizingMaskIntoConstraints = false
    self.rightArrow = NSStackView()
    rightArrow.translatesAutoresizingMaskIntoConstraints = false

    self.playSlider = TimeLabelOverflowedStackView()
    playSlider.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(playSlider)
    playSlider.padding(.vertical(.oscPaddingVertical), .horizontal(.oscPaddingHorizontal))

    self.toolbar = NSStackView()
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    toolbarContainer.addSubview(toolbar)
    toolbar.padding(.vertical(.toolbarPaddingVertical), .horizontal(.toolbarPaddingHorizontal))

    mainView.setContent(container)
    toolbarView.setContent(toolbarContainer)
    playButtonView.setContent(playButton)
    leftArrowView.setContent(leftArrow)
    rightArrowView.setContent(rightArrow)

    addSubview(mainView)
    mainView.padding(.bottom(10), .horizontal(12))

    addSubview(toolbarView)
    toolbarView.padding(.trailing(12))
    toolbarView.spacing(.bottom(12), to: mainView)

    addSubview(playButtonView)
    playButtonView.center(.x).center(.y)

    addSubview(leftArrowView)
    leftArrowView.center(.y, with: playButtonView).spacing(.trailing(20), to: playButtonView)

    addSubview(rightArrowView)
    rightArrowView.center(.y, with: playButtonView).spacing(.leading(20), to: playButtonView)

    prefObserver.add(.useLiquidGlassOSC, runNow: true) { [unowned self] _ in
      mainView.setStyle(Preference.liquidGlass(.osc) ? .liquidGlass : .visualEffect)
    }
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


extension OSCMinimalView: OSCViewContainer {
  var oscViews: [NSView?] {
    [mainView, toolbarView, playButtonView]
  }

  func setup(osc: OSCController, isActive: Bool) {
    guard isActive else { return }

    osc.playControlView.setVisibilityPriority(.notVisible, for: osc.speedLabelLeftContainer)
    osc.playControlView.setVisibilityPriority(.notVisible, for: osc.speedLabelRightContainer)
    playSlider.addView(osc.volumeView, in: .trailing)
    playSlider.addView(osc.sliderView, in: .leading)
    playSlider.setClippingResistancePriority(.defaultLow, for: .horizontal)
    playSlider.setVisibilityPriority(.mustHold, for: osc.sliderView)
    playSlider.setVisibilityPriority(.oscDetachEarly, for: osc.volumeView)

    toolbar.addView(osc.toolbarView, in: .center)
    playButton.addView(mainWindow.playButton, in: .center)
    leftArrow.addView(osc.leftArrowButton, in: .center)
    rightArrow.addView(osc.rightArrowButton, in: .center)
  }

  func detachAllComponents() {
    [playSlider, toolbar, playButton, leftArrow, rightArrow].forEach { v in
      v.views.forEach(v.removeView)
    }
  }
}
