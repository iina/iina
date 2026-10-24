//
//  SidebarSliderView.swift
//  iina
//
//  Created by Hechen Li on 2026-06-15.
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

fileprivate let ui = UIHelper.shared

/// Native parameter field shared by the player sidebars.
final class SidebarInputField: NSTextField {
  var emptyValue = "0"
  private var inputFocusMonitor: Any?
  private var isSendingAction = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    translatesAutoresizingMaskIntoConstraints = false
    usesSingleLineMode = true
    bezelStyle = .roundedBezel
    focusRingType = .exterior
    cell?.sendsActionOnEndEditing = true
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted {
      // AppKit places the caret after acquiring the shared field editor.
      DispatchQueue.main.async { [weak self] in self?.currentEditor()?.selectAll(nil) }
    }
    return accepted
  }

  override func mouseDown(with event: NSEvent) {
    super.mouseDown(with: event)
    currentEditor()?.selectAll(nil)
  }

  private func normalizeEmpty(_ editor: NSText?) {
    let text = editor?.string ?? stringValue
    guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    stringValue = emptyValue
    editor?.string = emptyValue
  }

  override func textShouldEndEditing(_ textObject: NSText) -> Bool {
    normalizeEmpty(textObject)
    return super.textShouldEndEditing(textObject)
  }

  override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    guard !isSendingAction else { return false }
    isSendingAction = true
    defer { isSendingAction = false }
    normalizeEmpty(currentEditor())
    return super.sendAction(action, to: target)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let inputFocusMonitor { NSEvent.removeMonitor(inputFocusMonitor) }
    inputFocusMonitor = nil
    guard window != nil else { return }
    // Video and sidebar background clicks do not normally transfer focus.
    inputFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      guard let self else { return event }
      return self.routeInputFocus(for: event)
    }
  }

  private func routeInputFocus(for event: NSEvent) -> NSEvent? {
    guard let window, event.window === window, let editor = currentEditor() else { return event }
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      // Further clicks hit AppKit's field editor, bypassing this control's mouseDown.
      editor.selectAll(nil)
      return nil
    }
    window.makeFirstResponder(nil)
    return event
  }

  deinit {
    if let inputFocusMonitor { NSEvent.removeMonitor(inputFocusMonitor) }
  }
}


class SidebarSliderView: NSView {
  unowned let player: PlayerCore

  var notificationKey: Notification.Name { .init("") }
  var slider: NSSlider!
  var tickMarkTextFieldsConstraints: [NSLayoutConstraint] = []
  var input: SidebarInputField!
  var indicator: NSTextField!
  var indicatorConstraint: NSLayoutConstraint!

  var inputWidth: CGFloat { 50 }
  var titleImage: NSImage? { nil }
  var titleKey: String { "" }
  var showsTitle: Bool { true }
  var titleAccessory: NSView? { nil }
  var tickMarkLabels: [String] { [] }

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    self.slider = AccentSlider()
    slider.translatesAutoresizingMaskIntoConstraints = false
    slider.controlSize = .small
    slider.tickMarkPosition = .below
    slider.target = self
    slider.action = #selector(sliderAction_)

    self.indicator = NSTextField(labelWithString: "")
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.font = .systemFont(ofSize: 10)
    indicator.setContentCompressionResistancePriority(.required, for: .horizontal)

    self.input = SidebarInputField()
    input.target = self
    input.action = #selector(customEditFinishedAction_)

    var titleViews = [
      ui.image(titleImage, size: 16, scaleUp: false) as NSView,
      ui.label(titleKey, font: .boldSystemFont(ofSize: 12)),
      ui.flexibleSpace(),
    ]
    if let titleAccessory { titleViews.append(titleAccessory) }
    let labelStack = ui.hStack(
      spacing: 8,
      titleViews
    )

    let tickMarkView = NSView()
    tickMarkView.translatesAutoresizingMaskIntoConstraints = false

    for (i, label) in tickMarkLabels.enumerated() {
      let label = NSTextField(labelWithString: label)
      label.translatesAutoresizingMaskIntoConstraints = false
      label.font = .systemFont(ofSize: 10)
      tickMarkView.addSubview(label)
      label.padding(.vertical)
      if i == 0 {
        label.leadingAnchor.constraint(equalTo: tickMarkView.leadingAnchor).isActive = true
      } else if i == tickMarkLabels.count - 1 {
        label.trailingAnchor.constraint(equalTo: tickMarkView.trailingAnchor).isActive = true
      } else {
        let constraint = label.centerXAnchor.constraint(equalTo: tickMarkView.leadingAnchor, constant: 0)
        constraint.isActive = true
        tickMarkTextFieldsConstraints.append(constraint)
      }
    }

    setup()

    if showsTitle { addSubview(labelStack) }
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

    slider.padding(.leading, .bottom(16))
    if showsTitle {
      labelStack.padding(.horizontal, .top)
      slider.spacing(.top(18), to: labelStack)
      input.padding(.trailing)
    } else {
      slider.padding(.top(18))
      input.padding(.trailing)
    }
    input.spacing(.leading(8), to: slider).center(.y, with: slider).size(width: inputWidth, height: 24)
    tickMarkView.padding(.leading, .bottom)

    tickMarkView.widthAnchor.constraint(equalTo: slider.widthAnchor, multiplier: 1).isActive = true

    player.observe(notificationKey) { [unowned self] _ in
      update_()
    }
  }

  override func viewDidMoveToSuperview() {
    update_()
  }

  override func layout() {
    super.layout()

    let numSpaces = CGFloat(tickMarkLabels.count - 1)
    for (i, constraint) in tickMarkTextFieldsConstraints.enumerated() {
      let xPos = xOffset(CGFloat(i + 1) / numSpaces)
      if constraint.constant != xPos {
        constraint.constant = xPos
      }
    }
    updateIndicator()
  }

  func xOffset(_ p: CGFloat) -> CGFloat {
    let knobWidth = slider.knobThickness
    return knobWidth / 2 + p * (slider.frame.size.width - knobWidth)
  }

  func updateIndicator() {
    /// Use `customSpeedTextField.stringValue` to take advantage of its formatter
    /// (e.g. `16` will be displayed instead of `16.0`)
    indicator.stringValue = indicatorLabel()

    let p = CGFloat((slider.doubleValue - slider.minValue) / (slider.maxValue - slider.minValue))
    let xPos = xOffset(p)
    if indicatorConstraint.constant != xPos {
      indicatorConstraint.constant = xPos
    }
  }

  private func update_() {
    guard player.info.state.active else { return }
    update()
  }

  @objc private func sliderAction_(_ sender: NSSlider) {
    player.performSidebarChange { sliderAction() }
  }

  @objc private func customEditFinishedAction_(_ sender: NSTextField) {
    player.performSidebarChange { customEditFinishedAction() }
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

