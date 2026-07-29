//
//  SidebarVideoPane.swift
//  iina
//
//  Created by Hechen Li on 2026-06-14.
//  Copyright © 2026 lhc. All rights reserved.
//


fileprivate let ui = UIHelper.shared


class SidebarVideoPane: SidebarScrollView {
  let prefObserver = Preference.Observer()
  weak var player: PlayerCore!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    drawsBackground = false

    let stack = ui.vStack(spacing: .sidebarStackViewSpacing)

    stack.addArrangedSubview(Container(TrackSelector(
      .video,
      player: player,
      observedKeys: [.iinaVIDChanged]
    )) {
      $0.padding(.horizontal, .vertical)
    })

    stack.addArrangedSubview(Container(createSettingsView()) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    stack.addArrangedSubview(Container(SpeedView(player: player)) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    stack.addArrangedSubview(Container(createSwitchesView()) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    stack.addArrangedSubview(Container(EqualizerView(player: player)) {
      $0.padding(.all(.sidebarContainerPadding))
    })

    documentView!.addSubview(stack)
    stack.padding(.horizontal(.sidebarMargin), .top(4), .bottom(.sidebarMargin))
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func createSettingsView() -> NSView {
    let container = NSView()
    container.setContentHuggingPriority(.init(100), for: .horizontal)
    container.translatesAutoresizingMaskIntoConstraints = false

    let stack = ui.vStack(
      align: .leading,
      spacing: .sidebarItemSpacing,
      wantsToGrow: true,
      ui.hStack(
        align: .centerY,
        ui.image("aspectratio", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.aspect_ratio", font: .boldSystemFont(ofSize: 12))
      ),
      AspectRatioView(player: player),
      ui.hStack(
        align: .centerY,
        ui.image("crop", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.crop", font: .boldSystemFont(ofSize: 12))
      ),
      CropView(player: player),
      ui.hStack(
        align: .centerY,
        ui.image("rotate.left", size: 16, config: .sidebarIconConfig),
        ui.label("sidebar.rotation", font: .boldSystemFont(ofSize: 12))
      ),
      RotationView(player: player),
    )

    container.addSubview(stack)
    stack.padding(.all)
    return container
  }

  private func createSwitchesView() -> NSView {
    let container = NSView()
    container.setContentHuggingPriority(.init(100), for: .horizontal)
    container.translatesAutoresizingMaskIntoConstraints = false

    let hdrSwitch = NSSwitch()
    if #available(macOS 26, *) {
      hdrSwitch.controlSize = .small
    }
    hdrSwitch.target = self
    hdrSwitch.action = #selector(hdrAction(_:))

    let hdrRow = ui.hStack(
      spacing: 8,
      ui.image("sun.max", size: 16, config: .sidebarIconConfig),
      ui.label("quicksetting.hdr"),
      ui.flexibleSpace(),
      hdrSwitch
    )

    let updateHDR = { [unowned self, weak hdrRow, weak hdrSwitch] in
      let available = self.player.info.hdrAvailable
      hdrRow?.isHidden = !available
      if available {
        hdrSwitch?.state = self.player.info.hdrEnabled ? .on : .off
      }
    }
    updateHDR()
    player.observe(.iinaHDRChanged) { _ in updateHDR() }

    let stack = ui.vStack(
      align: .leading,
      spacing: .sidebarItemSpacing,
      wantsToGrow: true,
      ui.hStack(
        spacing: 8,
        ui.image("cpu", size: 16, config: .sidebarIconConfig),
        ui.label("quicksetting.hwdec"),
        ui.flexibleSpace(),
        HwdecSwitch(player: player),
      ),
      hdrRow
    )

    container.addSubview(stack)
    stack.padding(.all)
    return container
  }

  @objc private func hdrAction(_ sender: NSSwitch) {
    self.player.info.hdrEnabled = sender.state == .on
    self.player.refreshEdrMode()
  }
}

fileprivate class HorizontalScrollViewWithIndicator: NSView {
  enum IndicatorDirection {
    case leading, trailing, hidden
  }

  let scrollView = ScrollView()
  private var indicator: NSButton!
  private var indicatorDirection: IndicatorDirection = .trailing {
    didSet {
      switch indicatorDirection {
      case .hidden:
        indicator.isHidden = true
      case .leading:
        indicator.isHidden = false
        indicator.image = .sf("chevron.backward")
      case .trailing:
        indicator.isHidden = false
        indicator.image = .sf("chevron.forward")
      }
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    translatesAutoresizingMaskIntoConstraints = false

    scrollView.parent = self
    addSubview(scrollView)

    self.indicator = NSButton(
      image: .sf("chevron.forward")!,
      target: self,
      action: #selector(indicatorAction)
    )
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.bezelStyle = .smallSquare
    indicator.isBordered = false
    addSubview(indicator)
    indicator.size(width: 8).padding(.trailing).center(.y)
    scrollView.padding(.vertical, .leading).spacing(.trailing(4), to: indicator)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func indicatorAction(_ sender: NSButton) {
    guard let width = scrollView.documentView?.frame.width else { return }

    let point = if indicatorDirection == .trailing {
      NSPoint(x: width - scrollView.contentSize.width, y: 0)
    } else {
      NSPoint(x: 0, y: 0)
    }
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.3
      scrollView.contentView.animator().setBoundsOrigin(point)
    })
  }

  class ScrollView: NSScrollView {
    var parent: HorizontalScrollViewWithIndicator!

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)

      translatesAutoresizingMaskIntoConstraints = false
      drawsBackground = false
      hasVerticalScroller = false
      hasHorizontalScroller = false
      verticalScrollElasticity = .none

      contentView.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(updateMask),
        name: NSView.boundsDidChangeNotification,
        object: contentView
      )
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
      super.layout()
      updateMask()
    }

    @objc private func updateMask(_ notification: Notification? = nil) {
      guard let documentView else { return }

      let visibleWidth = contentView.bounds.width
      let contentWidth = documentView.frame.width
      let originX      = contentView.bounds.origin.x

      guard contentWidth > visibleWidth else {
        parent.indicatorDirection = .hidden
        return
      }

      let eps: CGFloat = 1
      let hasTrailing  = originX <= eps
      let hasLeading = originX + visibleWidth >= contentWidth - eps

      parent.indicatorDirection = hasLeading ? .leading : hasTrailing ? .trailing : .hidden
    }

    /// Translate vertical scrolling events to horizontal for mouse control
    override func scrollWheel(with event: NSEvent) {
      if event.scrollingDeltaX != 0 {
        super.scrollWheel(with: event)
        return
      }

      guard let cg = event.cgEvent?.copy() else {
        super.scrollWheel(with: event)
        return
      }

      let lineV = cg.getDoubleValueField(.scrollWheelEventDeltaAxis1)
      cg.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)
      cg.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: lineV)

      let pxV = cg.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
      cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
      cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pxV)

      let fpV = cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
      cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
      cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fpV)

      guard let swapped = NSEvent(cgEvent: cg) else {
        super.scrollWheel(with: event)
        return
      }

      super.scrollWheel(with: swapped)
    }
  }
}

fileprivate class AspectRatioView: HorizontalScrollViewWithIndicator {
  private unowned let player: PlayerCore
  private var segmentControl: NSSegmentedControl!
  private var input: NSTextField!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    self.segmentControl = NSSegmentedControl(
      labels: AppData.aspectsInPanel,
      trackingMode: .selectOne,
      target: self, action: #selector(aspectRatioAction)
    )
    segmentControl.selectedSegment = 0

    self.input = NSTextField()
    input.usesSingleLineMode = true
    input.size(width: 40, height: 24)
    input.target = self
    input.action = #selector(aspectRatioAction)

    scrollView.documentView = ui.hStack(
      spacing: 8, segmentControl, input
    )
    size(height: 24)

    player.observe(.iinaVideoParamsChanged) { [unowned self] _ in
      update()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func update() {
    guard player.info.state.active else { return }

    if let index = AppData.aspectsInPanel.firstIndex(of: player.info.unsureAspect) {
      segmentControl.selectedSegment = index
    } else {
      segmentControl.selectedSegment = -1
    }
  }

  @objc private func aspectRatioAction(_ sender: AnyObject) {
    if let textField = sender as? NSTextField {
      let value = textField.stringValue
      if value != "" {
        segmentControl.setSelected(false, forSegment: segmentControl.selectedSegment)
        player.setVideoAspect(value)
        player.sendOSD(.aspect(value))
      }
    } else if let segment = sender as? NSSegmentedControl {
      let aspect = AppData.aspectsInPanel[segment.selectedSegment]
      player.setVideoAspect(aspect)
      player.sendOSD(.aspect(aspect))
    }
  }
}


fileprivate class CropView: HorizontalScrollViewWithIndicator {
  private unowned let player: PlayerCore
  private var segmentControl: NSSegmentedControl!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    self.segmentControl = NSSegmentedControl(
      labels: AppData.cropsInPanel + [NSLocalizedString("menu.crop_custom", comment: "")],
      trackingMode: .selectOne,
      target: self, action: #selector(cropAction)
    )
    segmentControl.selectedSegment = 0

    scrollView.documentView = segmentControl
    size(height: 24)

    player.observe(.iinaVideoParamsChanged) { [unowned self] _ in
      update()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func update() {
    guard player.info.state.active else { return }

    if let index = AppData.cropsInPanel.firstIndex(of: player.info.unsureCrop) {
      segmentControl.selectedSegment = index
    } else {
      // Select last segment ("Custom...")
      segmentControl.selectedSegment = segmentControl.segmentCount - 1
    }
  }

  @objc private func cropAction(_ sender: AnyObject) {
    if segmentControl.selectedSegment == segmentControl.segmentCount - 1 {
      guard let mainWindow = player.mainWindow else { return }
      // User clicked on "Custom...": show interactive mode
      // run asynchronically to wait for potential videoview resize
      Task { @MainActor in
        mainWindow.player.removeCropFilter()
        mainWindow.forceDraw("reset crop filter")
        mainWindow.sidebars.hideAllSideBars {
          mainWindow.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
        }
      }
    } else {
      let cropStr = AppData.cropsInPanel[segmentControl.selectedSegment]
      player.setCrop(fromString: cropStr)
      player.sendOSD(.crop(cropStr))
    }
  }
}


fileprivate class RotationView: NSView {
  private unowned let player: PlayerCore
  private var segmentControl: NSSegmentedControl!

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    self.segmentControl = NSSegmentedControl(
      labels: AppData.rotations.map { "\($0)°" },
      trackingMode: .selectOne,
      target: self, action: #selector(rotationAction)
    )
    segmentControl.translatesAutoresizingMaskIntoConstraints = false
    segmentControl.selectedSegment = 0
    for i in 0..<segmentControl.segmentCount {
      segmentControl.setTag(i, forSegment: i)
    }

    addSubview(segmentControl)
    segmentControl.padding(.all)

    player.observe(.iinaVideoParamsChanged) { [unowned self] _ in
      update()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func update() {
    guard player.info.state.active else { return }

    segmentControl.selectSegment(withTag: AppData.rotations.firstIndex(of: player.info.rotation) ?? -1)
  }

  @objc private func rotationAction(_ sender: AnyObject) {
    let value = AppData.rotations[segmentControl.selectedSegment]
    player.setVideoRotate(value)
    player.sendOSD(.rotate(value))
  }
}


fileprivate class HwdecSwitch: NSSwitch {
  private unowned let player: PlayerCore

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    if #available(macOS 26, *) {
      controlSize = .small
    }
    target = self
    action = #selector(hwdecAction)

    update()
    player.observe(.iinaHwdecChanged) { [unowned self] _ in
      update()
    }
  }

  private func update() {
    state = player.info.hwdecEnabled ? .on : .off
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func hwdecAction(_ sender: AnyObject) {
    player.toggleHardwareDecoding(state == .on)
  }
}




fileprivate let speedFormatter: NumberFormatter = {
  let fmt = NumberFormatter()
  fmt.numberStyle = .decimal
  fmt.usesGroupingSeparator = true
  fmt.maximumSignificantDigits = 25  // just make very big
  fmt.minimumFractionDigits = 0
  fmt.maximumFractionDigits = 6  // matches mpv behavior
  fmt.usesSignificantDigits = false
  fmt.roundingMode = .halfDown   // matches mpv behavior
  fmt.minimum = NSNumber(floatLiteral: AppData.mpvMinPlaybackSpeed)
  return fmt
}()


fileprivate class SpeedView: SidebarSliderView {
  override var titleImage: NSImage? {
    .sf("chevron.forward.dotted.chevron.forward", "forward.fill",
        withConfiguration: .sidebarIconConfig)
  }
  override var titleKey: String { "sidebar.speed" }

  override var tickMarkLabels: [String] {
    ["\(0.25.groupedStringUpTo6Decimals)x", "1x", "4x", "16x"]
  }

  override var notificationKey: Notification.Name {
    .iinaSpeedChanged
  }

  override func setup() {
    slider.minValue = 0
    slider.maxValue = 24
    slider.numberOfTickMarks = 25
    if #available(macOS 26, *) {
      slider.neutralValue = 8
    }
    input.formatter = speedFormatter
    resetButton.toolTip = NSLocalizedString("quicksetting.reset_speed", comment: "Reset speed to 1x")
  }

  /// Return the slider value that represents the given playback speed.
  /// - Parameter speed: Playback speed.
  /// - Returns: Appropriate slider value.
  private func convertSpeedToSliderValue(_ speed: Double) -> Double {
    let sliderSteps = 24.0
    return log(speed / AppData.minSpeed) / log(AppData.maxSpeed / AppData.minSpeed) * sliderSteps
  }

  /// Ensure that the given `Double` is a speed which is valid for mpv.
  ///
  /// - This is necessary because libmpv cannot be relied on to report the correct number & will reply
  /// with a property change event which echoes the number which was submitted, even if it is not the
  /// same as the number which mpv is actually using (it will internally round the number to 6 digits
  /// after the decimal but tell us that it used the non-rounded number).
  /// - `NumberFormatter` doesn't provide APIs to validate or correct an `NSNumber`.
  /// But we can get the same effect by converting to a `String` and back again.
  private func constrainSpeed(_ inputSpeed: Double) -> Double {
    let newSpeedString: String = speedFormatter.string(from: inputSpeed as NSNumber) ?? "1"
    return Double(truncating: speedFormatter.number(from: newSpeedString)!)
  }

  private func updateSpeed(to inputSpeed: Double) {
    let newSpeed = constrainSpeed(inputSpeed)
    print("newSpeed: \(newSpeed)")
    slider.doubleValue = convertSpeedToSliderValue(newSpeed)
    input.doubleValue = newSpeed
    resetButton.isHidden = newSpeed == 1.0
    if player.info.playSpeed != newSpeed {
      player.setSpeed(newSpeed)
    }
    updateIndicator()
  }

  override func indicatorLabel() -> String {
    "\(input.stringValue)x"
  }

  override func update() {
    let speed = player.mpv.getDouble(MPVOption.PlaybackControl.speed)
    slider.allowsTickMarkValuesOnly = false
    updateSpeed(to: speed)
  }

  override func sliderAction() {
    // Each step is 64^(1/24)
    //   0       1   ..    7      8      9   ..   24
    // 0.250x 0.297x .. 0.841x 1.000x 1.189x .. 16.00x
    slider.allowsTickMarkValuesOnly = true
    let sliderValue = slider.doubleValue
    // Attempt to round speed to 2 decimal places. If user is using the slider, any more
    // precision than that is just a distraction
    let sliderSteps = 24.0
    let newSpeed = (AppData.minSpeed * pow(AppData.maxSpeed / AppData.minSpeed, sliderValue / sliderSteps)).roundedTo2Decimals()
    updateSpeed(to: newSpeed)
  }

  override func customEditFinishedAction() {
    if input.stringValue.isEmpty {
      input.stringValue = "1"
    }
    slider.allowsTickMarkValuesOnly = false
    /// Unfortunately, the text field has not applied validation/formatting to the number at this point.
    /// We will do that manually via `constrainSpeed`.
    updateSpeed(to: input.doubleValue)
    if let window = input.window {
      window.makeFirstResponder(window.contentView)
    }
  }

  override func resetButtonAction() {
    player.setSpeed(1.0)
  }
}


fileprivate class EqualizerView: NSView {
  private unowned let player: PlayerCore

  private var brightnessSlider: NSSlider!
  private var contrastSlider: NSSlider!
  private var saturationSlider: NSSlider!
  private var gammaSlider: NSSlider!
  private var hueSlider: NSSlider!

  let configs: [(
    labelKey: String,
    keyPath: ReferenceWritableKeyPath<EqualizerView, NSSlider?>,
    type: PlayerCore.VideoEqualizerType,
    tag: Int
  )] = [
    ("brightness", \.brightnessSlider, .brightness, 1),
    ("contrast", \.contrastSlider, .contrast, 2),
    ("saturation", \.saturationSlider, .saturation, 3),
    ("gamma", \.gammaSlider, .gamma, 4),
    ("hue", \.hueSlider, .hue, 5),
  ]

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    let stack = ui.vStack(spacing: .sidebarItemSpacing)

    var firstLabel: NSTextField?

    for c in configs {
      let label = ui.label("sidebar.\(c.labelKey)", isSmall: true, canCompress: false)

      let slider = NSSlider()
      slider.tag = c.tag
      slider.controlSize = .small
      slider.minValue = -100
      slider.maxValue = 100
      slider.setContentHuggingPriority(.init(150), for: .horizontal)
      slider.target = self
      slider.action = #selector(sliderAction)
      if #available(macOS 26, *) {
        slider.neutralValue = 0
      }
      self[keyPath: c.keyPath] = slider

      let resetButton = NSButton(
        image: .sf("arrow.counterclockwise.circle.fill")!,
        target: self, action: #selector(resetAction)
      )
      resetButton.bezelStyle = .smallSquare
      resetButton.isBordered = false
      resetButton.tag = c.tag

      stack.addArrangedSubview(ui.hStack(
        spacing: 8,
        label, slider, resetButton
      ))

      if let firstLabel {
        label.widthAnchor.constraint(equalTo: firstLabel.widthAnchor).isActive = true
      } else {
        firstLabel = label
      }
    }

    addSubview(stack)
    stack.padding(.horizontal(1), .vertical(2))

    player.observe(.iinaVideoEqualizerChanged) { [unowned self] _ in
      update()
    }
  }

  private func update() {
    brightnessSlider.intValue = Int32(player.info.brightness)
    contrastSlider.intValue = Int32(player.info.contrast)
    saturationSlider.intValue = Int32(player.info.saturation)
    gammaSlider.intValue = Int32(player.info.gamma)
    hueSlider.intValue = Int32(player.info.hue)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func resetAction(_ sender: NSButton) {
    let config = configs.first(where: { $0.tag == sender.tag })!
    player.setVideoEqualizer(forOption: config.type, value: 0)
    self[keyPath: config.keyPath]?.intValue = 0
  }

  @objc private func sliderAction(_ sender: NSSlider) {
    let config = configs.first(where: { $0.tag == sender.tag })!
    player.setVideoEqualizer(forOption: config.type, value: Int(sender.intValue))
  }
}
