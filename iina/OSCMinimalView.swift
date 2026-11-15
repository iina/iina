//
//  OSCMinimalView.swift
//  iina
//
//  Created by Hechen Li on 2026-11-12.
//  Copyright © 2026 lhc. All rights reserved.
//


fileprivate extension LayoutValue {
  static let oscPaddingVertical = LayoutValue(6, 4)
  static let oscPaddingLeading = LayoutValue(10, 6)
  static let oscPaddingTrailing = LayoutValue(10, 6)
}


fileprivate let ui = UIHelper()


class OSCMinimalView: NSView {
  weak var mainWindow: MainWindowController!
  private let prefObserver = Preference.Observer()

  var oscView: TimeLabelOverflowedStackView!

  private var mainView: TranslucentView!
  private var toolbarView: TranslucentView!
  private var playButtonView: TranslucentView!
  private var leftArrowView: TranslucentView!
  private var rightArrowView: TranslucentView!

  private var container: NSView!
  private var toolbarContainer: NSStackView!
  private var playButtonContainer: NSStackView!
  private var leftArrowContainer: NSStackView!
  private var rightArrowContainer: NSStackView!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    self.mainView = TranslucentView(liquidGlassCornerRadius: 24, vevCornerRadius: 12, padding: (0, 0))
    self.toolbarView = TranslucentView(liquidGlassCornerRadius: 24, vevCornerRadius: 12, padding: (12, 8))
    self.playButtonView = TranslucentView(liquidGlassCornerRadius: 32, padding: (20, 20))
    self.leftArrowView = TranslucentView(liquidGlassCornerRadius: 32, padding: (12, 14))
    self.rightArrowView = TranslucentView(liquidGlassCornerRadius: 32, padding: (12, 14))

    super.init(frame: .zero)

    postsFrameChangedNotifications = true
    translatesAutoresizingMaskIntoConstraints = false

    NotificationCenter.default.addObserver(
      forName: NSView.frameDidChangeNotification,
      object: self,
      queue: .main
    ) { [unowned self] _ in
      toolbarView.isHidden = frame.height < 280
      [playButtonView, leftArrowView, rightArrowView].forEach {
        $0.isHidden = frame.height < 180
      }
    }

    self.container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    self.toolbarContainer = NSStackView()
    toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
    self.playButtonContainer = NSStackView()
    playButtonContainer.translatesAutoresizingMaskIntoConstraints = false
    self.leftArrowContainer = NSStackView()
    leftArrowContainer.translatesAutoresizingMaskIntoConstraints = false
    leftArrowContainer.addView(ui.space(width: 4, height: 8), in: .center)
    leftArrowContainer.spacing = 0
    self.rightArrowContainer = NSStackView()
    rightArrowContainer.translatesAutoresizingMaskIntoConstraints = false
    rightArrowContainer.addView(ui.space(width: 4, height: 8), in: .center)
    rightArrowContainer.spacing = 0

    self.oscView = TimeLabelOverflowedStackView()
    oscView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(oscView)
    oscView.padding(.vertical(.oscPaddingVertical), .trailing(.oscPaddingTrailing), .leading(.oscPaddingLeading))

    mainView.setContent(container)
    toolbarView.setContent(toolbarContainer)
    playButtonView.setContent(playButtonContainer)
    leftArrowView.setContent(leftArrowContainer)
    rightArrowView.setContent(rightArrowContainer)

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
    oscView.addView(osc.volumeView, in: .trailing)
    oscView.addView(osc.sliderView, in: .leading)
    oscView.setClippingResistancePriority(.defaultLow, for: .horizontal)
    oscView.setVisibilityPriority(.mustHold, for: osc.sliderView)
    oscView.setVisibilityPriority(.oscDetachEarly, for: osc.volumeView)

    toolbarContainer.addView(osc.toolbarView, in: .center)
    playButtonContainer.addView(mainWindow.playButton, in: .center)
    leftArrowContainer.insertView(osc.leftArrowButton, at: 0, in: .center)
    rightArrowContainer.addView(osc.rightArrowButton, in: .center)
  }

  func detachAllComponents() {
    [oscView, toolbarContainer, playButtonContainer].forEach { v in
      v.views.forEach(v.removeView)
    }
  }
}
