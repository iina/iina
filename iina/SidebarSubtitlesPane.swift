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

    let primaryTracks = TrackSelector(.sub, player: player, observedKeys: [.iinaSIDChanged])
    let primary = ui.vStack(
      spacing: .sidebarItemSpacing,
      wantsToGrow: true,
      ui.hStack(
        spacing: 8,
        ui.image("1.square.fill", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.primary", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
      ),
      primaryTracks
    )
    stack.addArrangedSubview(primary)
    primary.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    primaryTracks.widthAnchor.constraint(equalTo: primary.widthAnchor).isActive = true

    let secondaryTracks = TrackSelector(.secondSub, player: player, observedKeys: [.iinaSIDChanged])
    let secondary = ui.vStack(
      spacing: .sidebarItemSpacing,
      wantsToGrow: true,
      ui.hStack(
        spacing: 8,
        ui.image("2.square.fill", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.secondary", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
      ),
      secondaryTracks
    )
    stack.addArrangedSubview(secondary)
    secondary.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    secondaryTracks.widthAnchor.constraint(equalTo: secondary.widthAnchor).isActive = true

    let loadSubtitle = Container(LoadSubtitleView(player: player)) {
      $0.padding(.all(.sidebarContainerPadding))
    }
    stack.addArrangedSubview(loadSubtitle)

    let roleSelector = SubtitleRoleSelector()
    stack.addArrangedSubview(roleSelector)
    roleSelector.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    LayoutValue(28, 24).use { [weak stack, weak loadSubtitle] spacing in
      guard let stack, let loadSubtitle else { return }
      stack.setCustomSpacing(spacing, after: loadSubtitle)
    }
    stack.setCustomSpacing(6, after: roleSelector)

    let processing = SubPositionDelayView(player: player)
    stack.addArrangedSubview(processing)
    processing.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

    let style = SubStyleView(player: player)
    let styleReset = SidebarResetButton(target: style, action: #selector(SubStyleView.resetStyle))
    styleReset.resetContextMenu = { [weak style] in
      guard let style else { return NSMenu() }
      let role = NSLocalizedString(style.isPrimary ? "sidebar.primary" : "sidebar.secondary", comment: "Subtitle role")
      let title = String(format: NSLocalizedString("track_settings.reset_output", comment: "Reset selected role"), role)
      return SidebarResetButton.makeContextMenu(currentTitle: title, target: style,
        currentAction: #selector(SubStyleView.resetStyle))
    }
    let textStyleView = TrackSettingsGroupView(titleKey: "sidebar.style", content: style, action: styleReset)
    stack.addArrangedSubview(textStyleView)
    textStyleView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

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

    let engineWarning = Container(ui.label(
      "sidebar.secondary_style_engine_required", wrapping: true, isSmall: true, isSecondary: true)) {
        $0.padding(.all(.sidebarContainerPadding))
      }
    stack.addArrangedSubview(engineWarning)

    documentView!.addSubview(stack)
    stack.padding(.horizontal(.sidebarMargin), .top(4), .bottom(.sidebarMargin))

    let block = { [weak player, weak roleSelector, weak stack,
                   weak textStyleView, weak imageWarning, weak assWarning, weak engineWarning] (_: Notification) in
      guard let player, let roleSelector, let stack,
            let textStyleView, let imageWarning, let assWarning, let engineWarning else { return }
      let track = player.info.currentTrack(roleSelector.isPrimary ? .sub : .secondSub)
      let hasText = track?.isImageSub != true
      let isASS = track?.isAssSub == true

      let supportsStyle = roleSelector.isPrimary || player.mpv.supportsIndependentSecondarySubtitleStyle
      stack.setVisibilityPriority(hasText && supportsStyle ? .mustHold : .notVisible, for: textStyleView)
      stack.setVisibilityPriority(hasText && !supportsStyle ? .mustHold : .notVisible, for: engineWarning)
      stack.setVisibilityPriority(hasText ? .notVisible : .mustHold, for: imageWarning)
      stack.setVisibilityPriority(isASS ? .mustHold : .notVisible, for: assWarning)
    }

    roleSelector.onChange = { primary in
      processing.setPrimary(primary)
      style.setPrimary(primary)
      block(.init(name: .init("")))
    }
    block(.init(name: .init("")))
    player.observe(.iinaSIDChanged, block: block)
    player.observe(.iinaTracklistChanged, block: block)
  }

  @MainActor required init?(coder: NSCoder) {
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
    updateIndicator()
  }

  override func sliderAction() {
    let eventType = NSApp.currentEvent?.type
    if eventType == .leftMouseDown {
      slider.allowsTickMarkValuesOnly = true
    }
    if eventType != .leftMouseDown && eventType != .leftMouseDragged {
      slider.allowsTickMarkValuesOnly = false
    }
    let sliderValue = slider.doubleValue
    input.doubleValue = sliderValue
    updateIndicator()
    if eventType != .leftMouseDown && eventType != .leftMouseDragged {
      player.setSubDelay(sliderValue, forPrimary: isPrimary)
    }
  }

  override func customEditFinishedAction() {
    if input.stringValue.isEmpty {
      input.stringValue = "0"
    }
    let value = input.doubleValue
    player.setSubDelay(value, forPrimary: isPrimary)
    slider.doubleValue = value
  }

  override func resetButtonAction() {
    player.performSidebarChange { player.setSubDelay(0, forPrimary: isPrimary) }
  }
}


fileprivate class SubPositionDelayView: NSView {
  private unowned let player: PlayerCore
  var isPrimary: Bool = true

  private var positionSlider: NSSlider!
  private var delayView: SubDelayView!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

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

    let positionContent = NSView()
    positionContent.translatesAutoresizingMaskIntoConstraints = false
    positionContent.heightAnchor.constraint(equalToConstant: 24).isActive = true
    positionSlider.translatesAutoresizingMaskIntoConstraints = false
    positionContent.addSubview(positionSlider)
    positionSlider.padding(.horizontal).center(.y, with: positionContent)

    let positionHeading = ui.hStack(
      spacing: 8,
      ui.image("arrow.up.and.down", size: 16, config: .sidebarIconConfig),
      ui.label("sidebar.position", font: .boldSystemFont(ofSize: 12)),
      ui.flexibleSpace()
    )
    let adjustments = ui.vStack(spacing: .sidebarItemSpacing, wantsToGrow: true,
                                delayView, positionHeading, positionContent)
    for view in [delayView!, positionHeading, positionContent] {
      view.widthAnchor.constraint(equalTo: adjustments.widthAnchor).isActive = true
    }
    let reset = SidebarResetButton(target: self, action: #selector(resetAdjustments))
    reset.resetContextMenu = { [weak self] in
      guard let self else { return NSMenu() }
      let role = NSLocalizedString(isPrimary ? "sidebar.primary" : "sidebar.secondary", comment: "Subtitle role")
      let title = String(format: NSLocalizedString("track_settings.reset_output", comment: "Reset selected role"), role)
      return SidebarResetButton.makeContextMenu(currentTitle: title, target: self,
        currentAction: #selector(resetAdjustments))
    }
    let section = TrackSettingsGroupView(titleKey: "sidebar.adjustments", content: adjustments, action: reset)
    addSubview(section)
    section.padding(.all)

    update()
    player.observe(.iinaSubPositionChanged) { [unowned self] _ in
      updatePosition()
    }
  }

  func setPrimary(_ primary: Bool) {
    isPrimary = primary
    delayView.isPrimary = primary
    update()
  }

  private func update() {
    updatePosition()
    delayView.update()
  }

  private func updatePosition() {
    let posOption = isPrimary ? MPVOption.Subtitles.subPos : MPVOption.Subtitles.secondarySubPos
    positionSlider.intValue = Int32(player.mpv.getInt(posOption))
  }

  @objc private func resetAdjustments() {
    player.performSidebarChange {
      delayView.resetButtonAction()
      player.setSubPos(isPrimary ? 100 : 0, forPrimary: isPrimary)
    }
    update()
  }

  @objc private func positionAction(_ sender: AnyObject) {
    player.performSidebarChange { player.setSubPos(Int(positionSlider.intValue), forPrimary: isPrimary) }
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


fileprivate class SubStyleView: NSView {
  private unowned let player: PlayerCore
  private(set) var isPrimary = true

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
    )
    scaleStack.size(height: 30)

    let fontStackLabel = ui.label("sidebar.font", font: .boldSystemFont(ofSize: 12))
    fontStackLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    let fontStack = ui.hStack(
      spacing: 8,
      ui.image("textformat", size: 16, config: .sidebarIconConfig),
      fontStackLabel,
      ui.flexibleSpace(),
      fontChooser,
      fontSizePicker,
    )

    let stack = ui.vStack(
      spacing: .sidebarItemSpacing,
      scaleStack,
      fontStack,
      ui.hStack(
        spacing: 8,
        ui.image("paintpalette.fill", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.color", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        createColorWell(\.textColorWell, tag: 1),
      ),
      ui.hStack(
        spacing: 8,
        ui.image("inset.filled.circle.dashed", "circle.dashed.inset.filled", "circle.dashed.inset.fill", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.border", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        borderSizePicker,
        createColorWell(\.borderColorWell, tag: 3),
      ),
      ui.hStack(
        spacing: 8,
        ui.image("shadow", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.shadow", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        createColorWell(\.backgroundColorWell, tag: 2),
      )
    )

    addSubview(stack)
    stack.padding(.all)

    updateScale()
    updateTextStyle()
    player.observe(.iinaSubScaleChanged) { [unowned self] _ in updateScale() }
    player.observe(.iinaSubFontChanged) { [unowned self] _ in updateScale() }
    player.observe(.iinaSubtitleStyleChanged) { [unowned self] _ in
      updateScale()
      updateTextStyle()
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

  func setPrimary(_ primary: Bool) {
    for well in [textColorWell, borderColorWell, backgroundColorWell] { well?.deactivate() }
    isPrimary = primary
    updateScale()
    updateTextStyle()
  }

  private func option(_ name: String) -> String {
    SubtitleStyle.option(name, forPrimary: isPrimary)
  }

  private func updateScale() {
    guard isPrimary || player.mpv.supportsIndependentSecondarySubtitleStyle else { return }
    let subFont = player.mpv.getString(option(MPVOption.Subtitles.subFont)) ??
      NSLocalizedString("sidebar.font", comment: "");
    fontChooser.title = subFont

    let currSubScale = player.mpv.getDouble(option(MPVOption.Subtitles.subScale)).clamped(to: 0.1...10)
    let displaySubScale = Utility.toDisplaySubScale(fromRealSubScale: currSubScale)
    scaleSlider.doubleValue = displaySubScale + (displaySubScale > 0 ? -1 : 1)
  }

  private func updateTextStyle() {
    guard isPrimary || player.mpv.supportsIndependentSecondarySubtitleStyle else { return }
    selectSubtitleStyleValue(player.mpv.getDouble(option(MPVOption.Subtitles.subFontSize)), in: fontSizePicker)
    selectSubtitleStyleValue(player.mpv.getDouble(option(MPVOption.Subtitles.subOutlineSize)), in: borderSizePicker)

    for (op, colorWell) in [
      (MPVOption.Subtitles.subColor, textColorWell),
      (MPVOption.Subtitles.subOutlineColor, borderColorWell),
      (MPVOption.Subtitles.subBackColor, backgroundColorWell),
    ] {
      if let colorString = player.mpv.getString(option(op)), let color = NSColor(mpvColorString: colorString) {
        colorWell?.color = color
      }
    }
  }

  @objc func resetStyle() {
    player.performSidebarChange { player.resetSubtitleStyle(forPrimary: isPrimary) }
    updateScale()
    updateTextStyle()
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
    player.performSidebarChange { player.setSubScale(realValue, forPrimary: isPrimary) }
  }

  @objc func chooseSubFontAction(_ sender: AnyObject) {
    player.performSidebarChange { player.chooseSubFont(forPrimary: isPrimary) }
  }

  @objc func chooseSubFontSizeAction(_ sender: AnyObject) {
    guard let title = fontSizePicker.selectedItem?.title, let value = Double(title) else { return }
    player.performSidebarChange { player.setSubTextSize(value, forPrimary: isPrimary) }
  }

  @objc func chooseSubBorderSizeAction(_ sender: AnyObject) {
    guard let title = borderSizePicker.selectedItem?.title, let value = Double(title) else { return }
    player.performSidebarChange { player.setSubTextBorderSize(value, forPrimary: isPrimary) }
  }

  @objc func colorAction(_ sender: NSColorWell) {
    let color = sender.color.mpvColorString
    player.performSidebarChange {
      switch sender.tag {
      case 1: player.setSubTextColor(color, forPrimary: isPrimary)
      case 2: player.setSubTextBgColor(color, forPrimary: isPrimary)
      case 3: player.setSubTextBorderColor(color, forPrimary: isPrimary)
      default: break
      }
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// Add saved values absent from the preset menu rather than showing a different value.
fileprivate func selectSubtitleStyleValue(_ value: Double, in picker: NSPopUpButton) {
  guard value.isFinite else { return }
  for item in picker.itemArray where item.tag == -1 {
    picker.menu?.removeItem(item)
  }
  if let item = picker.itemArray.first(where: { Double($0.title) == value }) {
    picker.select(item)
  } else {
    let title = NSNumber(value: value).stringValue
    let index = picker.itemArray.firstIndex { (Double($0.title) ?? .infinity) > value } ?? picker.numberOfItems
    picker.insertItem(withTitle: title, at: index)
    picker.item(at: index)?.tag = -1
    picker.selectItem(at: index)
  }
}
