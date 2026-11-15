//
//  OSCView.swift
//  iina
//
//  Created by Hechen Li on 2026-11-12.
//  Copyright © 2026 lhc. All rights reserved.
//


extension NSStackView.VisibilityPriority {
  static let oscDetachEarly = NSStackView.VisibilityPriority(rawValue: 850)
  static let oscDetachEarlier = NSStackView.VisibilityPriority(rawValue: 800)
  static let oscDetachEarliest = NSStackView.VisibilityPriority(rawValue: 750)
}


fileprivate extension NSImage.SymbolConfiguration {
  static let arrowIconConfig = {
    if #available(macOS 26.0, *) {
      NSImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    } else {
      NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
    }
  }()
}


class OSCController {
  private unowned var mainWindow: MainWindowController!

  var oscViews: [Preference.OSCPosition: OSCViewContainer & NSView]!

  var playControlView: NSStackView!
  var playControlMiddleView: NSStackView!
  var leftArrowButton: NSButton!
  var rightArrowButton: NSButton!
  var speedLabelLeftContainer: NSView!
  var speedLabelRightContainer: NSView!
  var speedLabelLeft: NSTextField!
  var speedLabelRight: NSTextField!

  var volumeView: NSView!
  var toolbarView: NSStackView!
  var sliderView: NSView!

  var currentOSCViews: [NSView?]!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
  }

  func initialize() {
    self.oscViews = [
      .top: mainWindow.titleBarView,
      .bottom: mainWindow.oscBottomView,
      .floating: mainWindow.oscFloatingView,
      .minimal: mainWindow.oscMinimalView,
    ]

    self.volumeView = NSView()
    volumeView.translatesAutoresizingMaskIntoConstraints = false

    let muteButton = mainWindow.muteButton!
    let volumeSlider = mainWindow.volumeSlider!
    volumeView.addSubview(muteButton)
    volumeView.addSubview(volumeSlider)
    muteButton.padding(.vertical, .leading(4)).spacing(.trailing(4), to: volumeSlider)
    volumeSlider.size(width: 70).center(.y).padding(.trailing(6))

    self.playControlView = NSStackView()
    playControlView.translatesAutoresizingMaskIntoConstraints = false
    playControlView.orientation = .horizontal
    playControlView.alignment = .centerY
    playControlView.spacing = 0

    self.leftArrowButton = NSButton(image: .sf("backward.fill", withConfiguration: .arrowIconConfig)!,
                                    target: mainWindow, action: #selector(MainWindowController.leftButtonAction))
    leftArrowButton.maxAcceleratorLevel = 5

    self.rightArrowButton = NSButton(image: .sf("forward.fill", withConfiguration: .arrowIconConfig)!,
                                     target: mainWindow, action: #selector(MainWindowController.rightButtonAction))
    rightArrowButton.maxAcceleratorLevel = 5

    [mainWindow.playButton, leftArrowButton, rightArrowButton].forEach { button in
      button!.translatesAutoresizingMaskIntoConstraints = false
      button!.bezelStyle = .smallSquare
      button!.isBordered = false
      button!.size(width: 24, height: 24)
    }

    self.speedLabelLeftContainer = NSView()
    self.speedLabelRightContainer = NSView()
    [speedLabelLeftContainer, speedLabelRightContainer].forEach { view in
      view!.translatesAutoresizingMaskIntoConstraints = false
      view!.size(width: 30)  // label: 26 + padding: 8
    }

    self.speedLabelLeft = NSTextField(labelWithString: "")
    self.speedLabelRight = NSTextField(labelWithString: "")
    [speedLabelLeft, speedLabelRight].forEach { label in
      label!.translatesAutoresizingMaskIntoConstraints = false
      label!.font = .systemFont(ofSize: 10)
      label!.textColor = .secondaryLabelColor
    }
    speedLabelLeftContainer.addSubview(speedLabelLeft)
    speedLabelLeft.padding(.vertical, .trailing(8))
    speedLabelRightContainer.addSubview(speedLabelRight)
    speedLabelRight.padding(.vertical, .leading(8))

    self.playControlMiddleView = NSStackView(views: [leftArrowButton, mainWindow.playButton, rightArrowButton])
    playControlMiddleView.translatesAutoresizingMaskIntoConstraints = false
    playControlMiddleView.orientation = .horizontal
    playControlMiddleView.alignment = .centerY
    playControlMiddleView.spacing = 24

    self.toolbarView = NSStackView()
    toolbarView.translatesAutoresizingMaskIntoConstraints = false
    toolbarView.orientation = .horizontal
    toolbarView.alignment = .centerY
    toolbarView.spacing = 0
    toolbarView.size(height: 24)

    self.sliderView = TimeLabelOverflowedView()
    [mainWindow.leftLabel, mainWindow.rightLabel].forEach { label in
      label!.textColor = .secondaryLabelColor
      label!.alignment = .center
      label!.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
      label!.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
    }
    sliderView.translatesAutoresizingMaskIntoConstraints = false
    sliderView.addSubview(mainWindow.leftLabel)
    sliderView.addSubview(mainWindow.rightLabel)
    sliderView.addSubview(mainWindow.playSlider)
    sliderView.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
    mainWindow.leftLabel.padding(.leading(2)).spacing(.trailing(2), to: mainWindow.playSlider)
      .center(.y, with: mainWindow.playSlider)
    mainWindow.rightLabel.padding(.trailing(2)).spacing(.leading(2), to: mainWindow.playSlider)
      .center(.y, with: mainWindow.playSlider)
    mainWindow.playSlider.padding(.vertical(6))

    playControlView.addView(speedLabelLeftContainer, in: .center)
    playControlView.addView(playControlMiddleView, in: .center)
    playControlView.addView(speedLabelRightContainer, in: .center)
    // Video controllers and timeline indicators should not flip in a right-to-left language.
    playControlView.userInterfaceLayoutDirection = .leftToRight

    setupOSCToolbarButtons()
    if let action = Preference.ArrowButtonAction(key: .arrowButtonAction) {
      updateArrowButtons(action)
    }

    speedLabelLeft.isHidden = true
    speedLabelRight.isHidden = true
  }


  func updatePosition(from oscPosition: Preference.OSCPosition, to newPosition: Preference.OSCPosition, forced: Bool = false) {
    guard forced || oscPosition != newPosition else { return }

    // reset
    oscViews.values.forEach {
      $0.detachAllComponents()
    }
    [sliderView, playControlView, toolbarView, volumeView].forEach {
      $0!.removeFromSuperview()
    }

    playControlMiddleView.setViews(
      [leftArrowButton, mainWindow.playButton, rightArrowButton], in: .leading)

    playControlMiddleView.spacing = newPosition == .floating ? 20 : 16
    for (pos, view) in oscViews {
      view.setup(osc: self, isActive: newPosition == pos)
    }

    currentOSCViews = oscViews[newPosition]!.oscViews
  }

  func attachComponents(in stack: NSStackView) {
    playControlView.setVisibilityPriority(.notVisible, for: speedLabelLeftContainer)
    playControlView.setVisibilityPriority(.notVisible, for: speedLabelRightContainer)
    stack.addView(volumeView, in: .trailing)
    stack.addView(toolbarView, in: .trailing)
    stack.addView(playControlView, in: .leading)
    stack.addView(sliderView, in: .leading)
    stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
    stack.setVisibilityPriority(.mustHold, for: sliderView)
    stack.setVisibilityPriority(.oscDetachEarly, for: volumeView)
    stack.setVisibilityPriority(.oscDetachEarlier, for: toolbarView)
  }

  func setupOSCToolbarButtons() {
    let buttons = Preference.oscToolbarButtons
    let effectiveButtons = buttons.filter { $0 != .liveText || Preference.isLiveTextAvailable }
    toolbarView.views.forEach { toolbarView.removeView($0) }
    let liveTextEnabled = Preference.isLiveTextEnabled
    for buttonType in effectiveButtons {
      let button = NSButton()
      OSCToolbarButton.setStyle(of: button, buttonType: buttonType, reducedWidth: false)
      if buttonType == .liveText && liveTextEnabled {
        button.image = Preference.ToolBarButton.liveText.alternateImage()
      }
      button.action = #selector(mainWindow.toolBarButtonAction(_:))
      toolbarView.addView(button, in: .trailing)
    }
  }

  func highlightToolbarButton(_ button: Preference.ToolBarButton, _ isHighlighted: Bool) {
    let currentButton = toolbarView.views.lazy.compactMap { $0 as? NSButton }
      .first { $0.tag == button.rawValue }
    currentButton?.image = isHighlighted ? button.alternateImage() : button.image()
  }

  /// Configure the OSC arrow buttons based on IINA's `Use left/right button for` setting.
  ///
  /// For most settings the button is configured to be a
  /// [momentaryPushIn](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/momentarypushin)
  /// button. However if the button is set to control playback speed the button is configured to be a
  /// [multiLevelAccelerator](https://developer.apple.com/documentation/appkit/nsbutton/buttontype/multilevelaccelerator) button.
  /// This allows the user to control the speed using pressure when using devices that support pressure sensitivity.
  func updateArrowButtons(_ arrowBtnFunction: Preference.ArrowButtonAction) {
    let isPlaylist = arrowBtnFunction == .playlist
    leftArrowButton.image = .sf(isPlaylist ? "backward.end.fill" : "backward.fill",
                                withConfiguration: .arrowIconConfig)
    rightArrowButton.image = .sf(isPlaylist ? "forward.end.fill" : "forward.fill",
                                 withConfiguration: .arrowIconConfig)
    if arrowBtnFunction == .speed {
      leftArrowButton.setButtonType(.multiLevelAccelerator)
      rightArrowButton.setButtonType(.multiLevelAccelerator)
    } else {
      leftArrowButton.setButtonType(.momentaryPushIn)
      rightArrowButton.setButtonType(.momentaryPushIn)
      // if arrow button type changed while speed up/down, need to hide them
      playControlView.setVisibilityPriority(.notVisible, for: speedLabelLeftContainer)
      playControlView.setVisibilityPriority(.notVisible, for: speedLabelRightContainer)
    }
  }
}

protocol OSCViewContainer {
  func setup(osc: OSCController, isActive: Bool)
  var oscViews: [NSView?] { get }
  func detachAllComponents()
}
