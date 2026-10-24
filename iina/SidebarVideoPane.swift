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

    let tracks = TrackSelector(
      .video,
      player: player,
      observedKeys: [.iinaVIDChanged]
    )
    let addTrack = TrackAddButton(title: ui.localized("sidebar.add_video_track"),
                                  target: self, action: #selector(loadExternalVideoAction(_:)))
    let trackGroup = ui.vStack(spacing: 6, wantsToGrow: true, addTrack, tracks)
    stack.addArrangedSubview(trackGroup)
    trackGroup.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    addTrack.widthAnchor.constraint(equalTo: trackGroup.widthAnchor).isActive = true
    tracks.widthAnchor.constraint(equalTo: trackGroup.widthAnchor).isActive = true

    let processing = TrackProcessingSection(player: player, group: .videoGeometry, cards: [
      TrackSettingsGroupView(player: player, group: .videoGeometry, content: createSettingsView()),
      TrackSettingsGroupView(player: player, group: .videoColor, content: EqualizerView(player: player))
    ])
    stack.addArrangedSubview(processing)
    processing.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

    let speed = SpeedView(player: player)
    let speedReset = SidebarResetButton(target: speed, action: #selector(SpeedView.resetSpeed))
    speedReset.toolTip = ui.localized("quicksetting.reset_speed")
    let speedGroup = TrackSettingsGroupView(titleKey: "sidebar.speed", content: speed,
                                            titleImage: speed.titleImage, action: speedReset)
    let switches = createSwitchesView()
    for view in [speedGroup, switches] {
      stack.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    documentView!.addSubview(stack)
    stack.padding(.horizontal(.sidebarMargin), .top(4), .bottom(.sidebarMargin))
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func loadExternalVideoAction(_ sender: NSButton) {
    Utility.quickOpenPanel(
      title: ui.localized("sidebar.add_video_track"),
      chooseDir: false,
      dir: player.info.currentURL?.deletingLastPathComponent(),
      sheetWindow: player.currentWindow,
      allowedFileTypes: Utility.supportedFileExt[.video]
    ) { url in
      self.player.loadExternalVideoFile(url)
    }
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
    let hdrSwitch = NSSwitch()
    if #available(macOS 26, *) {
      hdrSwitch.controlSize = .small
    }
    hdrSwitch.target = self
    hdrSwitch.action = #selector(hdrAction(_:))

    let hdrRow = ui.hStack(
      spacing: 8,
      ui.image("sun.max", size: 16, config: .sidebarIconConfig),
      ui.label("quicksetting.hdr", font: .boldSystemFont(ofSize: 12)),
      ui.flexibleSpace(),
      hdrSwitch
    )

    let hdr = Container(hdrRow) { $0.padding(.all(.sidebarContainerPadding)) }
    let updateHDR = { [unowned self, weak hdr, weak hdrSwitch] in
      let available = self.player.info.hdrAvailable
      hdr?.isHidden = !available
      if available {
        hdrSwitch?.state = self.player.info.hdrEnabled ? .on : .off
      }
    }
    updateHDR()
    player.observe(.iinaHDRChanged) { _ in updateHDR() }

    let hardwareRow = ui.hStack(
        spacing: 8,
        ui.image("cpu", size: 16, config: .sidebarIconConfig),
        ui.label("quicksetting.hwdec", font: .boldSystemFont(ofSize: 12)),
        ui.flexibleSpace(),
        HwdecSwitch(player: player),
    )
    let hardware = Container(hardwareRow) { $0.padding(.all(.sidebarContainerPadding)) }
    let stack = ui.vStack(spacing: .sidebarItemSpacing, wantsToGrow: true, hardware, hdr)
    for card in [hardware, hdr] {
      card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    return stack
  }

  @objc private func hdrAction(_ sender: NSSwitch) {
    player.performSidebarChange {
      player.info.hdrEnabled = sender.state == .on
      player.refreshEdrMode()
    }
  }
}

fileprivate class HorizontalScrollViewWithIndicator: NSView {
  enum IndicatorDirection {
    case leading, trailing, hidden
  }

  let scrollView = ScrollView()
  private let focusRingPadding: CGFloat = 4
  private var indicator: NSButton!
  private var indicatorDirection: IndicatorDirection = .trailing {
    didSet {
      guard indicatorDirection != oldValue else { return }
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
    // Native focus rings extend beyond control frames; keep viewport padding outside row geometry.
    clipsToBounds = false

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
    scrollView.padding(.vertical(-focusRingPadding), .leading)
      .spacing(.trailing(4), to: indicator)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setDocumentContent(_ content: NSStackView) {
    // Both rows need identical focus-ring insets at either scroll limit.
    content.edgeInsets = NSEdgeInsets(top: focusRingPadding, left: 0,
                                     bottom: focusRingPadding, right: focusRingPadding)
    scrollView.documentView = content
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
    private var forwardsVerticalScroll = false

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

    override func scrollWheel(with event: NSEvent) {
      if event.phase.contains(.began) { forwardsVerticalScroll = false }
      if event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
        forwardsVerticalScroll = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
      }
      if forwardsVerticalScroll {
        var ancestor = superview
        while let view = ancestor {
          if let scroll = view as? NSScrollView {
            scroll.scrollWheel(with: event)
            return
          }
          ancestor = view.superview
        }
      }
      super.scrollWheel(with: event)
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
      labels: [ui.localized("quicksetting.item_default")] + AppData.aspectsInPanel.dropFirst(1),
      trackingMode: .selectOne,
      target: self, action: #selector(aspectRatioAction)
    )
    segmentControl.selectedSegment = 0

    let input = SidebarInputField()
    input.emptyValue = ""
    self.input = input
    input.size(width: 40, height: 24)
    input.target = self
    input.action = #selector(aspectRatioAction)

    setDocumentContent(ui.hStack(
      spacing: 8, segmentControl, input
    ))
    size(height: 24)

    update()
    player.observe(.iinaTrackSettingsChanged) { [unowned self] _ in update() }
    player.observe(.iinaVideoParamsChanged) { [unowned self] _ in
      update()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func update() {
    guard player.info.state.active else { return }
    segmentControl.isEnabled = !player.mainWindow.interactiveMode.isActive
    input.isEnabled = segmentControl.isEnabled

    if let index = AppData.aspectsInPanel.firstIndex(of: player.scopedVideoSettings().aspect) {
      segmentControl.selectedSegment = index
    } else {
      segmentControl.selectedSegment = -1
    }
  }

  @objc private func aspectRatioAction(_ sender: AnyObject) {
    if let textField = sender as? NSTextField {
      let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let aspect = value.isEmpty ? AppData.aspectsInPanel[0] : value
      segmentControl.selectedSegment = value.isEmpty ? 0 : -1
      player.performSidebarChange {
        player.setScopedVideoAspect(aspect)
        player.sendOSD(.aspect(aspect))
      }
    } else if let segment = sender as? NSSegmentedControl {
      let aspect = AppData.aspectsInPanel[segment.selectedSegment]
      player.performSidebarChange {
        player.setScopedVideoAspect(aspect)
        player.sendOSD(.aspect(aspect))
      }
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
      labels: [ui.localized("quicksetting.item_none")] + AppData.cropsInPanel.dropFirst(1) + [ui.localized("menu.crop_custom")],
      trackingMode: .selectOne,
      target: self, action: #selector(cropAction)
    )
    segmentControl.selectedSegment = 0

    setDocumentContent(ui.hStack(spacing: 0, segmentControl))
    size(height: 24)

    update()
    player.observe(.iinaTrackSettingsChanged) { [unowned self] _ in update() }
    player.observe(.iinaVideoParamsChanged) { [unowned self] _ in
      update()
    }
    update()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func update() {
    guard player.info.state.active else { return }
    segmentControl.isEnabled = !player.mainWindow.interactiveMode.isActive

    if let index = AppData.cropsInPanel.firstIndex(of: player.scopedVideoSettings().cropDescription) {
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
        mainWindow.sidebars.hideAllSideBars {
          self.player.openScopedCustomCrop()
        }
      }
    } else {
      let cropStr = AppData.cropsInPanel[segmentControl.selectedSegment]
      player.performSidebarChange {
        player.setScopedCrop(cropStr)
        player.sendOSD(.crop(cropStr))
      }
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

    update()
    player.observe(.iinaTrackSettingsChanged) { [unowned self] _ in update() }
    player.observe(.iinaVideoParamsChanged) { [unowned self] _ in
      update()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func update() {
    guard player.info.state.active else { return }

    segmentControl.isEnabled = !player.mainWindow.interactiveMode.isActive
    segmentControl.selectSegment(withTag: AppData.rotations.firstIndex(of: player.scopedVideoSettings().rotation) ?? -1)
  }

  @objc private func rotationAction(_ sender: AnyObject) {
    let value = AppData.rotations[segmentControl.selectedSegment]
    player.performSidebarChange {
      player.setScopedVideoRotate(value)
      player.sendOSD(.rotate(value))
    }
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
    player.performSidebarChange { player.toggleHardwareDecoding(state == .on) }
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
  override var showsTitle: Bool { false }
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
    input.emptyValue = "1"
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
    slider.doubleValue = convertSpeedToSliderValue(newSpeed)
    input.doubleValue = newSpeed
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
  }

  override func resetButtonAction() {
    player.setSpeed(1.0)
  }

  @objc func resetSpeed() { player.performSidebarChange { resetButtonAction() } }
}


final class VideoLUTPopUp: NSPopUpButton, NSMenuDelegate {
  static let importQueue = DispatchQueue(label: "IINAVideoLUTImport", qos: .userInitiated)
  private unowned let player: PlayerCore
  private let library: VideoLUTLibrary
  private var libraryObserver: NSObjectProtocol?
  private var presentingLUTMenu = false
  private var choiceRevision = 0
  private var libraryEntries: [VideoLUTLibrary.Entry] = []
  private var libraryNeedsRefresh = true
  private var displayedPaths: [String]?

  init(player: PlayerCore) {
    self.player = player
    library = VideoLUTLibrary(directory: Utility.appSupportDirUrl.appendingPathComponent("LUTs", isDirectory: true))
    super.init(frame: .zero, pullsDown: false)
    translatesAutoresizingMaskIntoConstraints = false
    controlSize = .small
    font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    setContentCompressionResistancePriority(.init(100), for: .horizontal)
    widthAnchor.constraint(lessThanOrEqualToConstant: 145).isActive = true
    (cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingMiddle
    target = self
    action = #selector(selectionChanged)
    menu?.delegate = self
    setAccessibilityLabel("LUT")
    libraryObserver = NotificationCenter.default.addObserver(forName: .iinaLUTLibraryChanged, object: nil, queue: .main) { [weak self] _ in self?.rebuild(refreshLibrary: true) }
    player.observe(.iinaTrackSettingsChanged) { [weak self] _ in self?.rebuild() }
    player.observe(.iinaVFChanged) { [weak self] _ in self?.rebuild() }
    rebuild()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { if let libraryObserver { NotificationCenter.default.removeObserver(libraryObserver) } }

  func menuNeedsUpdate(_ menu: NSMenu) { if !presentingLUTMenu { rebuild(refreshLibrary: true) } }

  override func mouseDown(with event: NSEvent) { presentLUTMenu() }
  override func performClick(_ sender: Any?) { presentLUTMenu() }
  override func accessibilityPerformPress() -> Bool { presentLUTMenu(); return true }
  override func keyDown(with event: NSEvent) {
    if [" ", "\r", "\u{03}", "\u{f700}", "\u{f701}"].contains(event.charactersIgnoringModifiers ?? "") {
      presentLUTMenu()
    } else { super.keyDown(with: event) }
  }

  private func presentLUTMenu() {
    guard isEnabled, !presentingLUTMenu, !player.mainWindow.interactiveMode.isActive else { return }
    rebuild(refreshLibrary: true)
    presentingLUTMenu = true
    defer { presentingLUTMenu = false; rebuild(refreshLibrary: true) }
    guard let menu, let neutral = itemArray.first(where: { $0.tag == 0 && !$0.isSeparatorItem }) else { return }
    let rect = cell?.titleRect(forBounds: bounds) ?? bounds
    var ancestor = superview
    while let view = ancestor, !(view is TrackSettingsGroupView) { ancestor = view.superview }
    let anchor = (ancestor as? TrackSettingsGroupView)?.menuAnchor ?? self
    menu.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
    let right = convert(anchor.bounds, from: anchor).maxX
    let x = userInterfaceLayoutDirection == .rightToLeft ? right : right - menu.size.width
    menu.popUp(positioning: neutral, at: NSPoint(x: x, y: rect.minY), in: self)
  }

  @objc private func menuItemChosen(_ sender: NSMenuItem) {
    select(sender)
    selectionChanged()
  }

  private func rebuild(refreshLibrary: Bool = false) {
    if refreshLibrary { libraryNeedsRefresh = true }
    guard !presentingLUTMenu else { return }
    if libraryNeedsRefresh {
      libraryEntries = (try? library.entries()) ?? []
      libraryNeedsRefresh = false
    }
    let entries = libraryEntries
    let path = selectedLUTPath(entries: entries)
    let managedPaths = entries.map { $0.url.path }
    let missingPath = path.flatMap { managedPaths.contains($0) ? nil : $0 }
    let paths = managedPaths + (missingPath.map { [$0] } ?? [])
    // Slider updates must not rescan/rebuild the menu; Finder changes are discovered when it opens.
    if displayedPaths != paths {
      displayedPaths = paths
      removeAllItems()
      addItem(withTitle: NSLocalizedString("lut.remove", comment: "Delete LUT"))
      lastItem?.tag = -2
      addItem(withTitle: NSLocalizedString("lut.import", comment: "Import LUT"))
      lastItem?.tag = -1
      menu?.addItem(.separator())
      lastItem?.tag = -1000
      addItem(withTitle: NSLocalizedString("lut.none", comment: "No LUT"))
      lastItem?.tag = 0
      if !paths.isEmpty { menu?.addItem(.separator()); lastItem?.tag = -1000 }
      for entryPath in paths {
        addItem(withTitle: URL(fileURLWithPath: entryPath).deletingPathExtension().lastPathComponent)
        lastItem?.representedObject = entryPath
        lastItem?.tag = 1
      }
      for item in itemArray where !item.isSeparatorItem {
        item.target = self
        item.action = #selector(menuItemChosen(_:))
      }
      menu?.autoenablesItems = false
    }
    let removalItem = itemArray.first { $0.tag == -2 }
    removalItem?.representedObject = path
    removalItem?.isEnabled = managedPaths.contains { $0 == path }
    let selection = itemArray.first(where: { ($0.representedObject as? String) == path && $0.tag >= 0 && !$0.isSeparatorItem })
    if selectedItem !== selection { select(selection) }
    for item in itemArray {
      let state: NSControl.StateValue = item === selectedItem ? .on : .off
      if item.state != state { item.state = state }
    }
    isEnabled = !player.mainWindow.interactiveMode.isActive
    toolTip = titleOfSelectedItem
  }

  private func selectedLUTPath(entries: [VideoLUTLibrary.Entry]) -> String? {
    guard let value = currentLUTValue() else { return nil }
    if player.scopedTrackSettings.target(.videoColor) > 0 { return value }
    return entries.first(where: { $0.graph == value })?.url.path
  }

  private func currentLUTValue() -> String? {
    guard player.info.state.active else { return nil }
    let id = player.scopedTrackSettings.target(.videoColor)
    if id > 0 { return player.scopedTrackSettings.video[id]?.lutPath }
    return player.mpv.getFilters(MPVProperty.vf)
      .first(where: { $0.label == VideoLUTLibrary.filterLabel })?.params?["graph"]
  }

  @objc private func selectionChanged() {
    choiceRevision += 1
    let command = selectedTag()
    let path = selectedItem?.representedObject as? String
    if command == -1 {
      rebuild()
      // Present the sheet after native menu tracking has finished.
      DispatchQueue.main.async { [weak self] in self?.importLUT() }
    } else if command == -2 {
      rebuild()
      DispatchQueue.main.async { [weak self] in self?.removeLUT(path) }
    } else {
      apply(path)
      rebuild()
    }
  }

  private func removeLUT(_ path: String?) {
    guard let path, let entry = (try? library.entries())?.first(where: { $0.url.path == path }) else { return }
    Utility.quickAskPanel("lut_remove", titleArgs: [entry.name], sheetWindow: window) { [weak self] response in
      guard let self, response == .alertFirstButtonReturn else { return }
      VideoLUTLibraryActions.remove(entry, library: self.library, window: self.window)
      self.rebuild()
    }
  }

  private func importLUT() {
    let media = player.info.currentURL
    let generation = player.info.trackSelectionGeneration
    let target = player.scopedTrackSettings.target(.videoColor)
    let revision = choiceRevision
    let previousValue = currentLUTValue()
    Utility.quickOpenPanel(title: NSLocalizedString("lut.import", comment: "Import LUT"), chooseDir: false,
                          sheetWindow: window, allowedFileTypes: ["cube"]) { [weak self] url in
      guard let self, let mainWindow = self.player.mainWindow, self.player.info.currentURL == media,
            self.player.info.trackSelectionGeneration == generation else { return }
      let feedback = mainWindow.beginOperationFeedback()
      Self.importQueue.async { [weak self] in
        let prepared = autoreleasepool { Result { try VideoLUTLibrary.prepareImport(url) } }
        DispatchQueue.main.async { [weak self] in
          mainWindow.endOperationFeedback(feedback)
          guard let self else { return }
          let sameMedia = {
            self.player.info.currentURL == media
              && self.player.info.trackSelectionGeneration == generation && self.player.info.state.loaded
          }
          do {
            // Commit library/player changes on main so removal in another window cannot race this import.
            let entry = try self.library.importPreparedFile(prepared.get())
            if sameMedia(), self.choiceRevision == revision,
               self.player.scopedTrackSettings.target(.videoColor) == target,
               self.currentLUTValue() == previousValue {
              self.apply(entry.url.path)
            }
          } catch {
            if sameMedia(), self.choiceRevision == revision {
              Utility.showAlert("lut_import_failed", arguments: [error.localizedDescription], sheetWindow: self.window)
            }
          }
          self.rebuild()
        }
      }
    }
  }

  private func apply(_ path: String?) {
    guard !player.mainWindow.interactiveMode.isActive else { return }
    if let path, !FileManager.default.isReadableFile(atPath: path) {
      Utility.showAlert("lut_apply_failed", sheetWindow: window)
      return
    }
    if player.scopedTrackSettings.target(.videoColor) > 0 {
      player.performSidebarChange {
        _ = player.updateScopedVideo(.videoColor) { $0.lutPath = path }
      }
      return
    }
    let existing = player.mpv.getFilters(MPVProperty.vf).first(where: { $0.label == VideoLUTLibrary.filterLabel })
    let success: Bool
    if let path {
      let graph = ProcessedVideoGraph.lutFilter(path: path)
      if existing?.params?["graph"] == graph { return }
      let previous = player.mpv.getString(MPVProperty.vf) ?? ""
      // mpv measures fixed-length quoting in UTF-8 bytes, including filenames.
      let filter = MPVFilter(name: "lavfi", label: VideoLUTLibrary.filterLabel,
                            paramString: "graph=%\(graph.utf8.count)%\(graph)")
      success = player.performSidebarChange {
        let applied = player.addVideoFilter(filter)
        if !applied { player.mpv.setString(MPVProperty.vf, previous) }
        return applied
      }
    } else {
      success = existing == nil || player.performSidebarChange {
        player.removeVideoFilter("@" + VideoLUTLibrary.filterLabel)
      }
    }
    if !success { Utility.showAlert("lut_apply_failed", sheetWindow: window) }
  }
}

enum VideoLUTLibraryActions {
  @discardableResult static func remove(_ entry: VideoLUTLibrary.Entry, library: VideoLUTLibrary, window: NSWindow?) -> Bool {
    // Detach transactionally across players; engine or Trash failures must restore every captured user.
    let users = PlayerCore.playerCores.filter { core in
      core.mpv != nil && core.info.state.rawValue < PlayerState.shuttingDown.rawValue && (core.scopedTrackSettings.video.values.contains { $0.lutPath == entry.url.path }
        || core.scopedCropPreview?.originalTrack.lutPath == entry.url.path
        || core.scopedCropPreview?.masterVF.contains(VideoLUTLibrary.filterLabel) == true
        || core.mpv.getFilters(MPVProperty.vf).contains {
          $0.label == VideoLUTLibrary.filterLabel && $0.params?["graph"] == entry.graph
        })
    }
    guard !users.contains(where: { $0.mainWindow.interactiveMode.isActive }) else {
      Utility.showAlert("lut_remove_crop", sheetWindow: window)
      return false
    }
    let snapshots = users.map { (core: $0, settings: $0.scopedTrackSettings, filters: $0.mpv.getString(MPVProperty.vf) ?? "") }
    var restoreSessions: [() -> Void] = []
    do {
      for snapshot in snapshots {
        let core = snapshot.core
        var changed = false
        for id in Array(core.scopedTrackSettings.video.keys) where core.scopedTrackSettings.video[id]?.lutPath == entry.url.path {
          core.scopedTrackSettings.video[id]?.lutPath = nil
          changed = true
        }
        if changed && core.info.state.loaded && !core.performSidebarChange({ core.refreshTrackProcessing(.video) }) {
          throw CocoaError(.userCancelled)
        }
        if core.mpv.getFilters(MPVProperty.vf).contains(where: {
          $0.label == VideoLUTLibrary.filterLabel && $0.params?["graph"] == entry.graph
        }), !core.performSidebarChange({ core.removeVideoFilter("@" + VideoLUTLibrary.filterLabel) }) {
          throw CocoaError(.userCancelled)
        }
      }
      restoreSessions = PlayerCore.playerCores.map { $0.detachSavedVideoLUT(atPath: entry.url.path) }
      try library.remove(entry)
    } catch {
      restoreSessions.forEach { $0() }
      for snapshot in snapshots {
        snapshot.core.scopedTrackSettings = snapshot.settings
        snapshot.core.performSidebarChange {
          if snapshot.core.info.state.loaded { _ = snapshot.core.refreshTrackProcessing(.video) }
          snapshot.core.mpv.setString(MPVProperty.vf, snapshot.filters)
        }
      }
      Utility.showAlert("lut_remove_failed", sheetWindow: window)
      return false
    }
    // The library is shared, including by idle windows and menus on other targets.
    for core in PlayerCore.playerCores { core.postNotification(.iinaTrackSettingsChanged) }
    return true
  }
}

fileprivate class EqualizerView: NSView {
  private unowned let player: PlayerCore

  private var brightnessSlider: NSSlider!
  private var contrastSlider: NSSlider!
  private var saturationSlider: NSSlider!
  private var gammaSlider: NSSlider!
  private var hueSlider: NSSlider!
  private var valueInputs: [Int: NSTextField] = [:]

  let configs: [(
    labelKey: String,
    symbolName: String,
    keyPath: ReferenceWritableKeyPath<EqualizerView, NSSlider?>,
    type: PlayerCore.VideoEqualizerType,
    tag: Int
  )] = [
    ("brightness", "sun.max", \.brightnessSlider, .brightness, 1),
    ("contrast", "circle.lefthalf.filled", \.contrastSlider, .contrast, 2),
    ("saturation", "drop.fill", \.saturationSlider, .saturation, 3),
    ("gamma", "chart.xyaxis.line", \.gammaSlider, .gamma, 4),
    ("hue", "paintpalette", \.hueSlider, .hue, 5),
  ]

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    let stack = ui.vStack(spacing: .sidebarItemSpacing)
    let lutLabel = ui.label("LUT", font: .boldSystemFont(ofSize: 12), canCompress: false)
    stack.addArrangedSubview(ui.hStack(spacing: 8,
      ui.image("camera.filters", size: 16, config: .sidebarIconConfig),
      lutLabel, ui.flexibleSpace(), VideoLUTPopUp(player: player)))
    var firstLabel: NSTextField?

    for c in configs {
      let label = ui.label("sidebar.\(c.labelKey)", font: .boldSystemFont(ofSize: 12), canCompress: false)

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

      let input = SidebarInputField()
      input.alignment = .right
      input.tag = c.tag
      input.target = self
      input.action = #selector(valueInputAction)
      input.cell?.sendsActionOnEndEditing = true
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.allowsFloats = false
      formatter.usesGroupingSeparator = false
      input.formatter = formatter
      input.setAccessibilityLabel(label.stringValue)
      slider.setAccessibilityLabel(label.stringValue)
      valueInputs[c.tag] = input

      input.size(width: 50, height: 24)

      stack.addArrangedSubview(ui.hStack(
        spacing: 8,
        ui.image(c.symbolName, size: 16, config: .sidebarIconConfig), label, slider, input
      ))

      if let firstLabel {
        label.widthAnchor.constraint(equalTo: firstLabel.widthAnchor).isActive = true
      } else {
        firstLabel = label
      }
    }

    for row in stack.arrangedSubviews {
      row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    addSubview(stack)
    stack.padding(.horizontal(1), .vertical(2))

    update()
    player.observe(.iinaTrackSettingsChanged) { [unowned self] _ in update() }
    player.observe(.iinaVideoEqualizerChanged) { [unowned self] _ in
      update()
    }
    update()
  }

  private func update() {
    let settings = player.scopedVideoSettings(.videoColor)
    let values = [settings.brightness, settings.contrast, settings.saturation, settings.gamma, settings.hue]
    let enabled = !player.mainWindow.interactiveMode.isActive
    for (config, value) in zip(configs, values) {
      self[keyPath: config.keyPath]?.isEnabled = enabled
      self[keyPath: config.keyPath]?.integerValue = value
      if let input = valueInputs[config.tag] {
        input.isEnabled = enabled
        input.integerValue = value
        // A group Reset or target change also replaces an unfinished edit.
        input.currentEditor()?.string = input.stringValue
      }
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func sliderAction(_ sender: NSSlider) {
    valueInputs[sender.tag]?.integerValue = sender.integerValue
    if player.scopedTrackSettings.target(.videoColor) > 0, NSApp.currentEvent?.type == .leftMouseDragged { return }
    let config = configs.first(where: { $0.tag == sender.tag })!
    player.performSidebarChange { player.setScopedVideoEqualizer(config.type, value: Int(sender.intValue)) }
  }

  @objc private func valueInputAction(_ sender: NSTextField) {
    guard !player.mainWindow.interactiveMode.isActive,
          let config = configs.first(where: { $0.tag == sender.tag }),
          let entered = Int(sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      update()
      return
    }
    let value = min(100, max(-100, entered))
    sender.integerValue = value
    self[keyPath: config.keyPath]?.integerValue = value
    player.performSidebarChange { player.setScopedVideoEqualizer(config.type, value: value) }
  }
}
