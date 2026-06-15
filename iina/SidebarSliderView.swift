//
//  SidebarSliderView.swift
//  iina
//
//  Created by Hechen Li on 2026-06-15.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let ui = UIHelper.shared


class SidebarSliderView: NSView {
  unowned let player: PlayerCore

  var notificationKey: Notification.Name { .init("") }
  var slider: NSSlider!
  var input: NSTextField!
  var indicator: NSTextField!
  var indicatorConstraint: NSLayoutConstraint!
  var resetButton: NSButton!

  var sliderWidth: CGFloat { 240 }
  var titleImage: NSImage? { nil }
  var titleKey: String { "" }
  var tickMarkLabels: [String] { [] }

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    self.slider = NSSlider()
    slider.translatesAutoresizingMaskIntoConstraints = false
    slider.controlSize = .small
    slider.tickMarkPosition = .below
    slider.target = self
    slider.action = #selector(sliderAction_)

    self.indicator = NSTextField(labelWithString: "")
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.font = .systemFont(ofSize: 10)
    indicator.setContentCompressionResistancePriority(.required, for: .horizontal)

    self.input = NSTextField()
    input.translatesAutoresizingMaskIntoConstraints = false
    input.usesSingleLineMode = true
    input.target = self
    input.action = #selector(customEditFinishedAction_)

    self.resetButton = NSButton(
      image: .sf("arrow.counterclockwise.circle.fill")!,
      target: self, action: #selector(resetButtonAction_)
    )
    resetButton.bezelStyle = .smallSquare
    resetButton.isBordered = false

    let labelStack = ui.hStack(
      spacing: 8,
      ui.image(titleImage, size: 16, scaleUp: false),
      ui.label(titleKey, font: .boldSystemFont(ofSize: 12)),
      ui.flexibleSpace(),
      resetButton,
    )

    let numSpaces = CGFloat(tickMarkLabels.count - 1)

    let tickMarkView = NSView()
    tickMarkView.translatesAutoresizingMaskIntoConstraints = false
    for (i, label) in tickMarkLabels.enumerated() {
      let label = NSTextField(labelWithString: label)
      label.translatesAutoresizingMaskIntoConstraints = false
      label.font = .systemFont(ofSize: 10)
      tickMarkView.addSubview(label)
      let xPos = xOffset(CGFloat(i) / numSpaces)
      let constraint = label.centerXAnchor
        .constraint(equalTo: tickMarkView.leadingAnchor, constant: xPos)
      constraint.priority = .defaultHigh
      constraint.isActive = true
      label.padding(.vertical, .horizontal(greaterThan: 0))
    }

    setup()

    addSubview(labelStack)
    addSubview(slider)
    addSubview(indicator)
    addSubview(input)
    addSubview(tickMarkView)

    indicator.padding(.horizontal(greaterThan: 0))
      .spacing(.bottom(2), to: slider)
    self.indicatorConstraint = indicator.centerXAnchor
      .constraint(equalTo: slider.leadingAnchor)
    indicatorConstraint.priority = .init(800)
    indicatorConstraint.isActive = true

    labelStack.padding(.horizontal, .top)
    slider.padding(.leading, .bottom(16))
      .spacing(.top(18), to: labelStack)
      .size(width: sliderWidth)
    input.padding(.trailing).spacing(.leading(8), to: slider)
      .center(.y, with: slider)
    tickMarkView.padding(.leading, .bottom)
      .size(width: sliderWidth)

    player.observe(notificationKey) { [unowned self] _ in
      update_()
    }
  }

  override func viewDidMoveToSuperview() {
    update_()
  }

  func xOffset(_ p: CGFloat) -> CGFloat {
    let knobWidth = slider.knobThickness
    return knobWidth / 2 + p * (sliderWidth - knobWidth)
  }

  func updateIndicator() {
    /// Use `customSpeedTextField.stringValue` to take advantage of its formatter
    /// (e.g. `16` will be displayed instead of `16.0`)
    indicator.stringValue = indicatorLabel()

    let p = CGFloat((slider.doubleValue - slider.minValue) / (slider.maxValue - slider.minValue))
    indicatorConstraint.constant = xOffset(p)
    layout()
  }

  private func update_() {
    guard player.info.state.active else { return }
    update()
  }

  @objc private func sliderAction_(_ sender: NSSlider) {
    sliderAction()
  }

  @objc private func customEditFinishedAction_(_ sender: NSTextField) {
    customEditFinishedAction()
  }

  @objc private func resetButtonAction_(_ sender: AnyObject) {
    resetButtonAction()
  }

  func setup() {}
  func update() {}
  func indicatorLabel() -> String { input.stringValue }
  func sliderAction() {}
  func customEditFinishedAction() {}
  func resetButtonAction() {}

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

