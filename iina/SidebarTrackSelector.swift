//
//  SidebarTrackSelector.swift
//  iina
//
//  Created by Hechen Li on 2026-06-14.
//  Copyright © 2026 lhc. All rights reserved.
//

class TrackSelector: SidebarSectionScrollView, NSTableViewDelegate, NSTableViewDataSource {
  private static let rowHeight: CGFloat = 26
  private static let headerHeight: CGFloat = 26
  private static let defaultHeight = headerHeight + rowHeight * 4
  private let trackType: MPVTrack.TrackType
  private unowned let player: PlayerCore

  private var selection = TrackSelectionState()
  private var mediaGeneration = -1
  private var displayedTracks: [MPVTrack] = []
  private var tableView: TrackTableView
  private let noTrackButton = TrackOffButton()
  private let resizeHandle = TrackListResizeHandle()
  private let outline = TrackListOutlineView()
  private var rangeHighlightIDs: Set<Int> = []
  private var rangeOpacity: CGFloat = 1
  private var rangeFadeTimer: Timer?
  private var rangeFade: (id: Int, from: CGFloat, startedAt: TimeInterval, duration: TimeInterval)?
  private lazy var listHeight = heightAnchor.constraint(equalToConstant: Self.defaultHeight)
  private var heightTimer: Timer?
  private var heightMotion: (from: CGFloat, to: CGFloat, scrollFrom: CGFloat, scrollTo: CGFloat,
                             startedAt: TimeInterval, duration: TimeInterval)?

  init(_ trackType: MPVTrack.TrackType, player: PlayerCore, observedKeys: [Notification.Name]) {
    self.player = player
    self.trackType = trackType
    self.tableView = TrackTableView()
    super.init(frame: .zero)

    tableView.onClick = { [weak self] id, event in self?.activate(id: id, event: event) }
    tableView.isTrackEnabled = { [weak self] id in self?.isTrackAvailable(id) ?? false }
    tableView.trackID = { [weak self] row in
      guard let self, row >= 0 else { return nil }
      return displayedTracks[at: row]?.id
    }
    tableView.initialKeyboardTrackID = { [weak self] in
      guard let self else { return nil }
      let active = player.info.activeTrackIDs(trackType)
      return displayedTracks.first { active.contains($0.id) }?.id
    }
    tableView.selectionHighlightStyle = .none
    tableView.allowsMultipleSelection = false
    tableView.delegate = self
    tableView.dataSource = self
    tableView.style = .plain
    tableView.rowHeight = Self.rowHeight
    tableView.intercellSpacing.height = 0

    let nameColumn = NSTableColumn(identifier: .trackName)
    nameColumn.headerCell.setAccessibilityElement(false)
    tableView.addTableColumn(nameColumn)
    let header = TrackOffHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: Self.headerHeight))
    header.addSubview(noTrackButton)
    header.setAccessibilityElement(true)
    header.setAccessibilityRole(.group)
    header.setAccessibilityChildren([noTrackButton])
    noTrackButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      noTrackButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 0),
      noTrackButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: 0),
      noTrackButton.topAnchor.constraint(equalTo: header.topAnchor),
      noTrackButton.bottomAnchor.constraint(equalTo: header.bottomAnchor),
    ])
    switch trackType {
    case .audio:
      noTrackButton.title = NSLocalizedString("sidebar.no_audio", value: "No audio", comment: "Audio track selection")
      noTrackButton.image = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: nil)
    case .video:
      noTrackButton.title = NSLocalizedString("sidebar.no_video", value: "No video", comment: "Video track selection")
      noTrackButton.image = NSImage(systemSymbolName: "video.slash", accessibilityDescription: nil)
    case .sub, .secondSub:
      noTrackButton.title = NSLocalizedString("sidebar.no_subtitles", value: "No subtitles", comment: "Subtitle track selection")
      noTrackButton.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: nil)
    }
    noTrackButton.onRightClick = { [weak self] event in self?.activate(id: 0, event: event) }
    noTrackButton.target = self
    noTrackButton.action = #selector(selectNoTrack(_:))
    tableView.headerView = header
    tableView.cornerView = nil
    tableView.allowsColumnResizing = false
    tableView.allowsColumnReordering = false
    tableView.backgroundColor = .clear
    tableView.gridStyleMask = [.solidHorizontalGridLineMask]

    translatesAutoresizingMaskIntoConstraints = false
    documentView = tableView
    drawsBackground = false
    verticalScrollElasticity = .none
    horizontalScrollElasticity = .none
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.masksToBounds = true
    layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.1).cgColor
    outline.gridColor = tableView.gridColor
    outline.headerHeight = Self.headerHeight
    addSubview(outline)
    listHeight.isActive = true
    resizeHandle.onResize = { [weak self] height in
      self?.resizeList(to: height)
    }
    addSubview(resizeHandle)

    player.observe(.iinaTracklistChanged) { [weak self] _ in
      self?.reloadTracks()
    }
    reloadTracks()
    for key in observedKeys {
      player.observe(key) { [weak self] _ in self?.reloadTracks() }
    }
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    heightTimer?.invalidate()
    rangeFadeTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Keep observing the owning window while an inactive tab is detached.
    guard let window else { finishHeightAnimation(); finishRangeFade(); return }
    let center = NotificationCenter.default
    center.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
    center.addObserver(self, selector: #selector(resetHeightOnWindowClose(_:)),
                       name: NSWindow.willCloseNotification, object: window)
  }

  @objc private func resetHeightOnWindowClose(_ notification: Notification) {
    finishRangeFade()
    stopHeightAnimation()
    listHeight.constant = Self.defaultHeight
    contentView.scroll(to: NSPoint(x: 0, y: -Self.headerHeight))
    reflectScrolledClipView(contentView)
  }

  private func resizeList(to height: CGFloat) {
    let maximumRows = max(4, floor((maximumListHeight - Self.headerHeight) / Self.rowHeight))
    let rows = min(maximumRows, max(4, ((height - Self.headerHeight) / Self.rowHeight).rounded()))
    let target = Self.headerHeight + rows * Self.rowHeight
    guard heightMotion?.to != target else { return }
    let contentHeight = CGFloat(tableView.numberOfRows) * Self.rowHeight
    // AppKit includes the pinned header as a negative inset in the clip bounds.
    let scrollOffset = contentView.bounds.minY + Self.headerHeight
    let alignedOffset = (scrollOffset / Self.rowHeight).rounded() * Self.rowHeight
    let viewportHeight = target - Self.headerHeight
    let scrollTarget = max(0, min(max(0, contentHeight - viewportHeight), alignedOffset)) - Self.headerHeight
    let duration = AccessibilityPreferences.motionReductionEnabled ? 0 : AccessibilityPreferences.adjustedDuration(0.14)
    guard duration > 0, window != nil else {
      stopHeightAnimation()
      applyHeight(target, scrollY: scrollTarget)
      return
    }
    guard listHeight.constant != target || contentView.bounds.minY != scrollTarget else {
      stopHeightAnimation()
      return
    }
    heightMotion = (listHeight.constant, target, contentView.bounds.minY, scrollTarget,
                    ProcessInfo.processInfo.systemUptime, duration)
    guard heightTimer == nil else { return }
    let timer = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] _ in
      self?.advanceHeightAnimation()
    }
    heightTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.add(timer, forMode: .eventTracking)
  }

  private func advanceHeightAnimation() {
    guard let motion = heightMotion else { return }
    if AccessibilityPreferences.motionReductionEnabled || AccessibilityPreferences.adjustedDuration(motion.duration) == 0 {
      finishHeightAnimation()
      return
    }
    let t = min(1, (ProcessInfo.processInfo.systemUptime - motion.startedAt) / motion.duration)
    let progress = CGFloat(1 - pow(1 - t, 3))
    applyHeight(motion.from + (motion.to - motion.from) * progress,
                scrollY: motion.scrollFrom + (motion.scrollTo - motion.scrollFrom) * progress)
    if t == 1 { finishHeightAnimation() }
  }

  private func applyHeight(_ height: CGFloat, scrollY: CGFloat) {
    listHeight.constant = height
    window?.contentView?.layoutSubtreeIfNeeded()
    contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: scrollY))
    reflectScrolledClipView(contentView)
  }

  private func finishHeightAnimation() {
    if let motion = heightMotion { applyHeight(motion.to, scrollY: motion.scrollTo) }
    stopHeightAnimation()
  }

  private func stopHeightAnimation() {
    heightTimer?.invalidate()
    heightTimer = nil
    heightMotion = nil
  }

  override func tile() {
    super.tile()
    if subviews.last !== outline { addSubview(outline, positioned: .above, relativeTo: nil) }
    outline.frame = bounds
    outline.needsDisplay = true
    resizeHandle.frame = NSRect(x: bounds.minX, y: isFlipped ? bounds.maxY - 6 : bounds.minY,
                                width: bounds.width, height: 6)
  }

  override func scrollWheel(with event: NSEvent) {
    let visibleHeight = max(0, contentSize.height - Self.headerHeight)
    if CGFloat(tableView.numberOfRows) * Self.rowHeight <= visibleHeight + 0.5 {
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

  private var maximumListHeight: CGFloat {
    guard let content = window?.contentView else { return Self.defaultHeight }
    // Keep the list's grip clear of the window's own resize border.
    var bottom = content.convert(content.bounds, to: nil).minY + 8
    var ancestor = superview
    while let view = ancestor {
      if let scroll = view as? NSScrollView {
        bottom = max(bottom, scroll.contentView.convert(scroll.contentView.bounds, to: nil).minY)
        break
      }
      ancestor = view.superview
    }
    return max(Self.defaultHeight, min(content.bounds.height, convert(bounds, to: nil).maxY - bottom))
  }
  
  private func reloadTracks() {
    if mediaGeneration != player.info.trackSelectionGeneration {
      stopRangeFade()
      rangeHighlightIDs = []
      rangeOpacity = 1
      selection = TrackSelectionState()
      tableView.keyboardTrackID = nil
      mediaGeneration = player.info.trackSelectionGeneration
    }
    let tracks = player.info.orderedTrackList(trackType)
    selection.synchronize(tracks.map(\.id))
    if selection.anchor == nil { stopRangeFade(); rangeHighlightIDs = []; rangeOpacity = 1 }
    let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
    displayedTracks = selection.order.compactMap { byID[$0] }
    reloadSelection()
  }

  private var positionColumnWidth: CGFloat {
    max(14, ceil((String(max(1, displayedTracks.count)) as NSString).size(withAttributes: [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
    ]).width))
  }

  private func reloadSelection() {
    noTrackButton.positionColumnWidth = positionColumnWidth
    noTrackButton.state = player.info.activeTrackIDs(trackType).isEmpty ? .on : .off
    noTrackButton.needsDisplay = true
    tableView.reloadData()
  }

  @objc private func selectNoTrack(_ sender: NSButton) {
    activate(id: 0, event: NSApp.currentEvent)
  }

  private func activate(id: Int, event: NSEvent?) {
    guard id == 0 || displayedTracks.contains(where: { $0.id == id }),
          isTrackAvailable(id),
          event?.type != .rightMouseUp || trackType == .audio || trackType == .video else { return }
    let action: TrackSelectionState.Action
    if trackType == .audio || trackType == .video, event?.type == .rightMouseUp || event?.modifierFlags.contains(.command) == true {
      action = .toggle
    } else if trackType == .audio || trackType == .video, event?.modifierFlags.contains(.shift) == true {
      action = .range
    } else {
      action = .solo
    }
    let previous = selection
    let active = player.info.activeTrackIDs(trackType)
    let ids = selection.select(id, action: action, active: active)
    var applied = true
    player.performSidebarChange {
      if trackType == .audio {
        if ids != active { applied = player.setAudioTracks(ids) }
      } else if trackType == .video {
        if ids != active { applied = player.setVideoTracks(ids, order: selection.order) }
      } else {
        player.setTrack(id, forType: trackType)
      }
    }
    if !applied { selection = previous }
    if applied, previous.anchor != selection.anchor || selection.anchor == nil {
      stopRangeFade()
      rangeHighlightIDs = Set(selection.anchor.map { [$0] } ?? [])
      rangeOpacity = 1
    }
    var completedRange = false
    if applied, action == .range, let anchor = previous.anchor, selection.anchor == anchor,
       let start = selection.order.firstIndex(of: anchor), let end = selection.order.firstIndex(of: id) {
      stopRangeFade()
      rangeHighlightIDs = Set(selection.order[min(start, end)...max(start, end)])
      rangeOpacity = 1
      completedRange = true
    }
    reloadSelection()
    if completedRange, let anchor = selection.anchor {
      fadeRange(anchor)
    }
  }

  private func isTrackAvailable(_ id: Int) -> Bool {
    guard id > 0 else { return true }
    switch trackType {
    case .sub: return player.info.secondSid != id
    case .secondSub: return player.info.sid != id
    case .audio, .video: return true
    }
  }

  private func fadeRange(_ id: Int) {
    stopRangeFade()
    let duration = AccessibilityPreferences.motionReductionEnabled ? 0 : AccessibilityPreferences.adjustedDuration(0.3)
    guard duration > 0, window != nil, rangeOpacity > 0 else {
      setRangeOpacity(0)
      return
    }
    rangeFade = (id, rangeOpacity, ProcessInfo.processInfo.systemUptime, duration)
    let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
      guard let self, let fade = self.rangeFade else { return }
      guard self.selection.anchor == fade.id else { self.stopRangeFade(); return }
      let t = min(1, (ProcessInfo.processInfo.systemUptime - fade.startedAt) / fade.duration)
      self.setRangeOpacity(fade.from * CGFloat(1 - t))
      if t == 1 || AccessibilityPreferences.motionReductionEnabled || AccessibilityPreferences.adjustedDuration(fade.duration) == 0 {
        self.finishRangeFade()
      }
    }
    rangeFadeTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func setRangeOpacity(_ opacity: CGFloat) {
    rangeOpacity = opacity
    for row in 0..<displayedTracks.count {
      (tableView.rowView(atRow: row, makeIfNecessary: false) as? TrackRangeRowView)?.rangeOpacity = opacity
    }
  }

  private func finishRangeFade() {
    guard rangeFade != nil else { return }
    stopRangeFade()
    setRangeOpacity(0)
  }

  private func stopRangeFade() {
    rangeFadeTimer?.invalidate()
    rangeFadeTimer = nil
    rangeFade = nil
  }

  func numberOfRows(in tableView: NSTableView) -> Int { displayedTracks.count }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let view = TrackRangeRowView()
    view.isHighlighted = displayedTracks[at: row].map { rangeHighlightIDs.contains($0.id) } ?? false
    view.rangeOpacity = rangeOpacity
    return view
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let trackList = displayedTracks
    guard let column = tableColumn, let track = trackList[at: row] else { return nil }

    let active = player.info.activeTrackIDs(trackType)

    let columnID = column.identifier
    let identifier = NSUserInterfaceItemIdentifier("\(columnID.rawValue)Cell")

    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? CellView ?? {
      let cell = CellView()
      cell.identifier = identifier
      return cell
    }()
    let isChosen = active.contains(track.id)
    let isAvailable = isTrackAvailable(track.id)
    cell.alphaValue = isAvailable ? 1 : 0.4
    cell.setAccessibilityEnabled(isAvailable)
    switch columnID {
    case .trackName:
      cell.setPosition(row + 1, width: positionColumnWidth)
      cell.textField?.textColor = .labelColor
      cell.textField?.stringValue = track.readableString(includingLanguage: false)
      cell.selectedIndicator.isHidden = !isChosen
      cell.setLanguage(track.readableLanguage)
      cell.setRemoval(track.isExternal && (trackType == .audio || trackType == .video)) { [weak self] in
        guard let self else { return }
        let removed = self.player.performSidebarChange {
          self.player.removeExternalTrack(track.id, type: self.trackType, order: self.selection.order)
        }
        if removed {
          self.reloadTracks()
        }
      }
    default:
      break
    }
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let id = tableView.trackID?(tableView.selectedRow) else { return }
    defer { tableView.deselectAll(nil) }
    guard isTrackAvailable(id) else { return }
    tableView.keyboardTrackID = id
    activate(id: id, event: NSApp.currentEvent)
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    displayedTracks[at: row].map { isTrackAvailable($0.id) } ?? false
  }

  private class CellView: NSTableCellView {
    private static let accessorySpacing: CGFloat = 4
    private static let maskFeather: CGFloat = 16
    let positionLabel = NSTextField(labelWithString: "")
    private lazy var positionWidth = positionLabel.widthAnchor.constraint(equalToConstant: 14)
    private let removeButton = TrackRemoveButton()
    private let titleContent = NSView()
    private let titleMask = CAGradientLayer()
    private lazy var languageSpacing = languageTag.leadingAnchor.constraint(
      greaterThanOrEqualTo: textField!.trailingAnchor, constant: Self.accessorySpacing)
    private var removal: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    private var isHovered = false
    private var removalVisible = false
    private var visibilityVersion = 0

    func setRemoval(_ removable: Bool, action: @escaping () -> Void) {
      removal = removable ? action : nil
      setAccessibilityCustomActions(removable ? [NSAccessibilityCustomAction(
        name: NSLocalizedString("track.remove_external", comment: "Remove external track from player")
      ) { [weak self] in
        guard let removal = self?.removal else { return false }
        removal()
        return true
      }] : [])
      updateRemoveButton(animated: false)
    }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let hoverArea { removeTrackingArea(hoverArea) }
      let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
      addTrackingArea(area)
      hoverArea = area
      isHovered = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
      updateRemoveButton()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; updateRemoveButton() }
    override func mouseExited(with event: NSEvent) { isHovered = false; updateRemoveButton() }

    private func updateRemoveButton(animated: Bool = true) {
      let visible = removal != nil && (isHovered || NSWorkspace.shared.isVoiceOverEnabled)
      guard visible != removalVisible else { return }
      removalVisible = visible
      visibilityVersion += 1
      let version = visibilityVersion
      let duration = !animated || window == nil || AccessibilityPreferences.motionReductionEnabled ? 0 : AccessibilityPreferences.adjustedDuration(0.12)
      let colors = [NSColor.black.cgColor, NSColor.black.cgColor,
                    NSColor.black.withAlphaComponent(visible ? 0 : 1).cgColor,
                    NSColor.black.withAlphaComponent(visible ? 0 : 1).cgColor]
      let previous = titleMask.presentation()?.colors ?? titleMask.colors
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      titleMask.colors = colors
      CATransaction.commit()
      if duration > 0 {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = previous
        animation.toValue = colors
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        titleMask.add(animation, forKey: "hover")
      } else {
        titleMask.removeAnimation(forKey: "hover")
      }
      guard duration > 0 else {
        removeButton.alphaValue = visible ? 1 : 0
        removeButton.isHidden = !visible
        return
      }
      if visible { removeButton.isHidden = false }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        removeButton.animator().alphaValue = visible ? 1 : 0
      } completionHandler: { [weak self] in
        guard let self, self.visibilityVersion == version else { return }
        self.removeButton.isHidden = !visible
      }
    }

    override func layout() {
      super.layout()
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      titleMask.frame = titleContent.bounds
      let width = max(1, titleContent.bounds.width)
      let circle = titleContent.convert(removeButton.circleFrame, from: removeButton)
      let fadeEnd = max(0, min(width, circle.minX - Self.accessorySpacing))
      titleMask.locations = [0, NSNumber(value: max(0, fadeEnd - Self.maskFeather) / width),
                             NSNumber(value: fadeEnd / width), 1]
      CATransaction.commit()
    }

    @objc private func removeTrack() { removal?() }

    func setPosition(_ position: Int, width: CGFloat) {
      positionLabel.stringValue = String(position)
      positionWidth.constant = width
    }
    var selectedIndicator: ColoredView
    var languageTag: ColoredView
    var languageLabel: NSTextField

    override init(frame frameRect: NSRect) {
      self.selectedIndicator = ColoredView(color: AppAccentColor.color, cornerRadius: 2)
      selectedIndicator.translatesAutoresizingMaskIntoConstraints = false

      self.languageTag = ColoredView(color: .controlColor, cornerRadius: 3)
      languageTag.translatesAutoresizingMaskIntoConstraints = false

      self.languageLabel = NSTextField(labelWithString: "")
      languageLabel.translatesAutoresizingMaskIntoConstraints = false

      super.init(frame: frameRect)

      let textField = NSTextField(labelWithString: "")
      textField.isSelectable = false
      textField.translatesAutoresizingMaskIntoConstraints = false
      textField.lineBreakMode = .byTruncatingMiddle
      textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      titleContent.translatesAutoresizingMaskIntoConstraints = false
      titleContent.wantsLayer = true
      titleMask.startPoint = CGPoint(x: 0, y: 0.5)
      titleMask.endPoint = CGPoint(x: 1, y: 0.5)
      titleMask.colors = Array(repeating: NSColor.black.cgColor, count: 4)
      titleContent.layer?.mask = titleMask
      addSubview(titleContent)
      titleContent.addSubview(textField)
      positionLabel.translatesAutoresizingMaskIntoConstraints = false
      positionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
      positionLabel.textColor = .secondaryLabelColor
      positionLabel.alignment = .center
      positionLabel.setAccessibilityElement(false)
      addSubview(positionLabel)
      NSLayoutConstraint.activate([
        positionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
        positionWidth,
        positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        titleContent.leadingAnchor.constraint(equalTo: positionLabel.trailingAnchor, constant: 6),
        titleContent.trailingAnchor.constraint(equalTo: trailingAnchor),
        titleContent.topAnchor.constraint(equalTo: topAnchor),
        titleContent.bottomAnchor.constraint(equalTo: bottomAnchor),
        textField.leadingAnchor.constraint(equalTo: titleContent.leadingAnchor),
        textField.trailingAnchor.constraint(lessThanOrEqualTo: titleContent.trailingAnchor),
        textField.centerYAnchor.constraint(equalTo: titleContent.centerYAnchor),
      ])
      self.textField = textField

      addSubview(selectedIndicator)
      selectedIndicator.padding(.leading, .vertical(5))
        .size(width: 4)

      languageLabel.font = .systemFont(ofSize: 11)

      languageTag.addSubview(languageLabel)
      languageLabel.padding(.vertical(1), .horizontal(2))

      titleContent.addSubview(languageTag)
      languageTag.center(.y)
      languageTag.trailingAnchor.constraint(equalTo: titleContent.trailingAnchor).isActive = true

      removeButton.translatesAutoresizingMaskIntoConstraints = false
      removeButton.isBordered = false
      removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
      removeButton.imagePosition = .imageOnly
      removeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
      removeButton.contentTintColor = .secondaryLabelColor
      removeButton.setAccessibilityLabel(NSLocalizedString("track.remove_external", comment: "Remove external track from player"))
      removeButton.target = self
      removeButton.action = #selector(removeTrack)
      removeButton.isHidden = true
      removeButton.alphaValue = 0
      addSubview(removeButton)
      NSLayoutConstraint.activate([
        removeButton.trailingAnchor.constraint(equalTo: languageTag.trailingAnchor, constant: TrackRemoveButton.circleInset),
        removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        removeButton.widthAnchor.constraint(equalToConstant: TrackRemoveButton.hitSize),
        removeButton.heightAnchor.constraint(equalToConstant: TrackRemoveButton.hitSize),
      ])
    }

    func setLanguage(_ language: String?) {
      let hasLanguage = language.map { !$0.isEmpty } ?? false
      languageLabel.stringValue = language ?? ""
      languageTag.isHidden = !hasLanguage
      languageSpacing.isActive = hasLanguage
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }
}

private final class TrackRemoveButton: NSButton {
  static let hitSize = CircularActionButtonStyle.hitSize
  static let circleDiameter = CircularActionButtonStyle.circleDiameter
  static let circleInset = CircularActionButtonStyle.circleInset
  override var alignmentRectInsets: NSEdgeInsets { CircularActionButtonStyle.alignmentInsets }
  var circleFrame: NSRect {
    CircularActionButtonStyle.circleFrame(in: bounds)
  }
  private var hoverArea: NSTrackingArea?
  private var hovered = false

  override var isHidden: Bool {
    didSet {
      if isHidden { hovered = false; needsDisplay = true }
      window?.invalidateCursorRects(for: self)
    }
  }

  override var isEnabled: Bool {
    didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) }
  }
  override var alphaValue: CGFloat { didSet { window?.invalidateCursorRects(for: self) } }

  override func resetCursorRects() {
    super.resetCursorRects()
    CircularActionButtonStyle.addCursorRect(to: self)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

  override func draw(_ dirtyRect: NSRect) {
    let pressed = cell?.isHighlighted == true
    NSColor.labelColor.withAlphaComponent(pressed ? 0.3 : hovered ? 0.2 : 0.12).setFill()
    NSBezierPath(ovalIn: circleFrame).fill()
    NSColor.labelColor.withAlphaComponent(isEnabled ? 0.85 : 0.35).setStroke()
    let cross = NSBezierPath()
    cross.lineWidth = 1.2
    cross.lineCapStyle = .round
    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    cross.move(to: NSPoint(x: center.x - 2.5, y: center.y - 2.5))
    cross.line(to: NSPoint(x: center.x + 2.5, y: center.y + 2.5))
    cross.move(to: NSPoint(x: center.x - 2.5, y: center.y + 2.5))
    cross.line(to: NSPoint(x: center.x + 2.5, y: center.y - 2.5))
    cross.stroke()
  }
}

private final class TrackOffHeaderView: NSTableHeaderView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    let background = NSVisualEffectView(frame: bounds)
    background.autoresizingMask = [.width, .height]
    background.material = .popover
    background.blendingMode = .withinWindow
    background.state = .active
    background.setAccessibilityElement(false)
    addSubview(background)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ dirtyRect: NSRect) {}
  override func mouseDown(with event: NSEvent) {}
}

private final class TrackOffButton: NSButton {
  var onRightClick: ((NSEvent) -> Void)?
  var positionColumnWidth: CGFloat = 14
  private var rightPress: NSPoint?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setButtonType(.toggle)
    isBordered = false
    imagePosition = .imageLeading
    imageScaling = .scaleProportionallyDown
    alignment = .left
    font = .systemFont(ofSize: NSFont.systemFontSize)
    contentTintColor = .labelColor
    focusRingType = .none
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    let selected = state == .on
    if selected {
      AppAccentColor.color.setFill()
      NSBezierPath(roundedRect: NSRect(x: 8, y: 5, width: 4, height: bounds.height - 10),
                   xRadius: 1.5, yRadius: 1.5).fill()
    }
    let iconSize: CGFloat = 14
    let icon = image?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))?
      .withSymbolConfiguration(.init(paletteColors: [.labelColor]))
    icon?.draw(in: NSRect(x: 20 + (positionColumnWidth - iconSize) / 2, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraph,
    ]
    let textHeight = (title as NSString).size(withAttributes: attributes).height
    (title as NSString).draw(in: NSRect(x: 26 + positionColumnWidth, y: (bounds.height - textHeight) / 2,
                                      width: max(0, bounds.width - 38 - positionColumnWidth), height: textHeight),
                            withAttributes: attributes)
  }

  override func rightMouseDown(with event: NSEvent) {
    rightPress = event.locationInWindow
  }

  override func rightMouseDragged(with event: NSEvent) {
    if let press = rightPress, hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y) > 3 {
      rightPress = nil
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    defer { rightPress = nil }
    guard let press = rightPress,
          hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y) <= 3,
          bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    onRightClick?(event)
  }
}

private final class TrackListOutlineView: NSView {
  var gridColor: NSColor = .gridColor
  var headerHeight: CGFloat = 26
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.sidebarContainerBorder.setStroke()
    let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
    border.lineWidth = 1
    border.stroke()
    gridColor.setFill()
    let pixel = 1 / (window?.backingScaleFactor ?? 1)
    NSRect(x: bounds.minX + 1, y: bounds.minY + headerHeight - pixel,
           width: max(0, bounds.width - 2), height: pixel).fill()
  }
}

private final class TrackListResizeHandle: NSControl {
  var onResize: ((CGFloat) -> Void)?

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: ResizeCursor.vertical)
  }

  override func mouseDown(with event: NSEvent) {
    guard let window, let list = superview else { return }
    let origin = event.locationInWindow
    let height = list.frame.height
    ResizeCursor.vertical.push()
    defer { NSCursor.pop() }
    // Window coordinates stay stable while the enclosing sidebar lays out.
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseUp { return }
      onResize?(height + origin.y - next.locationInWindow.y)
    }
  }
}

class ColoredView: NSView {
  let color: NSColor
  let cornerRadius: CGFloat

  init(color: NSColor, cornerRadius: CGFloat = 0) {
    self.color = color
    self.cornerRadius = cornerRadius
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    color.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
  }
}


private class TrackRangeRowView: NSTableRowView {
  var isHighlighted = false
  var rangeOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
  override func drawBackground(in dirtyRect: NSRect) {
    super.drawBackground(in: dirtyRect)
    if isHighlighted {
      NSColor.labelColor.withAlphaComponent(0.08 * rangeOpacity).setFill()
      bounds.fill()
    }
  }
}

/// Keep the gesture local to the list: a drag never becomes a playback click.
private class TrackTableView: NSTableView {
  override func accessibilityChildren() -> [Any]? {
    var children = super.accessibilityChildren() ?? []
    if let headerView { children.insert(headerView, at: 0) }
    return children
  }

  var onClick: ((Int, NSEvent) -> Void)?
  var isTrackEnabled: ((Int) -> Bool)?
  var trackID: ((Int) -> Int?)?
  var initialKeyboardTrackID: (() -> Int?)?
  var keyboardTrackID: Int?
  private var rightPress: (row: Int, id: Int, point: NSPoint)?

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 125, 126: // Down / Up
      guard numberOfRows > 0 else { return }
      let id = keyboardTrackID ?? initialKeyboardTrackID?()
      let current = (0..<numberOfRows).first { trackID?($0) == id }
      let step = event.keyCode == 125 ? 1 : -1
      var row = (current ?? (step > 0 ? -1 : numberOfRows)) + step
      while (0..<numberOfRows).contains(row) {
        if let nextID = trackID?(row), isTrackEnabled?(nextID) != false {
          keyboardTrackID = nextID
          scrollRowToVisible(row)
          onClick?(nextID, event)
          return
        }
        row += step
      }
    case 123, 124: // A one-column table has no horizontal destination.
      return
    default:
      super.keyDown(with: event)
    }
  }

  override func mouseDown(with event: NSEvent) {
    let origin = convert(event.locationInWindow, from: nil)
    let row = row(at: origin)
    guard row >= 0, let id = trackID?(row), let window else { return }
    // Focusing can scroll the table; capture track identity and window-space row before changing focus.
    let pressedFrame = convert(rect(ofRow: row), to: nil)
    if isTrackEnabled?(id) != false {
      keyboardTrackID = id
      window.makeFirstResponder(self)
    }
    var moved = false
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      let delta = NSPoint(x: next.locationInWindow.x - event.locationInWindow.x,
                          y: next.locationInWindow.y - event.locationInWindow.y)
      if hypot(delta.x, delta.y) > 3 { moved = true }
      if next.type == .leftMouseUp {
        if !moved, pressedFrame.contains(next.locationInWindow), isTrackEnabled?(id) != false {
          onClick?(id, event)
        }
        return
      }
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let row = row(at: point)
    rightPress = trackID?(row).map { (row, $0, point) }
  }

  override func rightMouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let press = rightPress, hypot(point.x - press.point.x, point.y - press.point.y) > 3 { rightPress = nil }
  }

  override func rightMouseUp(with event: NSEvent) {
    defer { rightPress = nil }
    let point = convert(event.locationInWindow, from: nil)
    guard let press = rightPress, press.row >= 0, row(at: point) == press.row,
          hypot(point.x - press.point.x, point.y - press.point.y) <= 3 else { return }
    keyboardTrackID = press.id
    window?.makeFirstResponder(self)
    onClick?(press.id, event)
  }
}
