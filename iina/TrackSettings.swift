import Cocoa

class SettingsTargetPopUp: NSPopUpButton {
  private var hoverArea: NSTrackingArea?
  private var hovered = false
  var symbolName: String {
    get { (cell as? TrackSettingsHeadingCell)?.symbolName ?? "display" }
    set { (cell as? TrackSettingsHeadingCell)?.symbolName = newValue; needsDisplay = true }
  }
  override init(frame: NSRect, pullsDown: Bool) {
    super.init(frame: frame, pullsDown: pullsDown)
    cell = TrackSettingsHeadingCell(textCell: "", pullsDown: false)
    translatesAutoresizingMaskIntoConstraints = false
    isBordered = false
    alignment = .left
    font = .systemFont(ofSize: 13, weight: .semibold)
    (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
    setContentCompressionResistancePriority(.init(100), for: .horizontal)
    setContentHuggingPriority(.required, for: .horizontal)
    heightAnchor.constraint(equalToConstant: 28).isActive = true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
  override var intrinsicContentSize: NSSize {
    let text = (titleOfSelectedItem ?? "") as NSString
    // 48 pt reserves the icon inset, 6 pt label gap, chevron and trailing padding.
    return NSSize(width: ceil(text.size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13)]).width) + 48, height: 28)
  }
  override var isEnabled: Bool {
    didSet { if !isEnabled { hovered = false }; needsDisplay = true; window?.invalidateCursorRects(for: self) }
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area); hoverArea = area
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func cursorUpdate(with event: NSEvent) { (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set() }
  override func resetCursorRects() {
    super.resetCursorRects()
    if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
  }
  override func draw(_ dirtyRect: NSRect) {
    if isEnabled && (hovered || cell?.isHighlighted == true) {
      NSColor.labelColor.withAlphaComponent(cell?.isHighlighted == true ? 0.14 : 0.08).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    super.draw(dirtyRect)
  }
  override var focusRingMaskBounds: NSRect { bounds }
  override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
}

/// Changing the editing target must not change playback membership.
final class TrackSettingsPopUp: SettingsTargetPopUp, NSMenuDelegate {
  private unowned let player: PlayerCore
  let group: TrackSettingsGroup
  init(player: PlayerCore, group: TrackSettingsGroup) {
    self.player = player; self.group = group
    super.init(frame: .zero, pullsDown: false)
    target = self; action = #selector(selectTarget)
    menu?.delegate = self
    setAccessibilityLabel(NSLocalizedString("track_settings.target", comment: "Editing target"))
    player.observe(.iinaTrackSettingsChanged) { [weak self] _ in self?.rebuild() }
    player.observe(.iinaTracklistChanged) { [weak self] _ in self?.rebuild() }
    player.observe(.iinaTrackOrderChanged) { [weak self] _ in self?.rebuild() }
    rebuild()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func menuNeedsUpdate(_ menu: NSMenu) {
    // AppKit can end editing before dispatching the menu action, rebuilding its tracked items.
    window?.makeFirstResponder(nil)
    rebuild()
  }
  private func rebuild() {
    removeAllItems()
    addItem(withTitle: NSLocalizedString(group.isAudio ? "track_settings.master" : "track_settings.output", comment: "Overall processing"))
    item(at: 0)?.tag = 0
    let tracks = player.info.orderedTrackList(group.isAudio ? .audio : .video)
    for (index, track) in tracks.enumerated() {
      addItem(withTitle: String(format: NSLocalizedString("track_settings.track", value: "Track %ld", comment: "Track position"), index + 1))
      lastItem?.tag = track.id
    }
    let id = player.scopedTrackSettings.target(group)
    let targetDisappeared = id != 0 && !tracks.contains(where: { $0.id == id })
    if tracks.contains(where: { $0.id == id }) || id == 0 { selectItem(withTag: id) }
    else { player.scopedTrackSettings.setTarget(0, for: group); selectItem(withTag: 0) }
    isEnabled = group.isAudio || !player.mainWindow.interactiveMode.isActive
    symbolName = group.isAudio ? (selectedTag() == 0 ? "speaker.wave.2" : "waveform") : (selectedTag() == 0 ? "display" : "film")
    toolTip = titleOfSelectedItem
    invalidateIntrinsicContentSize(); needsDisplay = true
    if targetDisappeared { player.postNotification(.iinaTrackSettingsChanged) }
  }
  @objc private func selectTarget() {
    let requestedTarget = selectedTag()
    guard isEnabled, requestedTarget >= 0,
          group.isAudio || !player.mainWindow.interactiveMode.isActive else { return }
    // Ending an edit can synchronously rebuild this popup with the old target.
    window?.makeFirstResponder(nil)
    player.scopedTrackSettings.setTarget(requestedTarget, for: group)
    player.postNotification(.iinaTrackSettingsChanged)
  }
}

/// Subtitle settings target the two display roles, independently of source IDs.
final class SubtitleRoleSelector: NSSegmentedControl {
  var onChange: ((Bool) -> Void)?
  var isPrimary: Bool { selectedSegment == 0 }

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    segmentCount = 2
    for (index, key) in ["sidebar.primary", "sidebar.secondary"].enumerated() {
      setLabel(NSLocalizedString(key, comment: "Subtitle role"), forSegment: index)
    }
    trackingMode = .selectOne
    segmentStyle = .rounded
    segmentDistribution = .fillEqually
    selectedSegment = 0
    font = .systemFont(ofSize: 13, weight: .semibold)
    heightAnchor.constraint(equalToConstant: 28).isActive = true
    target = self
    action = #selector(selectRole)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func selectRole() {
    // Commit edits to the old role before changing either settings group.
    window?.makeFirstResponder(nil)
    onChange?(isPrimary)
  }
}

/// Option names for primary styles and the optional independent secondary styles.
enum SubtitleStyle {
  static let options = ["sub-scale", "sub-font", "sub-font-size", "sub-color",
                        "sub-outline-size", "sub-outline-color", "sub-back-color"]
  static func option(_ name: String, forPrimary: Bool) -> String {
    forPrimary ? name : "secondary-" + name
  }
}

private final class TrackSettingsHeadingCell: NSPopUpButtonCell {
  var symbolName = "display"
  override func titleRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.minX + 28, y: rect.minY, width: max(0, rect.width - 48), height: rect.height)
  }
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    let color: NSColor = isEnabled ? .labelColor : .disabledControlTextColor
    func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, rect: NSRect) {
      guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: weight)) else { return }
      let tinted = NSImage(size: image.size, flipped: false) { bounds in
        image.draw(in: bounds); color.setFill(); bounds.fill(using: .sourceIn); return true
      }
      let scale = min(rect.width / image.size.width, rect.height / image.size.height)
      let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
      tinted.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    symbol(symbolName, size: 14, weight: .regular,
           rect: NSRect(x: cellFrame.minX + 6, y: cellFrame.midY - 8, width: 16, height: 16))
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
    let text = NSAttributedString(string: (controlView as? NSPopUpButton)?.titleOfSelectedItem ?? title,
      attributes: [.font: font ?? NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color, .paragraphStyle: paragraph])
    var textFrame = titleRect(forBounds: cellFrame)
    textFrame.origin.y = cellFrame.midY - text.size().height / 2
    textFrame.size.height = text.size().height
    text.draw(in: textFrame)
    symbol("chevron.down", size: 8, weight: .semibold,
           rect: NSRect(x: cellFrame.maxX - 14, y: cellFrame.midY - 4, width: 8, height: 8))
  }
}

class SidebarResetButton: NSButton {
  var resetContextMenu: (() -> NSMenu)?
  private var presentingContextMenu = false
  private var hoverArea: NSTrackingArea?
  init(target: AnyObject?, action: Selector?) {
    super.init(frame: .zero)
    title = NSLocalizedString("track_settings.reset", comment: "Reset settings group")
    self.target = target; self.action = action
    translatesAutoresizingMaskIntoConstraints = false
    isBordered = false
    font = .systemFont(ofSize: 12)
    setContentHuggingPriority(.required, for: .horizontal)
    heightAnchor.constraint(equalToConstant: 24).isActive = true
    resetContextMenu = { [weak self] in
      guard let self, let target = self.target, let action = self.action else { return NSMenu() }
      return Self.makeContextMenu(currentTitle: self.title, target: target, currentAction: action)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
  override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.contains(.control), resetContextMenu != nil {
      _ = presentResetContextMenu()
    } else { super.mouseDown(with: event) }
  }
  override func rightMouseDown(with event: NSEvent) {
    if resetContextMenu != nil { _ = presentResetContextMenu() }
    else { super.rightMouseDown(with: event) }
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    guard isEnabled else { return nil }
    return resetContextMenu?() ?? super.menu(for: event)
  }
  override func accessibilityPerformShowMenu() -> Bool { presentResetContextMenu() }

  static func makeContextMenu(currentTitle: String, target: AnyObject,
                              currentAction: Selector, allAction: Selector? = nil) -> NSMenu {
    let menu = NSMenu()
    var actions = [(currentTitle, currentAction)]
    if let allAction {
      actions.append((NSLocalizedString("track_settings.reset_tracks", comment: "Reset group for every track"), allAction))
    }
    for (title, action) in actions {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = target
      menu.addItem(item)
    }
    return menu
  }
  @discardableResult private func presentResetContextMenu() -> Bool {
    guard isEnabled, !presentingContextMenu, let menu = resetContextMenu?(), menu.numberOfItems > 0,
          let window, let content = window.contentView else { return false }
    var available = content.convert(content.bounds, to: nil).insetBy(dx: 12, dy: 12)
    if let screen = window.screen {
      available = available.intersection(window.convertFromScreen(screen.visibleFrame).insetBy(dx: 12, dy: 12))
    }
    guard !available.isEmpty else { return false }
    presentingContextMenu = true
    let titles = menu.items.map(\.title)
    defer {
      for (item, title) in zip(menu.items, titles) { item.title = title }
      presentingContextMenu = false
      highlight(false)
    }
    // AppKit can shrink a menu when tracking starts; set regular metrics before measuring its anchor.
    menu.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
    while menu.size.width > available.width {
      let candidates = menu.items.filter { !$0.isHidden && $0.title.count > 2 }
      guard let item = candidates.max(by: {
        ($0.title as NSString).size(withAttributes: [.font: menu.font ?? NSFont.menuFont(ofSize: 0)]).width
          < ($1.title as NSString).size(withAttributes: [.font: menu.font ?? NSFont.menuFont(ofSize: 0)]).width
      }) else { break }
      let title = item.title.hasSuffix("…") ? String(item.title.dropLast()) : item.title
      item.title = String(title.dropLast()) + "…"
    }
    let size = menu.size
    guard size.width <= available.width, size.height <= available.height else { return false }
    let button = convert(bounds, to: nil)
    let x = min(max(button.maxX - size.width, available.minX), available.maxX - size.width)
    let gap: CGFloat = 8
    let below = button.minY - gap - size.height
    let preferredY = below >= available.minY ? below : button.maxY + gap
    let y = min(max(preferredY, available.minY), available.maxY - size.height)
    let anchorX = userInterfaceLayoutDirection == .rightToLeft ? x + size.width : x
    highlight(true)
    // Native nil-item tracking places the menu frame 5 pt above its anchor.
    let trackingTopInset: CGFloat = 5
    menu.popUp(positioning: nil,
               at: convert(NSPoint(x: anchorX, y: y + size.height - trackingTopInset), from: nil), in: self)
    return true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area); hoverArea = area
    needsDisplay = true
  }
  override func mouseEntered(with event: NSEvent) { needsDisplay = true }
  override func mouseExited(with event: NSEvent) { needsDisplay = true }
  override func resetCursorRects() {
    super.resetCursorRects()
    CircularActionButtonStyle.addCursorRect(to: self)
  }
  override func draw(_ dirtyRect: NSRect) {
    if isEnabled, !isHiddenOrHasHiddenAncestor, let window, window.isKeyWindow,
       bounds.intersection(visibleRect).contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
      NSColor.labelColor.withAlphaComponent(cell?.isHighlighted == true ? 0.14 : 0.08).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let label = NSAttributedString(string: title, attributes: [
      .font: font ?? NSFont.systemFont(ofSize: 12),
      .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor,
      .paragraphStyle: paragraph
    ])
    let height = label.size().height
    label.draw(in: NSRect(x: bounds.minX, y: bounds.midY - height / 2,
                          width: bounds.width, height: height))
  }
}

final class TrackSettingsGroupReset: SidebarResetButton {
  private unowned let player: PlayerCore
  let group: TrackSettingsGroup
  init(player: PlayerCore, group: TrackSettingsGroup) {
    self.player = player; self.group = group
    super.init(target: nil, action: nil)
    target = self; action = #selector(resetGroup)
    resetContextMenu = { [weak self] in
      guard let self else { return NSMenu() }
      let menu = Self.makeContextMenu(currentTitle: currentResetTitle, target: self,
                                      currentAction: #selector(resetGroup), allAction: #selector(resetAllTracks))
      let overall = NSLocalizedString(group.isAudio ? "track_settings.master" : "track_settings.output", comment: "Overall processing")
      menu.items[1].toolTip = String(format: NSLocalizedString("track_settings.reset_tracks_hint", comment: "All reset scopes"),
                                    NSLocalizedString(group.titleKey, comment: "Settings group"), overall)
      return menu
    }
    let label = String(format: NSLocalizedString("track_settings.reset_group", comment: "Reset group"),
                       NSLocalizedString(group.titleKey, comment: "Settings group"))
    setAccessibilityLabel(label); toolTip = label
    player.observe(.iinaTrackSettingsChanged) { [weak self] _ in self?.updateState() }
    updateState()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func updateState() {
    isEnabled = group.isAudio || !player.mainWindow.interactiveMode.isActive
  }
  private var currentResetTitle: String {
    let id = player.scopedTrackSettings.target(group)
    if id == 0 {
      let name = NSLocalizedString(group.isAudio ? "track_settings.master" : "track_settings.output", comment: "Overall target")
      return String(format: NSLocalizedString("track_settings.reset_output", comment: "Reset target"), name)
    }
    let tracks = player.info.orderedTrackList(group.isAudio ? .audio : .video)
    if let index = tracks.firstIndex(where: { $0.id == id }) {
      return String(format: NSLocalizedString("track_settings.reset_numbered_track", comment: "Reset numbered target"), index + 1)
    }
    return NSLocalizedString("track_settings.reset_track", comment: "Reset selected track")
  }
  @objc private func resetAllTracks() {
    guard isEnabled else { return }
    window?.makeFirstResponder(nil)
    player.performSidebarChange { player.resetTrackSettings(group, allTracks: true) }
  }
  @objc private func resetGroup() {
    guard isEnabled else { return }
    window?.makeFirstResponder(nil)
    player.performSidebarChange { player.resetTrackSettings(group) }
  }
}

extension PlayerCore {
  func scopedAudioDelay() -> Double {
    let id = scopedTrackSettings.target(.audioDelay)
    return id == 0 ? mpv.getDouble(MPVOption.Audio.audioDelay) : scopedTrackSettings.audio[id]?.delay ?? 0
  }
  func setScopedAudioDelay(_ value: Double) {
    guard value.isFinite else { return }
    let id = scopedTrackSettings.target(.audioDelay)
    if id == 0 { setAudioDelay(value); return }
    let old = scopedTrackSettings
    var profile = scopedTrackSettings.audio[id] ?? AudioTrackProcessing()
    profile.delay = min(5, max(-5, value))
    scopedTrackSettings.audio[id] = profile
    if !refreshTrackProcessing(.audio, audioRollback: old.audio) { scopedTrackSettings = old }
    postNotification(.iinaTrackSettingsChanged)
  }
  func scopedAudioEQ() -> [Double] {
    let id = scopedTrackSettings.target(.audioEQ)
    if id != 0 { return scopedTrackSettings.audio[id]?.gains ?? Array(repeating: 0, count: 10) }
    guard let filter = info.audioEqFilter,
          let text = Regex("\\[(.+?)\\]").captures(in: filter.stringFormat)[at: 1] else { return Array(repeating: 0, count: 10) }
    let gains = text.split(separator: ",").map { Double($0.split(separator: "=").last ?? "0") ?? 0 }
    return gains.count == 10 ? gains : Array(repeating: 0, count: 10)
  }
  func setScopedAudioEQ(_ gains: [Double]) {
    guard gains.count == 10, gains.allSatisfy(\.isFinite) else { return }
    let id = scopedTrackSettings.target(.audioEQ)
    if id == 0 { setAudioEq(fromGains: gains); return }
    let old = scopedTrackSettings
    var profile = scopedTrackSettings.audio[id] ?? AudioTrackProcessing()
    profile.gains = gains.map { min(12, max(-12, $0)) }
    scopedTrackSettings.audio[id] = profile
    if !refreshTrackAudioEQ(id: id, previous: old.audio[id]?.gains ?? Array(repeating: 0, count: 10), gains: profile.gains, audioRollback: old.audio) { scopedTrackSettings = old }
    postNotification(.iinaTrackSettingsChanged)
  }
  func scopedVideoSettings(_ group: TrackSettingsGroup = .videoGeometry) -> VideoTrackProcessing {
    let id = scopedTrackSettings.target(group)
    if id != 0 { return scopedTrackSettings.video[id] ?? VideoTrackProcessing() }
    var result = VideoTrackProcessing()
    result.aspect = info.unsureAspect; result.cropDescription = info.unsureCrop; result.rotation = info.rotation
    result.brightness = info.brightness; result.contrast = info.contrast
    result.saturation = info.saturation; result.gamma = info.gamma; result.hue = info.hue
    return result
  }
  @discardableResult
  func updateScopedVideo(_ group: TrackSettingsGroup = .videoGeometry, change: (inout VideoTrackProcessing) -> Void) -> Bool {
    let id = scopedTrackSettings.target(group)
    guard !mainWindow.interactiveMode.isActive else { postNotification(.iinaTrackSettingsChanged); return false }
    guard id > 0, info.videoTracks.contains(where: { $0.id == id }) else { return false }
    mainWindow.prepareVideoTransformWindowReference()
    let old = scopedTrackSettings
    var value = scopedTrackSettings.video[id] ?? VideoTrackProcessing()
    change(&value); scopedTrackSettings.video[id] = value
    let success = refreshTrackProcessing(.video)
    if !success { scopedTrackSettings = old }
    postNotification(.iinaTrackSettingsChanged)
    return success
  }
  func setScopedVideoAspect(_ value: String) {
    guard !mainWindow.interactiveMode.isActive else { postNotification(.iinaTrackSettingsChanged); return }
    if scopedTrackSettings.target(.videoGeometry) == 0 { setVideoAspect(value); return }
    let aspect = Regex.aspect.matches(value) ? value : "Default"
    updateScopedVideo { $0.aspect = aspect }
  }
  func setScopedVideoRotate(_ value: Int) {
    guard !mainWindow.interactiveMode.isActive else { postNotification(.iinaTrackSettingsChanged); return }
    if scopedTrackSettings.target(.videoGeometry) == 0 { setVideoRotate(value); return }
    guard AppData.rotations.contains(value) else { return }
    updateScopedVideo { $0.rotation = value }
  }
  func setScopedCrop(_ value: String) {
    guard !mainWindow.interactiveMode.isActive else { postNotification(.iinaTrackSettingsChanged); return }
    let id = scopedTrackSettings.target(.videoGeometry)
    if id == 0 { setCrop(fromString: value); return }
    guard let track = info.videoTracks.first(where: { $0.id == id }),
          let width = track.demuxW, let height = track.demuxH else { return }
    if let aspect = Aspect(string: value) {
      let pixelAspect = max(0.000001, track.demuxPixelAspect ?? 1)
      let pixelCrop = Aspect(size: NSSize(width: aspect.value / pixelAspect, height: 1))
      let size = NSSize(width: width, height: height).crop(withAspect: pixelCrop)
      let w = max(1, min(width, Int(size.width))), h = max(1, min(height, Int(size.height)))
      updateScopedVideo { $0.crop = TrackVideoCrop(x: (width-w)/2, y: (height-h)/2, width: w, height: h); $0.cropDescription = value }
    } else { updateScopedVideo { $0.crop = nil; $0.cropDescription = "None" } }
  }
  func setScopedVideoEqualizer(_ type: VideoEqualizerType, value: Int) {
    guard !mainWindow.interactiveMode.isActive else { postNotification(.iinaTrackSettingsChanged); return }
    if scopedTrackSettings.target(.videoColor) == 0 { setVideoEqualizer(forOption: type, value: value); return }
    let value = min(100, max(-100, value))
    updateScopedVideo(.videoColor) {
      switch type {
      case .brightness: $0.brightness = value
      case .contrast: $0.contrast = value
      case .saturation: $0.saturation = value
      case .gamma: $0.gamma = value
      case .hue: $0.hue = value
      }
    }
  }
  func resetTrackSettings(_ group: TrackSettingsGroup, allTracks: Bool = false) {
    guard group.isAudio || !mainWindow.interactiveMode.isActive else { return }
    let previous = scopedTrackSettings
    let trackID: Int? = allTracks ? nil : scopedTrackSettings.target(group)
    let audioProfiles = previous.audio.filter { trackID == nil || $0.key == trackID }
    if allTracks || trackID != 0 {
      if group == .audioEQ, !neutralizeTrackAudioEQ(audioProfiles) { return }
      scopedTrackSettings.reset(group, trackID: trackID)
      guard refreshTrackProcessing(group.isAudio ? .audio : .video, audioRollback: previous.audio) else {
        scopedTrackSettings = previous
        if group == .audioEQ { _ = neutralizeTrackAudioEQ(audioProfiles, restoring: true) }
        postNotification(.iinaTrackSettingsChanged); return
      }
    }
    guard allTracks || trackID == 0 else { postNotification(.iinaTrackSettingsChanged); return }
    switch group {
    case .audioDelay: setAudioDelay(0)
    case .audioEQ: setAudioEq(fromGains: Array(repeating: 0, count: 10))
    case .videoGeometry: setVideoAspect("Default"); removeCropFilter(); setVideoRotate(0)
    case .videoColor:
      // All-tracks reset includes Output; local Output reset retains source profiles.
      if mpv.getFilters(MPVProperty.vf).contains(where: { $0.label == "lyina_lut" }) {
        guard removeVideoFilter("@lyina_lut") else {
          scopedTrackSettings = previous
          _ = refreshTrackProcessing(.video)
          postNotification(.iinaTrackSettingsChanged)
          return
        }
      }
      for option in [VideoEqualizerType.brightness, .contrast, .saturation, .gamma, .hue] { setVideoEqualizer(forOption: option, value: 0) }
    }
    postNotification(.iinaTrackSettingsChanged)
  }
}

/// Temporary source-only overrides must be restored when the editor exits.
struct ScopedTrackCropPreview {
  let id: Int
  let activeVideo: [Int]
  let order: [Int]
  let geometry: CropVideoGeometry
  let originalTrack: VideoTrackProcessing
  let masterVF: String
  let masterAspect: String
  let masterRotation: String
  let masterCrop: MPVFilter?
  let masterCropDescription: String
  let masterColors: [(PlayerCore.VideoEqualizerType, Int)]
  var filter: MPVFilter? {
    guard let crop = originalTrack.crop else { return nil }
    return MPVFilter.crop(w: crop.width, h: crop.height, x: crop.x, y: crop.y, exact: true)
  }
}

extension PlayerCore {
  func openScopedCustomCrop() {
    mainWindow.prepareVideoTransformWindowReference()
    let id = scopedTrackSettings.target(.videoGeometry)
    guard id != 0 else { mainWindow.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true); return }
    guard !mainWindow.interactiveMode.isActive, scopedCropPreview == nil,
          mainWindow.pipStatus == .notInPIP,
          let track = info.videoTracks.first(where: { $0.id == id }),
          let w = track.demuxW, let h = track.demuxH, w > 0, h > 0 else { return }
    let active = info.activeTrackIDs(.video)
    var ordered = info.videoTrackOrder.filter { active.contains($0) }
    ordered.append(contentsOf: active.sorted().filter { !ordered.contains($0) })
    scopedCropPreview = ScopedTrackCropPreview(id: id, activeVideo: ordered, order: info.videoTrackOrder,
      geometry: CropVideoGeometry(sourceSize: NSSize(width: w, height: h),
        displaySize: NSSize(width: Double(w) * (track.demuxPixelAspect ?? 1), height: Double(h)), rotation: 0),
      originalTrack: scopedTrackSettings.video[id] ?? VideoTrackProcessing(),
      masterVF: mpv.getString(MPVProperty.vf) ?? "", masterAspect: mpv.getString(MPVOption.Video.videoAspectOverride) ?? "-1",
      masterRotation: mpv.getString(MPVOption.Video.videoRotate) ?? "0", masterCrop: info.cropFilter,
      masterCropDescription: info.unsureCrop,
      masterColors: [(.brightness, info.brightness), (.contrast, info.contrast), (.saturation, info.saturation), (.gamma, info.gamma), (.hue, info.hue)])
    // Source-space coordinates must not include output or layer transformations.
    prepareScopedCropPreview()
    guard refreshTrackProcessing(.video) else { finishScopedCustomCrop(); return }
    mainWindow.interactiveMode.enter(mode: .crop, selectWholeVideoByDefault: true)
    if !mainWindow.interactiveMode.isActive { finishScopedCustomCrop() }
  }
  private func prepareScopedCropPreview() {
    mpv.setString(MPVProperty.vf, "")
    info.cropFilter = nil
    mpv.setString(MPVOption.Video.videoAspectOverride, "-1")
    mpv.setString(MPVOption.Video.videoRotate, "no")
    for option in [VideoEqualizerType.brightness, .contrast, .saturation, .gamma, .hue] { setVideoEqualizer(forOption: option, value: 0) }
  }
  @discardableResult
  func finishScopedCustomCrop(crop: TrackVideoCrop? = nil, applying: Bool = false, restoringSelection: Bool = true) -> Bool {
    guard let preview = scopedCropPreview else { return false }
    scopedCropPreview = nil
    let previous = scopedTrackSettings.video[preview.id]
    if applying {
      var profile = scopedTrackSettings.video[preview.id] ?? preview.originalTrack; profile.crop = crop
      profile.cropDescription = crop == nil ? "None" : "Custom"
      scopedTrackSettings.video[preview.id] = profile
    }
    mpv.setString(MPVOption.Video.videoAspectOverride, preview.masterAspect)
    mpv.setString(MPVOption.Video.videoRotate, preview.masterRotation)
    mpv.setString(MPVProperty.vf, preview.masterVF)
    info.cropFilter = preview.masterCrop; info.unsureCrop = preview.masterCropDescription
    for (option, value) in preview.masterColors { setVideoEqualizer(forOption: option, value: value) }
    info.videoTrackOrder = preview.order
    if restoringSelection && !refreshTrackProcessing(.video, videoOverride: preview.activeVideo) {
      scopedTrackSettings.video[preview.id] = previous
      if applying {
        // Keep the raw preview and the live editor's unsaved rectangle for retry.
        scopedCropPreview = preview
        prepareScopedCropPreview()
        _ = refreshTrackProcessing(.video)
      } else {
        _ = refreshTrackProcessing(.video, videoOverride: preview.activeVideo)
      }
      postNotification(.iinaTrackSettingsChanged)
      return false
    }
    postNotification(.iinaTrackSettingsChanged)
    return true
  }
}
