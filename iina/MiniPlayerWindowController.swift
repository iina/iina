//
//  MiniPlayerWindowController.swift
//  iina
//
//  Created by lhc on 30/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let DefaultPlaylistHeight: CGFloat = 300
fileprivate let AutoHidePlaylistThreshold: CGFloat = 200
fileprivate let AnimationDurationShowControl: TimeInterval = 0.2


fileprivate extension LayoutValue {
  static let topPadding = LayoutValue(8, 4)
  static let bottomPadding = LayoutValue(10, 8)
  static let controlTopPadding = LayoutValue(4, 0)
  static let titleSliderSpacing = LayoutValue(8, 6)
}


class MiniPlayerWindowController: PlayerWindowController, NSPopoverDelegate {
  override var windowNibName: NSNib.Name {
    return NSNib.Name("MiniPlayerWindowController")
  }

  override var videoView: VideoView {
    return player.mainWindow.videoView
  }

  var backgroundView: NSVisualEffectView!
  var closeButtonView: NSView!
  var closeButtonBackground: NSVisualEffectView!
  var closeButton: NSButton!
  var closeButtonSizeConstraint: NSLayoutConstraint!
  var closeButtonSpacingConstraint: NSLayoutConstraint!
  var backButton: NSButton!
  var videoWrapperView: NSView!
  var videoWrapperViewBottomConstraint: NSLayoutConstraint!
  var controlViewTopConstraint: NSLayoutConstraint!
  var playlistWrapperView: NSVisualEffectView!
  var mediaInfoView: NSView!
  var controlView: NSView!
  var titleLabel: ScrollingTextField!
  var titleLabelTopConstraint: NSLayoutConstraint!
  var artistAlbumLabel: ScrollingTextField!
  var volumeLabel: NSTextField!
  var volumeControlContainer: NSView!
  var volumeControlBackground: NSVisualEffectView!
  var volumeContainerTrailingConstraint: NSLayoutConstraint!
  var defaultAlbumArt: NSView!
  var togglePlaylistButton: NSButton!
  var toggleAlbumArtButton: NSButton!

  var isPlaylistVisible = false
  var isVideoVisible = true

  var videoViewAspectConstraint: NSLayoutConstraint?

  var hideVolumeControlTask: DispatchWorkItem?

  var playlistView: PlaylistViewController {
    return player.mainWindow.sidebars.playlistView
  }

  override var mouseActionDisabledViews: [NSView?] {[backgroundView, playlistWrapperView]}

  var isShowingVolumeControl = false
  var volumeControlViews: [NSView?] {
    [volumeControlBackground, volumeLabel, volumeSlider]
  }

  // MARK: - Initialization

  override func windowDidLoad() {
    // need to create before since super calls updateVolume()
    self.volumeLabel = NSTextField(labelWithString: "50")
    volumeLabel.translatesAutoresizingMaskIntoConstraints = false

    super.windowDidLoad()

    guard let window, let cv = window.contentView else { return }

    window.isMovableByWindowBackground = true
    window.titleVisibility = .hidden
    window.delegate = self
    ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindow.ButtonType]).forEach {
      let button = window.standardWindowButton($0)
      button?.isHidden = true
      // > The close button, being obscured by standard buttons, won't respond to clicking when window is inactive.
      // > i.e. clicking close button (or any position located in the standard buttons's frame) will only order the window
      // > to front, but it never becomes key or main window.
      // > Removing the button directly will also work but it causes crash on 10.12-, so for the sake of safety we don't use that way for now.
      // > Not a perfect solution. It should respond to the first click.
      // Update: Testing switching to calling removeFromSuperview did not work when running under
      // macOS Sequoia 15.7.2. The button was still present in the title bar. Possibly in response
      // to past crashes Apple updated the title bar implementation to ignore certain attempts to
      // alter the title bar. Continuing to set the frame size to zero so mouse events reach our
      // custom close button.
      button?.frame.size = .zero
    }

    // MARK: - video wrapper view

    self.videoWrapperView = NSView()
    videoWrapperView.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(videoWrapperView)
    videoWrapperView.padding(.horizontal)
    let videoWrapperTopConstraint = videoWrapperView.topAnchor.constraint(equalTo: cv.topAnchor)
    videoWrapperTopConstraint.priority = .defaultHigh
    videoWrapperTopConstraint.isActive = true

    self.defaultAlbumArt = NSView()
    defaultAlbumArt.translatesAutoresizingMaskIntoConstraints = false
    defaultAlbumArt.isHidden = false
    defaultAlbumArt.wantsLayer = true
    defaultAlbumArt.layer?.contents = #imageLiteral(resourceName: "default-album-art")
    videoWrapperView.addSubview(defaultAlbumArt)
    defaultAlbumArt.padding(.top, .leading, .trailing)
    let videoWrapperShrinkConstraint = videoWrapperView.bottomAnchor.constraint(equalTo: defaultAlbumArt.bottomAnchor)
    videoWrapperShrinkConstraint.priority = NSLayoutConstraint.Priority(250)
    videoWrapperShrinkConstraint.isActive = true
    defaultAlbumArt.widthAnchor.constraint(equalTo: defaultAlbumArt.heightAnchor).isActive = true

    // background view

    self.backgroundView = NSVisualEffectView()
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.blendingMode = .behindWindow
    backgroundView.material = .underWindowBackground
    backgroundView.state = .active
    cv.addSubview(backgroundView)
    backgroundView.padding(.horizontal, .vertical(greaterThan: 0))
    self.videoWrapperViewBottomConstraint = backgroundView.topAnchor.constraint(equalTo: videoWrapperView.bottomAnchor)
    videoWrapperViewBottomConstraint.isActive = true
    self.controlViewTopConstraint = backgroundView.topAnchor.constraint(equalTo: cv.topAnchor)
    controlViewTopConstraint.isActive = false

    [leftLabel, rightLabel].forEach { label in
      label!.textColor = .secondaryLabelColor
      label!.font = .monospacedDigitFont(for: .mini)
      label!.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
    }

    backgroundView.addSubview(leftLabel)
    leftLabel.alignment = .right
    leftLabel.padding(.leading(6))
    backgroundView.addSubview(rightLabel)
    rightLabel.padding(.trailing(6))
    rightLabel.alignment = .left
    leftLabel.widthAnchor.constraint(equalTo: rightLabel.widthAnchor, multiplier: 1).isActive = true

    backgroundView.addSubview(playSlider)
    playSlider.padding(.bottom(.bottomPadding))
    playSlider.spacing(.leading(6), to: leftLabel)
    leftLabel.center(.y, with: playSlider)
    rightLabel.spacing(.leading(6), to: playSlider)
    rightLabel.center(.y, with: playSlider)

    self.mediaInfoView = NSView()
    mediaInfoView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.addSubview(mediaInfoView)
    mediaInfoView.padding(.top(.topPadding), .horizontal)
      .spacing(.bottom(.titleSliderSpacing), to: playSlider)

    self.titleLabel = ScrollingTextField(labelWithString: "Title")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.alignment = .center
    titleLabel.lineBreakMode = .byTruncatingMiddle
    titleLabel.font = .boldSystemFont(ofSize: 13)
    mediaInfoView.addSubview(titleLabel)
    titleLabel.padding(.horizontal(greaterThan: 24)).center(.x)
    titleLabelTopConstraint = titleLabel.topAnchor.constraint(equalTo: mediaInfoView.topAnchor, constant: 6)
    titleLabelTopConstraint.isActive = true

    self.artistAlbumLabel = ScrollingTextField(labelWithString: "Artist - Album")
    artistAlbumLabel.translatesAutoresizingMaskIntoConstraints = false
    artistAlbumLabel.wantsLayer = true
    artistAlbumLabel.controlSize = .small
    artistAlbumLabel.alignment = .center
    artistAlbumLabel.font = .messageFont(ofSize: 11)
    artistAlbumLabel.textColor = .secondaryLabelColor
    artistAlbumLabel.lineBreakMode = .byClipping
    mediaInfoView.addSubview(artistAlbumLabel)
    artistAlbumLabel.padding(.horizontal(greaterThan: 24), .bottom)
      .center(.x).spacing(.top(4), to: titleLabel)

    self.controlView = NSView()
    controlView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.addSubview(controlView)
    controlView.padding(.horizontal, .top(.controlTopPadding))
      .size(height: 48)

    let prevBtn = NSButton(image: .nextl, target: self, action: #selector(prevBtnAction))
    let nextBtn = NSButton(image: .nextr, target: self, action: #selector(nextBtnAction))

    self.togglePlaylistButton = NSButton(image: .playlist, target: self, action: #selector(togglePlaylist))
    self.toggleAlbumArtButton = NSButton(image: .toggleAlbumArt, target: self, action: #selector(toggleVideoView))

    let iconButtons: [NSButton] = [playButton, prevBtn, nextBtn, togglePlaylistButton, toggleAlbumArtButton]
    iconButtons.forEach { button in
      button.translatesAutoresizingMaskIntoConstraints = false
      button.bezelStyle = .shadowlessSquare
      button.imagePosition = .imageOnly
      button.isBordered = false
      button.imageScaling = .scaleProportionallyUpOrDown
      button.refusesFirstResponder = true
      controlView.addSubview(button)
    }

    playButton.size(width: 28, height: 28)
    nextBtn.size(width: 28, height: 28)
    prevBtn.size(width: 28, height: 28)
    togglePlaylistButton.size(width: 14, height: 14)
    toggleAlbumArtButton.size(width: 14, height: 14)

    // volume popover

    self.volumeControlContainer = NSView()
    volumeControlContainer.translatesAutoresizingMaskIntoConstraints = false
    controlView.addSubview(volumeControlContainer)

    self.volumeControlBackground = NSVisualEffectView()
    volumeControlBackground.translatesAutoresizingMaskIntoConstraints = false
    volumeControlBackground.material = .popover
    volumeControlBackground.blendingMode = .withinWindow
    volumeControlBackground.state = .active
    volumeControlBackground.roundCorners(withRadius: 18)
    volumeControlBackground.wantsLayer = true
    volumeControlBackground.layer?.cornerRadius = 18
    volumeControlBackground.layer?.borderWidth = 1
    volumeControlBackground.layer?.borderColor = NSColor.sidebarContainerBorder.cgColor
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 2
    volumeControlBackground.shadow = shadow
    volumeControlContainer.addSubview(volumeControlBackground)
    volumeControlBackground.padding(.all)

    volumeControlContainer.addSubview(muteButton)
    muteButton.padding(.leading(10)).center(.y)
    self.volumeContainerTrailingConstraint = volumeControlContainer
      .trailingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 10)
    volumeContainerTrailingConstraint.isActive = true

    volumeControlContainer.addSubview(volumeSlider)
    volumeSlider.maxValue = Double(Preference.integer(for: .maxVolume))
    volumeSlider.size(width: 100)
      .padding(.vertical(12), .leading(45))

    volumeLabel.controlSize = .small
    volumeLabel.alignment = .center
    volumeLabel.font = .messageFont(ofSize: 11)
    volumeControlContainer.addSubview(volumeLabel)
    volumeLabel.center(.y)
      .spacing(.leading(8), to: volumeSlider)

    muteButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor).isActive = true
    prevBtn.center(.y, with: playButton)
      .spacing(.leading(20), to: muteButton)
    playButton.padding(.top(12)).center(.x, offset: 2)
      .spacing(.leading(24), to: prevBtn)
    nextBtn.center(.y, with: playButton)
      .spacing(.leading(20), to: playButton)
    togglePlaylistButton.center(.y, with: playButton)
    togglePlaylistButton.spacing(.leading(20), to: nextBtn)
    toggleAlbumArtButton.center(.y, with: togglePlaylistButton)
    toggleAlbumArtButton.spacing(.leading(16), to: togglePlaylistButton)

    // playlist wrapper view

    self.playlistWrapperView = NSVisualEffectView()
    playlistWrapperView.translatesAutoresizingMaskIntoConstraints = false
    playlistWrapperView.blendingMode = .behindWindow
    playlistWrapperView.material = .underWindowBackground
    playlistWrapperView.state = .active
    cv.addSubview(playlistWrapperView)
    playlistWrapperView.size(width: 300)
    playlistWrapperView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
    playlistWrapperView.padding(.horizontal).spacing(.top, to: backgroundView)
    let playlistWrapperBottomConstraint = cv.bottomAnchor.constraint(equalTo: playlistWrapperView.bottomAnchor)
    playlistWrapperBottomConstraint.priority = .defaultLow
    playlistWrapperBottomConstraint.isActive = true

    let playlistSeparator = NSBox()
    playlistSeparator.boxType = .separator
    playlistSeparator.translatesAutoresizingMaskIntoConstraints = false
    playlistWrapperView.addSubview(playlistSeparator)
    playlistSeparator.padding(.leading, .top, .trailing)

    // close button

    self.closeButtonView = NSView()
    closeButtonView.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(closeButtonView)
    closeButtonView.padding(.top(6), .leading(8))

    self.closeButtonBackground = NSVisualEffectView()
    closeButtonBackground.translatesAutoresizingMaskIntoConstraints = false
    closeButtonBackground.blendingMode = .withinWindow
    closeButtonBackground.material = .popover
    closeButtonBackground.state = .active
    closeButtonBackground.clipsToBounds = true
    closeButtonBackground.roundCorners(withRadius: 10)
    closeButtonBackground.wantsLayer = true
    closeButtonBackground.layer?.cornerRadius = 10
    closeButtonView.addSubview(closeButtonBackground)
    closeButtonBackground.padding(.all)

    self.closeButton = NSButton()
    closeButton.image = .sf("xmark.circle.fill")
    closeButton.action = #selector(self.close)
    closeButton.target = self
    self.backButton = NSButton()
    backButton.image = .sf("arrow.uturn.backward.circle.fill")
    backButton.action = #selector(self.backBtnAction(_:))
    backButton.target = self
    backButton.toolTip = NSLocalizedString("mini_player.back", comment: "back")
    closeButton.toolTip = NSLocalizedString("mini_player.close", comment: "close")
    [closeButton, backButton].forEach { button in
      button!.translatesAutoresizingMaskIntoConstraints = false
      button!.bezelStyle = .smallSquare
      button!.isBordered = false
      button!.imagePosition = .imageOnly
      button!.refusesFirstResponder = true
      button!.widthAnchor.constraint(equalTo: button!.heightAnchor, multiplier: 1).isActive = true
      closeButtonBackground.addSubview(button!)
    }

    backButton.widthAnchor.constraint(equalTo: closeButton.widthAnchor, multiplier: 1).isActive = true
    closeButtonSizeConstraint = closeButton.widthAnchor.constraint(equalToConstant: 12)
    closeButtonSizeConstraint.isActive = true
    closeButton.padding(.top(3), .horizontal(3))
    backButton.padding(.bottom(3), .horizontal(3))
    closeButtonSpacingConstraint = backButton.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4)
    closeButtonSpacingConstraint.isActive = true

    setToInitialWindowSize(display: false, animate: false)

    // tracking area
    let trackingView = NSView()
    trackingView.translatesAutoresizingMaskIntoConstraints = false
    cv.addSubview(trackingView, positioned: .below, relativeTo: nil)
    trackingView.padding(.horizontal)
      .padding(.top, from: videoWrapperView)
      .padding(.bottom, from: backgroundView)
    trackingView.addTrackingArea(NSTrackingArea(
      rect: trackingView.bounds,
      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
      owner: self, userInfo: nil
    ))

    // hide controls initially
    closeButtonView.alphaValue = 0
    controlView.alphaValue = 0
    volumeControlViews.forEach { $0?.isHidden = true }

    // tool tips
    togglePlaylistButton.toolTip = Preference.ToolBarButton.playlist.localizedDescription()
    toggleAlbumArtButton.toolTip = NSLocalizedString("mini_player.album_art", comment: "album_art")
    muteButton.toolTip = NSLocalizedString("mini_player.volume", comment: "volume")

    if Preference.bool(for: .alwaysFloatOnTop) {
      setWindowFloatingOnTop(true)
    }

    updateCloseButton()
  }

  // MARK: - Mouse / Trackpad events

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(window)
    super.mouseDown(with: event)
  }

  override func scrollWheel(with event: NSEvent) {
    if event.inAnyOf([playSlider]) && playSlider.isEnabled {
      seekOverride = true
    } else if event.inAnyOf([volumeControlContainer]) && volumeSlider.isEnabled {
      volumeOverride = true
    } else {
      guard !event.inAnyOf([backgroundView]) else { return }
    }

    super.scrollWheel(with: event)

    seekOverride = false
    volumeOverride = false
  }

  override func mouseEntered(with event: NSEvent) {
    showControl()
  }

  override func mouseMoved(with event: NSEvent) {
    if isShowingVolumeControl && !event.inAnyOf([volumeControlContainer]) {
      hideVolumeControl()
    }
  }

  override func mouseExited(with event: NSEvent) {
    hideControl()
  }

  // MARK: - Window delegate: Open / Close

  func windowWillClose(_ notification: Notification) {
    if player.info.state != .shuttingDown && player.info.state != .shutDown {
      // not needed if called when terminating the whole app
      player.overrideAutoSwitchToMusicMode = false
      player.switchBackFromMiniPlayer(automatically: true, showMainWindow: false)
    }
    player.stop()
    player.events.emit(.windowWillClose)
  }

  // MARK: - Window delegate: Size

  func windowWillStartLiveResize(_ notification: Notification) {
    videoView.videoLayer.inLiveResize = true
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard player.info.state.active, let window else { return }
    let windowHeight = normalWindowHeight()
    if isPlaylistVisible {
      // hide
      if window.frame.height < windowHeight + AutoHidePlaylistThreshold {
        isPlaylistVisible = false
        setToInitialWindowSize()
      }
    } else {
      // show
      if window.frame.height < windowHeight + AutoHidePlaylistThreshold {
        setToInitialWindowSize()
      } else {
        isPlaylistVisible = true
      }
    }
    videoView.videoLayer.inLiveResize = false
  }

  // MARK: - Window delegate: Activeness status

  override func windowDidBecomeMain(_ notification: Notification) {
    super.windowDidBecomeMain(notification)

    titleLabel.scroll()
    artistAlbumLabel.scroll()
  }

  // MARK: - UI: Show / Hide

  private func showControl() {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AnimationDurationShowControl
      closeButtonView.animator().alphaValue = 1
      controlView.animator().alphaValue = 1
      mediaInfoView.animator().alphaValue = 0
    }, completionHandler: {})
  }

  private func hideControl() {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AnimationDurationShowControl
      closeButtonView.animator().alphaValue = 0
      controlView.animator().alphaValue = 0
      mediaInfoView.animator().alphaValue = 1
    }, completionHandler: {
      self.titleLabel.scroll()
      self.artistAlbumLabel.scroll()
    })
  }

  // MARK: - UI
  @objc
  override func updateTitle() {
    let (mediaTitle, mediaAlbum, mediaArtist) = player.getMusicMetadata()
    titleLabel.stringValue = mediaTitle
    window?.title = mediaTitle
    // hide artist & album label when info not available
    if mediaArtist.isEmpty && mediaAlbum.isEmpty {
      titleLabelTopConstraint.constant = 6 + 10
      artistAlbumLabel.stringValue = ""
    } else {
      titleLabelTopConstraint.constant = 6
      if mediaArtist.isEmpty || mediaAlbum.isEmpty {
        artistAlbumLabel.stringValue = "\(mediaArtist)\(mediaAlbum)"
      } else {
        artistAlbumLabel.stringValue = "\(mediaArtist) - \(mediaAlbum)"
      }
    }
    titleLabel.scroll()
    artistAlbumLabel.scroll()
  }

  override func updateVolume() {
    guard loaded else { return }
    super.updateVolume()
    volumeLabel.intValue = Int32(player.info.volume)
  }

  override func handleVideoSizeChange() {
    guard let window else { return }
    let (width, height) = videoSizeForDisplayInMusicMode()
    let aspect = CGFloat(width) / CGFloat(height)
    let currentHeight = videoView.frame.height
    let newHeight = videoView.frame.width / aspect
    updateVideoViewAspectConstraint(withAspect: aspect)
    // resize window
    guard isVideoVisible else { return }
    var frame = window.frame
    frame.size.height += newHeight - currentHeight - 0.5
    window.setFrame(frame, display: true, animate: false)
  }

  private func updateCloseButton() {
    closeButtonSizeConstraint.constant = isVideoVisible ? 13 : 12
    closeButtonSpacingConstraint.constant = isVideoVisible ? 5 : 4
  }

  func updateVideoViewAspectConstraint(withAspect aspect: CGFloat) {
    if let constraint = videoViewAspectConstraint {
      constraint.isActive = false
    }
    videoViewAspectConstraint = NSLayoutConstraint(item: videoView, attribute: .width, relatedBy: .equal,
                                                   toItem: videoView, attribute: .height, multiplier: aspect, constant: 0)
    videoViewAspectConstraint?.isActive = true
  }

  func videoSizeForDisplayInMusicMode() -> (Int, Int) {
    guard player.info.isAudio == .isAudio else {
      return player.videoSizeForDisplay
    }
    let albumArtTrack = player.info.videoTracks.first(where: { $0.isAlbumart })
    if let albumArtTrack,
       let width = albumArtTrack.demuxW,
       let height = albumArtTrack.demuxH,
       width > 0,
       height > 0 {
      return (width, height)
    }
    return (1, 1)
  }

  func refreshArtworkVisibility() {
    guard loaded else { return }
    let albumArtTrack = player.info.videoTracks.first(where: { $0.isAlbumart })
    let hasSubtitles = (player.info.isSubVisible && player.info.sid != 0) || (player.info.isSecondSubVisible && player.info.secondSid != 0)
    defaultAlbumArt.isHidden = player.info.isAudio != .isAudio || albumArtTrack != nil || hasSubtitles
  }

  func setToInitialWindowSize(display: Bool = true, animate: Bool = true) {
    guard let window else { return }
    window.setFrame(window.frame.rectWithoutPlaylistHeight(providedWindowHeight: normalWindowHeight()), display: display, animate: animate)
  }

  // MARK: - NSPopoverDelegate

  func popoverWillClose(_ notification: Notification) {
    if NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) != window!.windowNumber {
      hideControl()
    }
  }

  func handleVolumePopover(_ isTrackpadBegan: Bool, _ isTrackpadEnd: Bool, _ isMouse: Bool) {
    hideVolumeControlTask?.cancel()
    hideVolumeControlTask = DispatchWorkItem {
      self.hideVolumeControl()
    }
    if isTrackpadBegan {
      showVolumePopover(animated: false)
    } else if isTrackpadEnd {
      DispatchQueue.main.asyncAfter(deadline: .now(), execute: hideVolumeControlTask!)
    } else if isMouse {
      // if it's a mouse, simply show popover then hide after a while when user stops scrolling
      showVolumePopover(animated: false)
      let timeout = Preference.double(for: .osdAutoHideTimeout)
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: hideVolumeControlTask!)
    }
  }

  private func hideVolumeControl(animated: Bool = true) {
    isShowingVolumeControl = false
    if animated {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = AnimationDurationShowControl
        volumeControlViews.forEach { $0?.animator().alphaValue = 0 }
      }) {
        self.volumeControlViews.forEach { $0?.isHidden = true }
        self.volumeContainerTrailingConstraint.constant = 10
      }
    } else {
      volumeControlViews.forEach { $0?.isHidden = true }
      volumeContainerTrailingConstraint.constant = 10
    }
  }

  private func showVolumePopover(animated: Bool = true) {
    isShowingVolumeControl = true
    volumeContainerTrailingConstraint.constant = 148
    if animated {
      volumeControlViews.forEach {
        $0?.alphaValue = 0
        $0?.isHidden = false
      }
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = AnimationDurationShowControl
        volumeControlViews.forEach { $0?.animator().alphaValue = 1 }
      }, completionHandler: {})
    } else {
      volumeControlViews.forEach {
        $0?.alphaValue = 1
        $0?.isHidden = false
      }
    }
  }

  // MARK: - IBActions

  override func muteButtonAction(_ sender: NSButton) {
    if isShowingVolumeControl {
      super.muteButtonAction(sender)
    } else {
      showVolumePopover()
    }
  }

  func showPlaylistAction(_ tab: SidebarViewController.TabType) {
    if !isPlaylistVisible {
      playlistView.pleaseSwitchToTab(tab)
      togglePlaylist(self)
    } else if playlistView.currentTab == tab {
      togglePlaylist(self)
    } else {
      playlistView.pleaseSwitchToTab(tab)
    }
  }

  @IBAction func togglePlaylist(_ sender: Any) {
    guard let window else { return }
    if isPlaylistVisible {
      // hide
      isPlaylistVisible = false
      setToInitialWindowSize()
    } else {
      // show
      isPlaylistVisible = true
//      playlistView.reloadData(playlist: true, chapters: true)

      var newFrame = window.frame
      newFrame.origin.y -= DefaultPlaylistHeight
      newFrame.size.height += DefaultPlaylistHeight
      window.setFrame(newFrame, display: true, animate: true)
    }
    Preference.set(isPlaylistVisible, for: .musicModeShowPlaylist)
  }

  @IBAction func toggleVideoView(_ sender: Any) {
    guard let window else { return }
    isVideoVisible = !isVideoVisible
    videoWrapperViewBottomConstraint.isActive = isVideoVisible
    controlViewTopConstraint.isActive = !isVideoVisible
    updateCloseButton()
    let videoViewHeight = round(videoView.frame.height)
    if isVideoVisible {
      var frame = window.frame
      frame.size.height += videoViewHeight
      window.setFrame(frame, display: true, animate: false)
    } else {
      var frame = window.frame
      frame.size.height -= videoViewHeight
      window.setFrame(frame, display: true, animate: false)
    }
    Preference.set(isVideoVisible, for: .musicModeShowAlbumArt)
  }

  @IBAction func backBtnAction(_ sender: NSButton) {
    player.switchBackFromMiniPlayer()
  }

  @IBAction func nextBtnAction(_ sender: NSButton) {
    player.navigateInPlaylist(nextMedia: true)
  }

  @IBAction func prevBtnAction(_ sender: NSButton) {
    player.navigateInPlaylist(nextMedia: false)
  }

  @IBAction func volumeBtnAction(_ sender: NSButton) {
    showVolumePopover()
  }

  override func handleIINACommand(_ cmd: IINACommand) {
    super.handleIINACommand(cmd)
    switch cmd {
    case .toggleMusicMode:
      player.switchBackFromMiniPlayer()
    default:
      break
    }
  }

  // MARK: - Utils

  private func normalWindowHeight() -> CGFloat {
    return 72 + (isVideoVisible ? videoWrapperView.frame.height : 0)
  }
}


fileprivate extension NSRect {
  func rectWithoutPlaylistHeight(providedWindowHeight windowHeight: CGFloat) -> NSRect {
    var newRect = self
    newRect.origin.y += (newRect.height - windowHeight)
    newRect.size.height = windowHeight
    return newRect
  }
}
