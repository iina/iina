// Copyright © 2026 IINA contributors. Licensed under GPLv3.

import AppKit
import Combine
import GroupActivities

final class SharePlayManager: NSObject {
  static let shared = SharePlayManager()
  private var listener: Task<Void, Never>?
  private var activation: Task<Void, Never>?
  private var session: GroupSession<IINAWatchActivity>?
  private var subscriptions = Set<AnyCancellable>()
  private var bridge: SharePlayCoordinator?
  private weak var player: PlayerCore?
  private var proposedPlayer: PlayerCore?
  private var proposedMedia: SharePlayMedia?
  private var proposedURL: URL?
  private var selectedURL: URL?
  private var selectionDeadline = 0.0
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var warning: String?
  private var panel: NSPanel?
  private var statusLabel: NSTextField?
  private var buttons: [String: NSButton] = [:]

  func start() {
    guard listener == nil else { return }
    listener = Task { @MainActor [weak self] in
      for await session in IINAWatchActivity.sessions() {
        guard !Task.isCancelled, let self else { session.leave(); return }
        self.receive(session)
      }
    }
    let center = NSWorkspace.shared.notificationCenter
    observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
      self?.player?.sharePlayPlayback?.suspend(.system)
    })
    observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.player?.sharePlayPlayback?.resume(.system)
    })
  }

  func show() {
    if panel == nil { makePanel() }
    refresh()
    panel?.makeKeyAndOrderFront(nil)
  }

  func shutdown() {
    listener?.cancel(); listener = nil
    activation?.cancel(); activation = nil
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observers.removeAll()
    leave()
  }

  @objc private func startSharing() {
    guard session == nil, activation == nil else { return }
    let candidate = PlayerCore.active
    let state = candidate.sharePlaySnapshot
    guard state.loaded, state.seekable, state.duration.isFinite, state.duration > 0, let url = state.url else {
      showFailure("shareplay.open_video"); return
    }
    let title = String(url.lastPathComponent.prefix(512))
    let media = SharePlayMedia(id: UUID(), title: title.isEmpty ? NSLocalizedString("shareplay.video", comment: "") : title,
                               duration: state.duration)
    proposedMedia = media
    proposedPlayer = candidate
    proposedURL = url
    warning = nil
    activation = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.activation = nil; self.refresh() }
      let activity = IINAWatchActivity(media: media)
      switch await activity.prepareForActivation() {
      case .activationPreferred:
        guard !Task.isCancelled else { return }
        do {
          let activated = try await activity.activate()
          if !activated { self.showFailure("shareplay.activation_failed") }
        } catch {
          if !Task.isCancelled { self.showFailure("shareplay.activation_failed", detail: error.localizedDescription) }
        }
      case .activationDisabled: self.showFailure("shareplay.facetime_required")
      case .cancelled: self.proposedMedia = nil; self.proposedPlayer = nil; self.proposedURL = nil
      @unknown default: self.showFailure("shareplay.activation_failed")
      }
    }
    refresh()
  }

  private func receive(_ newSession: GroupSession<IINAWatchActivity>) {
    guard newSession.activity.media.isValid else { newSession.leave(); showFailure("shareplay.invalid_media"); return }
    if session != nil { leave() }
    session = newSession
    warning = nil
    let id = newSession.id
    let media = newSession.activity.media
    newSession.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
      guard let self, self.session?.id == id else { return }
      if case .invalidated = state { self.cleanUp(); self.warning = NSLocalizedString("shareplay.ended", comment: "") }
      self.refresh()
    }.store(in: &subscriptions)
    newSession.$activeParticipants.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
    newSession.$activity.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] activity in
      guard let self, self.session?.id == id else { return }
      if activity.media != media {
        self.leave(); self.showFailure("shareplay.media_changed")
      }
    }.store(in: &subscriptions)
    timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    RunLoop.main.add(timer!, forMode: .common)
    if proposedMedia?.id == newSession.activity.media.id, let candidate = proposedPlayer,
       candidate.sharePlaySnapshot.loaded, candidate.info.currentURL == proposedURL {
      attach(candidate)
    } else {
      proposedPlayer = nil
      proposedMedia = nil
      show()
    }
  }

  @objc private func useCurrent() {
    guard session != nil, player == nil else { return }
    confirm(PlayerCore.active)
  }

  private func confirm(_ candidate: PlayerCore) {
    let state = candidate.sharePlaySnapshot
    guard state.loaded, state.seekable else { showFailure("shareplay.open_video"); return }
    guard let media = session?.activity.media, media.matches(duration: state.duration) else {
      showFailure("shareplay.duration_mismatch"); return
    }
    let id = session?.id
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("shareplay.confirm_title", comment: "")
    alert.informativeText = String(format: NSLocalizedString("shareplay.confirm_media", comment: ""), media.title)
    alert.addButton(withTitle: NSLocalizedString("shareplay.join", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("shareplay.cancel", comment: ""))
    if alert.runModal() == .alertFirstButtonReturn, session?.id == id { attach(candidate) }
  }

  @objc private func chooseFile() {
    guard session != nil, player == nil else { return }
    let id = session?.id
    let picker = NSOpenPanel()
    picker.canChooseDirectories = false
    picker.allowsMultipleSelection = false
    picker.message = NSLocalizedString("shareplay.choose_message", comment: "")
    picker.begin { [weak self] result in
      guard let self, result == .OK, let url = picker.url, self.session?.id == id else { return }
      let candidate = PlayerCore.newPlayerCore
      self.selectedURL = url
      self.selectionDeadline = SharePlayCoordinator.hostTime + 15
      self.proposedPlayer = candidate
      candidate.openURL(url, shouldAutoLoad: false)
      self.refresh()
    }
  }

  private func tick() {
    if selectedURL != nil, SharePlayCoordinator.hostTime >= selectionDeadline {
      selectedURL = nil
      proposedPlayer = nil
      showFailure("shareplay.not_ready")
    }
    if let selectedURL, let candidate = proposedPlayer, candidate.info.state.loaded {
      self.selectedURL = nil
      guard candidate.info.currentURL == selectedURL, let media = session?.activity.media,
            media.matches(duration: candidate.sharePlaySnapshot.duration), candidate.sharePlaySnapshot.seekable else {
        proposedPlayer = nil
        showFailure("shareplay.duration_mismatch"); return
      }
      // Explicit confirmation is required even if file duration matches.
      confirm(candidate)
    }
    player?.sharePlayPlayback?.tick()
  }

  private func attach(_ candidate: PlayerCore) {
    guard let session, candidate.sharePlayPlayback == nil, candidate.sharePlaySnapshot.seekable,
          session.activity.media.matches(duration: candidate.sharePlaySnapshot.duration) else {
      showFailure("shareplay.open_video"); return
    }
    let initialState = candidate.sharePlaySnapshot
    guard candidate.prepareForSharePlay() else { showFailure("shareplay.not_ready"); return }
    let bridge = SharePlayCoordinator()
    let playback = SharePlayPlayback(media: session.activity.media, player: candidate,
                                    coordinator: bridge, clock: { SharePlayCoordinator.hostTime })
    bridge.playback = playback
    self.bridge = bridge
    player = candidate
    candidate.sharePlayPlayback = playback
    playback.onChange = { [weak self] in self?.refresh() }
    playback.onFailure = { [weak self] key in self?.showFailure(key) }
    guard bridge.connect(to: session, position: candidate.sharePlaySnapshot.position, rate: initialState.paused ? 0 : initialState.speed) else {
      leave(); showFailure("shareplay.activation_failed"); return
    }
    session.join()
    proposedPlayer = nil
    proposedMedia = nil
    proposedURL = nil
    warning = nil
    refresh()
  }

  @objc func leave() {
    let previous = session
    cleanUp()
    previous?.leave()
    refresh()
  }

  @objc private func endForEveryone() {
    session?.end()
    cleanUp()
    refresh()
  }

  @objc private func rejoin() {
    warning = nil
    player?.sharePlayPlayback?.rejoin()
    refresh()
  }

  func playerStopped(_ stopped: PlayerCore) {
    if player === stopped { leave() }
  }

  private func cleanUp() {
    timer?.invalidate(); timer = nil
    subscriptions.removeAll()
    player?.sharePlayPlayback?.stop()
    player?.sharePlayPlayback = nil
    bridge?.disconnect()
    bridge = nil
    player?.restoreAfterSharePlay()
    player = nil
    session = nil
    proposedPlayer = nil
    proposedMedia = nil
    proposedURL = nil
    selectedURL = nil
    warning = nil
  }

  private func showFailure(_ key: String, detail: String? = nil) {
    let message = NSLocalizedString(key, comment: "") + (detail.map { "\n" + $0 } ?? "")
    guard warning != message else { return }
    warning = message
    show()
  }

  private func makePanel() {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 310),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    panel.title = "SharePlay"
    panel.isReleasedWhenClosed = false
    let status = NSTextField(wrappingLabelWithString: "")
    status.font = .systemFont(ofSize: 13)
    status.setAccessibilityIdentifier("shareplay.status")
    status.preferredMaxLayoutWidth = 492
    statusLabel = status
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(status)
    for row: [(String, Selector)] in [
      [("shareplay.start", #selector(startSharing)), ("shareplay.use_current", #selector(useCurrent)), ("shareplay.choose", #selector(chooseFile))],
      [("shareplay.rejoin", #selector(rejoin)), ("shareplay.leave", #selector(leave)), ("shareplay.end", #selector(endForEveryone))]
    ] {
      let horizontal = NSStackView()
      horizontal.spacing = 8
      for (key, selector) in row {
        let button = NSButton(title: NSLocalizedString(key, comment: ""), target: self, action: selector)
        button.setAccessibilityIdentifier(key)
        buttons[key] = button
        horizontal.addArrangedSubview(button)
      }
      stack.addArrangedSubview(horizontal)
    }
    panel.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: panel.contentView!.bottomAnchor, constant: -24)
    ])
    panel.center()
    self.panel = panel
  }

  private func refresh() {
    let attached = player?.sharePlayPlayback != nil
    let suspended = !(player?.sharePlayPlayback?.suspensions.isEmpty ?? true)
    let status: String
    if let session {
      if attached {
        let key = suspended ? "shareplay.suspended" : "shareplay.connected"
        status = session.activity.media.title + "\n" + String(format: NSLocalizedString(key, comment: ""), session.activeParticipants.count)
      } else { status = String(format: NSLocalizedString("shareplay.select_media", comment: ""), session.activity.media.title) }
    } else { status = NSLocalizedString("shareplay.introduction", comment: "") }
    statusLabel?.stringValue = status + (warning.map { "\n\n" + $0 } ?? "")
    buttons["shareplay.start"]?.isEnabled = session == nil && activation == nil
    buttons["shareplay.use_current"]?.isEnabled = session != nil && !attached
    buttons["shareplay.choose"]?.isEnabled = session != nil && !attached && selectedURL == nil
    buttons["shareplay.rejoin"]?.isEnabled = attached && suspended
    buttons["shareplay.leave"]?.isEnabled = session != nil
    buttons["shareplay.end"]?.isEnabled = session != nil
  }
}
