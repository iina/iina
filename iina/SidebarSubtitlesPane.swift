//
//  SidebarSubtitlesPane.swift
//  iina
//
//  Created by Hechen Li on 2026-06-15.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let ui = UIHelper.shared


class SidebarSubtitlesPane: SidebarScrollView {
  let prefObserver = Preference.Observer()
  weak var player: PlayerCore!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    drawsBackground = false

    let stack = ui.vStack(spacing: .sidebarStackViewSpacing)

    stack.addArrangedSubview(ui.vStack(
      spacing: .sidebarItemSpacing,
      wantsToGrow: true,
      ui.hStack(
        spacing: 8,
        ui.image("1.square.fill", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.primary", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        VisibilitySwitch(player: player, isPrimary: true),
      ),
      Container(TrackSelector(
        .sub,
        player: player,
        observedKeys: [.iinaSIDChanged]
      )) {
        $0.padding(.all)
      }
    ))

    stack.addArrangedSubview(ui.vStack(
      spacing: .sidebarItemSpacing,
      wantsToGrow: true,
      ui.hStack(
        spacing: 8,
        ui.image("2.square.fill", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.secondary", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        VisibilitySwitch(player: player, isPrimary: false),
      ),
      Container(TrackSelector(
        .secondSub,
        player: player,
        observedKeys: [.iinaSIDChanged]
      )) {
        $0.padding(.all)
      }
    ))

    stack.addArrangedSubview(Container(LoadSubtitleView(player: player)) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    stack.addArrangedSubview(Container(SubPositionDelayView(player: player)) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    let textStyleView = Container(SubStyleView(player: player)) {
      $0.padding(.all(.sidebarContainerPadding))
    }
    stack.addArrangedSubview(textStyleView)

    let imageWarning = Container(ui.label(
      "sidebar.sub_settings_not_available", wrapping: true, isSmall: true, isSecondary: true)) {
        $0.padding(
          .vertical(.sidebarContainerPadding),
          .leading(.sidebarContainerPadding),
          .trailing(greaterThan: .sidebarContainerPadding)
        )
      }
    stack.addArrangedSubview(imageWarning)

    let assWarning = Container(ui.label(
      "sidebar.sub_style_warning", wrapping: true, isSmall: true, isSecondary: true)) {
        $0.padding(
          .vertical(.sidebarContainerPadding),
          .leading(.sidebarContainerPadding),
          .trailing(greaterThan: .sidebarContainerPadding)
        )
      }
    stack.addArrangedSubview(assWarning)

    documentView!.addSubview(stack)
    stack.padding(.horizontal(.sidebarMargin), .top(4), .bottom(.sidebarMargin))

    let block = { (_: Notification) in
      let tracks = ([.sub, .secondSub] as [MPVTrack.TrackType]).compactMap {
        player.info.currentTrack($0)
      }
      let hasText = tracks.isEmpty || tracks.map { !$0.isImageSub }.reduce(false) { $0 || $1 }
      let isASS = tracks.map { $0.isAssSub }.reduce(false) { $0 || $1 }

      stack.setVisibilityPriority(hasText ? .mustHold : .notVisible, for: textStyleView)
      stack.setVisibilityPriority(hasText ? .notVisible : .mustHold, for: imageWarning)
      stack.setVisibilityPriority(isASS ? .mustHold : .notVisible, for: assWarning)
    }

    block(.init(name: .init("")))
    player.observe(.iinaSIDChanged, block: block)
    player.observe(.iinaTracklistChanged, block: block)
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class VisibilitySwitch: NSSwitch {
  private unowned let player: PlayerCore
  private let isPrimary: Bool

  init(player: PlayerCore, isPrimary: Bool) {
    self.player = player
    self.isPrimary = isPrimary
    super.init(frame: .zero)

    if #available(macOS 26, *) {
      controlSize = .mini
    }
    target = self
    action = #selector(switchAction)
    update()

    player.observe(.iinaSubVisibilityChanged) { [unowned self] _ in
      update()
    }
  }

  private func update() {
    let isVisible = isPrimary ?
      player.info.isSubVisible : player.info.isSecondSubVisible
    state = isVisible ? .on : .off
  }

  @objc private func switchAction(_ sender: AnyObject) {
    if isPrimary {
      player.toggleSubVisibility()
    } else {
      player.toggleSecondSubVisibility()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class LoadSubtitleView: NSView {
  private unowned let player: PlayerCore

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    let loadSubSegment = NSSegmentedControl(
      labels: [NSLocalizedString("sidebar.load_subtitle", comment: ""), ""],
      trackingMode: .momentary,
      target: self,
      action: #selector(loadExternalSubAction)
    )
    loadSubSegment.trackingMode = .momentary
    loadSubSegment.target = self
    loadSubSegment.action = #selector(loadExternalSubAction)
    loadSubSegment.setImage(.sf("chevron.down"), forSegment: 1)

    let searchOnlineButton = ui.button(
      "sidebar.search_online", target: self, action: #selector(searchOnlineAction)
    )

    let stack = ui.hStack(
      spacing: 8,
      loadSubSegment,
      searchOnlineButton,
    )
    addSubview(stack)
    stack.padding(.all)
  }

  @objc func loadExternalSubAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == 0 {
      let currentDir = player.info.currentURL?.deletingLastPathComponent()
      Utility.quickOpenPanel(title: "Load external subtitle", chooseDir: false, dir: currentDir,
                             sheetWindow: player.currentWindow,
                             allowedFileTypes: Utility.containsSubExt) { url in
        self.player.loadExternalSubFile(url, delay: true)
      }
    } else if sender.selectedSegment == 1 {
      player.mainWindow.showSubChooseMenu(forView: sender)
    }
  }

  @objc func searchOnlineAction(_ sender: AnyObject) {
    player.mainWindow.menuActionHandler.menuFindOnlineSub(.dummy)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class SubDelayView: SidebarSliderView {
  var isPrimary: Bool = true

  override var titleImage: NSImage? {
    .sf("clock.arrow.trianglehead.counterclockwise.rotate.90", "clock.arrow.circlepath",
        withConfiguration: .sidebarIconConfig)
  }
  override var titleKey: String { "sidebar.delay" }
  override var tickMarkLabels: [String] {
    ["-5s", "0s", "+5s"]
  }
  override var notificationKey: Notification.Name {
    .iinaSubDelayChanged
  }

  override func setup() {
    slider.minValue = -5
    slider.maxValue = 5
    slider.numberOfTickMarks = 21
    if #available(macOS 26, *) {
      slider.neutralValue = 0
    }

    let fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    fmt.maximumSignificantDigits = 3
    input.formatter = fmt
  }

  override func indicatorLabel() -> String {
    "\(input.stringValue)s"
  }

  override func update() {
    let delayOption = isPrimary ? MPVOption.Subtitles.subDelay : MPVOption.Subtitles.secondarySubDelay
    let subDelay = player.mpv.getDouble(delayOption)
    slider.doubleValue = subDelay
    input.doubleValue = subDelay
    resetButton.isHidden = slider.doubleValue == 0
    updateIndicator()
  }

  override func sliderAction() {
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      slider.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      slider.allowsTickMarkValuesOnly = false
    }
    let sliderValue = slider.doubleValue
    input.doubleValue = sliderValue
    updateIndicator()
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        player.setSubDelay(sliderValue, forPrimary: isPrimary)
      }
    }
  }

  override func customEditFinishedAction() {
    if input.stringValue.isEmpty {
      input.stringValue = "0"
    }
    let value = input.doubleValue
    player.setSubDelay(value, forPrimary: isPrimary)
    slider.doubleValue = value
    if let window = input.window {
      window.makeFirstResponder(window.contentView)
    }
  }

  override func resetButtonAction() {
    player.setAudioDelay(0)
  }
}


fileprivate class SubPositionDelayView: NSView {
  private unowned let player: PlayerCore
  var isPrimary: Bool = true

  private var primarySwitch: NSSegmentedControl!
  private var positionSlider: NSSlider!
  private var delayView: SubDelayView!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    self.primarySwitch = NSSegmentedControl()
    primarySwitch.controlSize = .small
    primarySwitch.segmentCount = 2
    primarySwitch.setLabel(NSLocalizedString("sidebar.primary", comment: ""), forSegment: 0)
    primarySwitch.setLabel(NSLocalizedString("sidebar.secondary", comment: ""), forSegment: 1)
    primarySwitch.selectedSegment = 0
    primarySwitch.setContentHuggingPriority(.init(100), for: .horizontal)
    primarySwitch.segmentDistribution = .fillEqually

    self.positionSlider = NSSlider()
    positionSlider.minValue = 0
    positionSlider.maxValue = 100
    positionSlider.controlSize = .small
    positionSlider.target = self
    positionSlider.action = #selector(positionAction)

    if #available(macOS 26.0, *) {
      positionSlider.tintProminence = .none
    }

    self.delayView = SubDelayView(player: player)

    let stack = ui.vStack(
      spacing: .sidebarItemSpacing,
      wantsToGrow: true,
      primarySwitch,
      ui.space(),
      delayView,
      ui.hStack(
        spacing: 8,
        ui.image("arrow.up.and.down", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.position", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
      ),
      positionSlider,
    )
    addSubview(stack)
    stack.padding(.all)

    update()
    player.observe(.iinaSubPositionChanged) { [unowned self] _ in
      updatePosition()
    }
  }

  private func update() {
    updatePosition()
    delayView.update()
  }

  private func updatePosition() {
    let posOption = isPrimary ? MPVOption.Subtitles.subPos : MPVOption.Subtitles.secondarySubPos
    positionSlider.intValue = Int32(player.mpv.getInt(posOption))
  }

  @objc private func switchAction(_ sender: AnyObject) {
    isPrimary = primarySwitch.selectedSegment == 0
    update()
  }

  @objc private func positionAction(_ sender: AnyObject) {
    player.setSubPos(Int(positionSlider.intValue), forPrimary: isPrimary)
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class SubStyleView: NSView {
  private unowned let player: PlayerCore

  private var scaleSlider: NSSlider!
  private var fontChooser: NSButton!
  private var fontSizePicker: NSPopUpButton!
  private var borderSizePicker: NSPopUpButton!
  private var textColorWell: NSColorWell!
  private var backgroundColorWell: NSColorWell!
  private var borderColorWell: NSColorWell!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    self.scaleSlider = NSSlider()
    scaleSlider.minValue = -5
    scaleSlider.maxValue = 5
    scaleSlider.controlSize = .small
    scaleSlider.target = self
    scaleSlider.action = #selector(scaleAction)
    if #available(macOS 26.0, *) {
      scaleSlider.neutralValue = 0
    }

    let scaleResetButton = NSButton(
      image: .sf("arrow.counterclockwise.circle.fill")!,
      target: self, action: #selector(scaleResetButtonAction)
    )
    scaleResetButton.bezelStyle = .smallSquare
    scaleResetButton.isBordered = false

    self.fontChooser = NSButton()
    fontChooser.bezelStyle = .push
    fontChooser.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
    fontChooser.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    fontChooser.target = self
    fontChooser.action = #selector(chooseSubFontAction)

    self.fontSizePicker = NSPopUpButton()
    for i in stride(from: 25, through: 75, by: 5) {
      fontSizePicker.addItem(withTitle: "\(i)")
    }
    fontSizePicker.size(width: 60)
    fontSizePicker.target = self
    fontSizePicker.action = #selector(chooseSubFontSizeAction)

    self.borderSizePicker = NSPopUpButton()
    borderSizePicker.addItems(withTitles: [
      "0", "0.25", "0.5", "1", "1.5", "2", "2.5", "3", "4", "5"
    ])
    borderSizePicker.size(width: 60)
    borderSizePicker.target = self
    borderSizePicker.action = #selector(chooseSubBorderSizeAction)

    let scaleStack = ui.hStack(
      spacing: 8,
      ui.image("plus.magnifyingglass", size: 16, config: .sidebarIconConfig),
      ui.label("sidebar.scale", font: .boldSystemFont(ofSize: 12)),
      scaleSlider,
      scaleResetButton,
    )
    scaleStack.size(height: 30)

    let stack = ui.vStack(
      spacing: .sidebarItemSpacing,
      scaleStack,
      ui.hStack(
        spacing: 8,
        ui.image("textformat", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.font", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        fontChooser,
        fontSizePicker,
      ),
      ui.hStack(
        spacing: 8,
        ui.image("paintpalette.fill", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.color", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        createColorWell(\.textColorWell, tag: 1),
      ),
      ui.hStack(
        spacing: 8,
        ui.image("inset.filled.rectangle", "rectangle.inset.filled", "rectangle.inset.fill",
                 size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.background", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        createColorWell(\.backgroundColorWell, tag: 2),
      ),
      ui.hStack(
        spacing: 8,
        ui.image("paintpalette.fill", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.border", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        borderSizePicker,
        createColorWell(\.borderColorWell, tag: 3),
      )
    )

    addSubview(stack)
    stack.padding(.all)

    updateScale()
    updateTextStyle()
    player.observe(.iinaSubScaleChanged) { [unowned self] _ in
      updateScale()
    }
  }

  private func createColorWell(_ keyPath: ReferenceWritableKeyPath<SubStyleView, NSColorWell?>, tag: Int) -> NSColorWell {
    let colorWell = if #available(macOS 13.0, *) {
      NSColorWell()
    } else {
      RoundedColorWell()
    }
    colorWell.tag = tag
    colorWell.translatesAutoresizingMaskIntoConstraints = false
    if #available(macOS 13.0, *) {
      colorWell.colorWellStyle = .expanded
    } else {
      colorWell.size(width: 24)
    }
    colorWell.size(height: 24)
    colorWell.target = self
    colorWell.action = #selector(colorAction)
    self[keyPath: keyPath] = colorWell
    return colorWell
  }

  private func updateScale() {
    let subFont = player.mpv.getString(MPVOption.Subtitles.subFont) ??
      NSLocalizedString("sidebar.font", comment: "");
    fontChooser.title = subFont

    let currSubScale = player.mpv.getDouble(MPVOption.Subtitles.subScale).clamped(to: 0.1...10)
    let displaySubScale = Utility.toDisplaySubScale(fromRealSubScale: currSubScale)
    scaleSlider.doubleValue = displaySubScale + (displaySubScale > 0 ? -1 : 1)
  }

  private func updateTextStyle() {
    let fontSize = player.mpv.getInt(MPVOption.Subtitles.subFontSize)
    fontSizePicker.selectItem(withTitle: fontSize.description)

    let borderWidth = player.mpv.getDouble(MPVOption.Subtitles.subBorderSize)
    borderSizePicker.selectItem(at: -1)
    borderSizePicker.itemArray.forEach { item in
      if borderWidth == Double(item.title) {
        borderSizePicker.select(item)
      }
    }

    for (op, colorWell) in [
      (MPVOption.Subtitles.subColor, textColorWell),
      (MPVOption.Subtitles.subBorderColor, borderColorWell),
      (MPVOption.Subtitles.subBackColor, backgroundColorWell),
    ] {
      if let colorString = player.mpv.getString(op), let color = NSColor(mpvColorString: colorString) {
        colorWell?.color = color
      }
    }
  }

  @objc private func scaleResetButtonAction(_ sender: AnyObject) {
    player.setSubScale(1)
    scaleSlider.doubleValue = 0
  }

  @objc private func scaleAction(_ sender: AnyObject) {
    let value = scaleSlider.doubleValue
    let mappedValue: Double, realValue: Double
    // map [-10, -1], [1, 10] to [-9, 9], bounds may change in future
    if value > 0 {
      mappedValue = round((value + 1) * 20) / 20
      realValue = mappedValue
    } else {
      mappedValue = round((value - 1) * 20) / 20
      realValue = 1 / mappedValue
    }
    player.setSubScale(realValue)
  }

  @objc func chooseSubFontAction(_ sender: AnyObject) {
    player.chooseSubFont()
  }

  @objc func chooseSubFontSizeAction(_ sender: AnyObject) {
    guard let title = fontSizePicker.selectedItem?.title, let value = Double(title) else { return }
    player.setSubTextSize(value)
  }

  @objc func chooseSubBorderSizeAction(_ sender: AnyObject) {
    guard let title = borderSizePicker.selectedItem?.title, let value = Double(title) else { return }
    player.setSubTextBorderSize(value)
  }

  @objc func colorAction(_ sender: NSColorWell) {
    let color = sender.color.mpvColorString
    switch sender.tag {
    case 1: player.setSubTextColor(color)
    case 2: player.setSubTextBgColor(color)
    case 3: player.setSubTextBorderColor(color)
    default: break
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
