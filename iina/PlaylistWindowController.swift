import Cocoa

/// Moves one playlist view between the player's content area and a standalone window.
final class PlaylistWindowController: NSWindowController, NSWindowDelegate {
  private enum Mode: Int { case embedded, floating }
  unowned let player: PlayerCore
  private let prefObserver = Preference.Observer()
  private let presentationButton = NSButton()
  private var presentationMenuItem: NSMenuItem!
  private var panel: NSVisualEffectView!
  private var menuHandler: MainMenuActionHandler!
  private var mode = Mode(rawValue: UserDefaults.standard.integer(forKey: "playlistWindowMode")) ?? .embedded
  private var freeFrame: NSRect?
  private var wantsVisible = false
  private var changingPresentation = false
  private(set) var videoContentView: NSView?
  private var isEmbedded = false
  private var videoTrailingConstraint: NSLayoutConstraint!
  private var embeddingConstraints: [NSLayoutConstraint] = []
  private var headerTopConstraint: NSLayoutConstraint!
  private var savedAspectRatio = NSSize.zero
  private var savedMinSize = NSSize.zero
  private let panelWidth: CGFloat = 340
  var embeddedWidth: CGFloat { isEmbedded ? panelWidth : 0 }
  var embeddedPanelView: NSView? { isEmbedded ? panel : nil }

  init(player: PlayerCore) {
    self.player = player
    super.init(window: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func text(_ key: String, _ fallback: String) -> String {
    NSLocalizedString(key, value: fallback, comment: "Playlist window")
  }

  /// Install before creating the video renderer; never detach its view during presentation changes.
  func installVideoHost() {
    guard videoContentView == nil, let parent = player.mainWindow.window,
          let content = parent.contentView else { return }
    let host = NSView(frame: content.frame)
    parent.contentView = host
    videoContentView = content
    content.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(content)
    videoTrailingConstraint = content.trailingAnchor.constraint(equalTo: host.trailingAnchor)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      content.topAnchor.constraint(equalTo: host.topAnchor),
      content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
      videoTrailingConstraint
    ])
    host.layoutSubtreeIfNeeded()
  }

  override func loadWindow() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 480),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = text("playlist.window_title", "Playlist")
    window.minSize = NSSize(width: 320, height: 240)
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.collectionBehavior = [.fullScreenNone]
    self.window = window

    panel = NSVisualEffectView()
    panel.material = .popover
    panel.blendingMode = .withinWindow
    panel.state = .active
    let pane = SidebarPlaylistPane(player: player, standalone: true)
    pane.translatesAutoresizingMaskIntoConstraints = false
    presentationButton.isBordered = false
    presentationButton.imagePosition = .imageOnly
    presentationButton.contentTintColor = .secondaryLabelColor
    presentationButton.target = self
    presentationButton.action = #selector(togglePresentation(_:))
    presentationButton.setAccessibilityIdentifier("playlist.togglePresentation")
    let menu = NSMenu()
    presentationMenuItem = NSMenuItem(title: "", action: #selector(togglePresentation(_:)), keyEquivalent: "")
    presentationMenuItem.target = self
    menu.addItem(presentationMenuItem)
    panel.menu = menu
    let title = NSTextField(labelWithString: window.title)
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    let controls = UIHelper.shared.hStack(spacing: 8, title, UIHelper.shared.flexibleSpace(), presentationButton)
    panel.addSubview(controls)
    panel.addSubview(pane)
    controls.padding(.horizontal(12))
    headerTopConstraint = controls.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12)
    headerTopConstraint.isActive = true
    pane.padding(.horizontal, .bottom).spacing(.top(4), to: controls)
    window.contentView = panel
    window.delegate = self
    if let saved = UserDefaults.standard.string(forKey: "playlistWindowFreeFrame") {
      let frame = NSRectFromString(saved)
      if frame.width >= 320, frame.height >= 240 { freeFrame = frame }
    }
    menuHandler = MainMenuActionHandler(playerCore: player)
    let responder = window.nextResponder
    window.nextResponder = menuHandler
    menuHandler.nextResponder = responder
    nextResponder = player.mainWindow
    prefObserver.add(.themeMaterial, runNow: true) { [weak self] _ in
      let theme: Preference.Theme = Preference.enum(for: .themeMaterial)
      self?.window?.appearance = NSAppearance(iinaTheme: theme)
    }
    updateControls()
  }

  var isVisible: Bool {
    isEmbedded ? player.mainWindow.window?.isVisible == true : window?.isVisible == true
  }

  func toggle() {
    if isVisible { hide() } else { show() }
  }

  func show() {
    guard !changingPresentation else { return }
    if window == nil { loadWindow() }
    wantsVisible = true
    if mode == .embedded, embed() {
      player.mainWindow.window?.makeKeyAndOrderFront(nil)
    } else {
      mode = .floating
      showFloating()
    }
    updateControls()
    notifyVisibilityChanged()
  }

  func hide() {
    wantsVisible = false
    unembed()
    window?.orderOut(nil)
    notifyVisibilityChanged()
  }

  /// Music mode retains its existing embedded playlist. Native full screen keeps this pane in place.
  func suspend() {
    guard mode == .embedded else { return }
    unembed()
    window?.orderOut(nil)
    notifyVisibilityChanged()
  }

  func restoreIfNeeded() {
    guard wantsVisible, mode == .embedded, !player.isInMiniPlayer else { return }
    _ = embed()
    notifyVisibilityChanged()
  }

  private func notifyVisibilityChanged() {
    NotificationCenter.default.post(name: .iinaSidebarStatusChanged, object: nil)
  }

  private func updateControls() {
    let description = mode == .embedded
      ? text("playlist.detach", "Detach Playlist")
      : text("playlist.attach", "Attach Playlist to Player")
    presentationButton.image = NSImage(systemSymbolName: mode == .embedded ? "arrow.up.right.square" : "rectangle.split.2x1",
                                       accessibilityDescription: description)
    presentationButton.toolTip = description
    presentationButton.setAccessibilityLabel(description)
    presentationMenuItem.title = description
    UserDefaults.standard.set(mode.rawValue, forKey: "playlistWindowMode")
  }

  @objc private func togglePresentation(_ sender: Any?) {
    guard !changingPresentation else { return }
    if case .animating = player.mainWindow.fsState { return }
    if mode == .embedded {
      unembed()
      mode = .floating
      showFloating()
    } else {
      saveFreeFrame()
      if embed() { mode = .embedded }
    }
    updateControls()
    notifyVisibilityChanged()
  }

  private func showFloating() {
    guard let window else { return }
    changingPresentation = true
    headerTopConstraint.constant = 12
    panel.removeFromSuperview()
    panel.translatesAutoresizingMaskIntoConstraints = true
    window.contentView = panel
    if let frame = freeFrame, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
      window.setFrame(frame, display: true)
    } else {
      window.setContentSize(NSSize(width: panelWidth, height: 480))
      window.center()
    }
    changingPresentation = false
    window.makeKeyAndOrderFront(nil)
    saveFreeFrame()
  }

  private func saveFreeFrame() {
    guard !changingPresentation, mode == .floating, let window, window.isVisible else { return }
    freeFrame = window.frame
    UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "playlistWindowFreeFrame")
  }

  @discardableResult private func embed() -> Bool {
    if isEmbedded { return true }
    guard !changingPresentation, let parent = player.mainWindow.window,
          let host = parent.contentView, videoContentView != nil, panel != nil else { return false }
    let fullscreen = player.mainWindow.fsState.isFullscreen
    var frame = parent.frame
    if !fullscreen {
      // Keep the video area's size and position. Never shrink it to make room for the list.
      guard let screen = parent.screen, frame.maxX + panelWidth <= screen.visibleFrame.maxX else {
        player.sendOSD(.custom(text("playlist.embed_no_space", "Move the player left or use Free window mode to keep the video area unchanged.")))
        return false
      }
      frame.size.width += panelWidth
    }
    changingPresentation = true
    headerTopConstraint.constant = max(12, parent.frame.height - parent.contentLayoutRect.height + 8)
    window?.orderOut(nil)
    window?.contentView = NSView()
    panel.removeFromSuperview()
    isEmbedded = true
    savedAspectRatio = parent.aspectRatio
    savedMinSize = parent.minSize
    videoTrailingConstraint.constant = -panelWidth
    panel.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(panel)
    embeddingConstraints = [
      panel.topAnchor.constraint(equalTo: host.topAnchor),
      panel.bottomAnchor.constraint(equalTo: host.bottomAnchor),
      panel.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      panel.widthAnchor.constraint(equalToConstant: panelWidth)
    ]
    NSLayoutConstraint.activate(embeddingConstraints)
    parent.aspectRatio = .zero
    parent.minSize = NSSize(width: savedMinSize.width + panelWidth, height: savedMinSize.height)
    if !fullscreen { parent.setFrame(frame, display: true) }
    else if var prior = player.mainWindow.fsState.priorWindowedFrame {
      prior.size.width += panelWidth
      player.mainWindow.fsState.priorWindowedFrame = prior
    }
    host.layoutSubtreeIfNeeded()
    changingPresentation = false
    return true
  }

  private func unembed() {
    guard isEmbedded, !changingPresentation, let parent = player.mainWindow.window else { return }
    changingPresentation = true
    let fullscreen = player.mainWindow.fsState.isFullscreen
    var frame = parent.frame
    frame.size.width -= panelWidth
    NSLayoutConstraint.deactivate(embeddingConstraints)
    embeddingConstraints.removeAll()
    panel.removeFromSuperview()
    isEmbedded = false
    videoTrailingConstraint.constant = 0
    parent.minSize = savedMinSize
    if !fullscreen { parent.setFrame(frame, display: true) }
    else if var prior = player.mainWindow.fsState.priorWindowedFrame {
      prior.size.width -= panelWidth
      player.mainWindow.fsState.priorWindowedFrame = prior
    }
    let (width, height) = player.videoSizeForDisplay
    parent.aspectRatio = (Preference.bool(for: .lockPlayerWindowSize) || Preference.unlockWindowAspectRatio) ? .zero
      : (width > 0 && height > 0 ? NSSize(width: width, height: height) : savedAspectRatio)
    parent.contentView?.layoutSubtreeIfNeeded()
    changingPresentation = false
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hide()
    return false
  }

  func windowDidMove(_ notification: Notification) { saveFreeFrame() }
  func windowDidResize(_ notification: Notification) { saveFreeFrame() }
  func windowDidBecomeKey(_ notification: Notification) { PlayerCore.lastActive = player }
}
