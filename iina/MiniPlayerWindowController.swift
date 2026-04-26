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
fileprivate let MiniPlayerSubTextAssProperty = "sub-text/ass"
fileprivate let MiniPlayerSubTextAssFullProperty = "sub-text/ass-full"
fileprivate let MiniPlayerSubAssExtradataProperty = "sub-ass-extradata"

class MiniPlayerWindowController: PlayerWindowController, NSPopoverDelegate {

  enum SubtitleScaleChangeResult {
    case correctedToHidden
    case handledInternally
    case userInitiated
  }

  override var windowNibName: NSNib.Name {
    return NSNib.Name("MiniPlayerWindowController")
  }

  @objc let monospacedFont: NSFont = {
    let fontSize = NSFont.systemFontSize(for: .mini)
    return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }()

  override var videoView: VideoView {
    return player.mainWindow.videoView
  }

  @IBOutlet weak var volumeButton: NSButton!
  @IBOutlet var volumePopover: NSPopover!
  @IBOutlet weak var volumeSliderView: NSView!
  @IBOutlet weak var backgroundView: NSVisualEffectView!
  @IBOutlet weak var closeButtonView: NSView!
  @IBOutlet weak var closeButtonBackgroundViewVE: NSVisualEffectView!
  @IBOutlet weak var closeButtonBackgroundViewBox: NSBox!
  @IBOutlet weak var closeButtonVE: NSButton!
  @IBOutlet weak var backButtonVE: NSButton!
  @IBOutlet weak var closeButtonBox: NSButton!
  @IBOutlet weak var backButtonBox: NSButton!
  @IBOutlet weak var videoWrapperView: NSView!
  @IBOutlet var videoWrapperViewBottomConstraint: NSLayoutConstraint!
  @IBOutlet var controlViewTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var playlistWrapperView: NSVisualEffectView!
  @IBOutlet weak var mediaInfoView: NSView!
  @IBOutlet weak var controlView: NSView!
  @IBOutlet weak var titleLabel: ScrollingTextField!
  @IBOutlet weak var titleLabelTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var artistAlbumLabel: ScrollingTextField!
  @IBOutlet weak var volumeLabel: NSTextField!
  @IBOutlet weak var defaultAlbumArt: NSView!
  @IBOutlet weak var togglePlaylistButton: NSButton!
  @IBOutlet weak var toggleAlbumArtButton: NSButton!

  var isPlaylistVisible = false
  var isVideoVisible = true

  /// Caches the user's subtitle scale while the mini player shows subtitles in its custom overlay.
  private var cachedSubScale: Double?
  /// Tracks whether mpv subtitle rendering is currently suppressed in favor of the mini player overlay.
  private var isSubRenderSuppressed = false
  /// Prevents the subtitle scale OSD from reacting to `sub-scale` changes initiated by the mini player itself.
  private var isManagedSubScaleChange = false
  /// Caches the parsed ASS script metadata until mpv reports new script extradata.
  private var cachedSubtitleASSExtradata: String?
  private var cachedSubtitleASSScript: MiniPlayerASSScript?
  private var cachedExternalSubtitleASSPath: String?
  private var cachedExternalSubtitleASSFile: MiniPlayerASSFile?
  private var subtitleCueViews: [NSTextField] = []

  private lazy var subtitleOverlayView: MiniPlayerSubtitleOverlayView = {
    let view = MiniPlayerSubtitleOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
  }()

  lazy var plainSubtitleLabel: NSTextField = {
    let label = NSTextField(wrappingLabelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.isEditable = false
    label.isSelectable = false
    label.isBezeled = false
    label.drawsBackground = false
    label.textColor = .white
    label.font = NSFont.systemFont(ofSize: 20, weight: .medium)
    label.alignment = .center
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.cell?.truncatesLastVisibleLine = true
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
    shadow.shadowBlurRadius = 4
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    label.shadow = shadow
    label.isHidden = true
    return label
  }()

  private var hideSubtitleWorkItem: DispatchWorkItem?

  var videoViewAspectConstraint: NSLayoutConstraint?

  lazy var hideVolumePopover: DispatchWorkItem = {
    DispatchWorkItem {
      self.volumePopover.animates = true
      self.volumePopover.performClose(self)
    }
  }()

  var playlistView: PlaylistViewController {
    return player.mainWindow.playlistView
  }

  override var mouseActionDisabledViews: [NSView?] {[backgroundView, playlistWrapperView] as [NSView?]}

  // MARK: - Initialization

  override func windowDidLoad() {
    super.windowDidLoad()

    guard let window = window else { return }

    window.styleMask = [.fullSizeContentView, .titled, .resizable, .closable, .miniaturizable]
    window.isMovableByWindowBackground = true
    window.titleVisibility = .hidden
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

    setToInitialWindowSize(display: false, animate: false)

    controlViewTopConstraint.isActive = false

    // tracking area
    let trackingView = NSView()
    trackingView.translatesAutoresizingMaskIntoConstraints = false
    window.contentView?.addSubview(trackingView, positioned: .below, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|"], ["v": trackingView])
    NSLayoutConstraint.activate([
      NSLayoutConstraint(item: trackingView, attribute: .bottom, relatedBy: .equal, toItem: backgroundView, attribute: .bottom, multiplier: 1, constant: 0),
      NSLayoutConstraint(item: trackingView, attribute: .top, relatedBy: .equal, toItem: videoWrapperView, attribute: .top, multiplier: 1, constant: 0)
    ])
    trackingView.addTrackingArea(NSTrackingArea(rect: trackingView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))

    // default album art
    defaultAlbumArt.isHidden = false
    defaultAlbumArt.wantsLayer = true
    defaultAlbumArt.layer?.contents = #imageLiteral(resourceName: "default-album-art")

    // close button
    closeButtonVE.action = #selector(self.close)
    closeButtonBox.action = #selector(self.close)
    closeButtonBackgroundViewVE.roundCorners(withRadius: 8)

    // hide controls initially
    closeButtonBackgroundViewBox.isHidden = true
    closeButtonView.alphaValue = 0
    controlView.alphaValue = 0

    // tool tips
    togglePlaylistButton.toolTip = Preference.ToolBarButton.playlist.localizedDescription()
    toggleAlbumArtButton.toolTip = NSLocalizedString("mini_player.album_art", comment: "album_art")
    volumeButton.toolTip = NSLocalizedString("mini_player.volume", comment: "volume")
    closeButtonVE.toolTip = NSLocalizedString("mini_player.close", comment: "close")
    backButtonVE.toolTip = NSLocalizedString("mini_player.back", comment: "back")

    if Preference.bool(for: .alwaysFloatOnTop) {
      setWindowFloatingOnTop(true)
    }
    volumeSlider.maxValue = Double(Preference.integer(for: .maxVolume))
    volumePopover.delegate = self

    videoWrapperView.addSubview(subtitleOverlayView)
    NSLayoutConstraint.activate([
      subtitleOverlayView.leadingAnchor.constraint(equalTo: videoWrapperView.leadingAnchor),
      subtitleOverlayView.trailingAnchor.constraint(equalTo: videoWrapperView.trailingAnchor),
      subtitleOverlayView.topAnchor.constraint(equalTo: videoWrapperView.topAnchor),
      subtitleOverlayView.bottomAnchor.constraint(equalTo: videoWrapperView.bottomAnchor)
    ])
    subtitleOverlayView.addSubview(plainSubtitleLabel)
    NSLayoutConstraint.activate([
      plainSubtitleLabel.leadingAnchor.constraint(equalTo: subtitleOverlayView.leadingAnchor, constant: 12),
      plainSubtitleLabel.trailingAnchor.constraint(equalTo: subtitleOverlayView.trailingAnchor, constant: -12),
      plainSubtitleLabel.bottomAnchor.constraint(equalTo: subtitleOverlayView.bottomAnchor, constant: -8)
    ])
  }

  // MARK: - Mouse / Trackpad events

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(window)
    super.mouseDown(with: event)
  }

  override func scrollWheel(with event: NSEvent) {
    if isMouseEvent(event, inAnyOf: [playSlider]) && playSlider.isEnabled {
      seekOverride = true
    } else if isMouseEvent(event, inAnyOf: [volumeSliderView]) && volumeSlider.isEnabled {
      volumeOverride = true
    } else {
      guard !isMouseEvent(event, inAnyOf: [backgroundView]) else { return }
    }

    super.scrollWheel(with: event)

    seekOverride = false
    volumeOverride = false
  }

  override func mouseEntered(with event: NSEvent) {
    showControl()
  }

  override func mouseExited(with event: NSEvent) {
    guard !volumePopover.isShown else { return }
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
    guard player.info.state.active, let window = window else { return }
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
    let image = volumeIcon()
    muteButton.image = image
    volumeButton.image = image
  }

  override func handleVideoSizeChange() {
    guard let window = window else { return }
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

  func updateVideoViewAspectConstraint(withAspect aspect: CGFloat) {
    if let constraint = videoViewAspectConstraint {
      constraint.isActive = false
    }
    videoViewAspectConstraint = NSLayoutConstraint(item: videoView, attribute: .width, relatedBy: .equal,
                                                   toItem: videoView, attribute: .height, multiplier: aspect, constant: 0)
    videoViewAspectConstraint?.isActive = true
  }

  func videoSizeForDisplayInMusicMode() -> (Int, Int) {
    guard player.currentMediaIsAudio == .isAudio else {
      return player.videoSizeForDisplay
    }
    return player.info.musicModeArtworkSize ?? (1, 1)
  }

  func refreshArtworkVisibility() {
    guard loaded else { return }
    defaultAlbumArt.isHidden = player.currentMediaIsAudio != .isAudio || player.info.albumArtTrack != nil
  }

  func setToInitialWindowSize(display: Bool = true, animate: Bool = true) {
    guard let window = window else { return }
    window.setFrame(window.frame.rectWithoutPlaylistHeight(providedWindowHeight: normalWindowHeight()), display: display, animate: animate)
  }

  func refreshSubtitleOverlay() {
    guard loaded else { return }

    let shouldUseOverlay = player.isInMiniPlayer &&
      player.currentMediaIsAudio == .isAudio &&
      isVideoVisible &&
      player.info.isSubVisible &&
      player.info.sid != 0

    guard shouldUseOverlay else {
      restoreSubtitleRendering()
      clearSubtitleOverlay(immediately: true)
      return
    }

    setSubtitleRenderingSuppressed(true)

    if let currentSub = player.info.currentTrack(.sub),
       let externalFilename = currentSub.externalFilename,
       MiniPlayerASSRenderer.supportsExternalASSFile(at: externalFilename),
       let playbackTime = player.info.videoPosition?.second,
       let assFile = subtitleASSFile(at: externalFilename) {
      let renderedCues = MiniPlayerASSRenderer.renderCues(from: assFile.cues.filter { $0.isActive(at: playbackTime) },
                                                          script: assFile.script)
      if !renderedCues.isEmpty {
        updateASSSubtitleOverlay(with: renderedCues, script: assFile.script)
      } else {
        clearSubtitleOverlay()
      }
      return
    }

    let assFullText = player.mpv.getString(MiniPlayerSubTextAssFullProperty) ?? ""
    let assText = player.mpv.getString(MiniPlayerSubTextAssProperty) ??
      player.mpv.getString(MPVProperty.subTextAss) ?? ""
    let subtitleText = player.mpv.getString(MPVProperty.subText) ?? ""
    let shouldRenderASS = !assFullText.isEmpty || (!assText.isEmpty && assText != subtitleText)

    if shouldRenderASS {
      let assScript = subtitleASSScript(for: player.mpv.getString(MiniPlayerSubAssExtradataProperty))
      let renderedCues = MiniPlayerASSRenderer.renderCues(from: assFullText, assText: assText, script: assScript)
      if !renderedCues.isEmpty {
        updateASSSubtitleOverlay(with: renderedCues, script: assScript)
      } else if assFullText.isEmpty && assText.isEmpty && !subtitleText.isEmpty {
        updatePlainSubtitleLabel(with: subtitleText)
      } else {
        clearSubtitleOverlay()
      }
      return
    }

    if subtitleText.isEmpty {
      clearSubtitleOverlay()
    } else {
      updatePlainSubtitleLabel(with: subtitleText)
    }
  }

  func handleSubtitleScaleChange(_ scale: Double) -> SubtitleScaleChangeResult {
    if isSubRenderSuppressed && !isManagedSubScaleChange && scale != 0 {
      cachedSubScale = scale
      isManagedSubScaleChange = true
      player.mpv.setDouble(MPVOption.Subtitles.subScale, 0.0, level: .verbose)
      return .correctedToHidden
    }

    let didHandleInternally = isManagedSubScaleChange
    isManagedSubScaleChange = false
    return didHandleInternally ? .handledInternally : .userInitiated
  }

  private func setSubtitleRenderingSuppressed(_ suppressed: Bool) {
    if suppressed {
      guard !isSubRenderSuppressed else { return }
      cachedSubScale = player.mpv.getDouble(MPVOption.Subtitles.subScale)
      isSubRenderSuppressed = true
      isManagedSubScaleChange = true
      player.mpv.setDouble(MPVOption.Subtitles.subScale, 0.0, level: .verbose)
      return
    }

    restoreSubtitleRendering()
  }

  private func restoreSubtitleRendering() {
    guard isSubRenderSuppressed else { return }
    isSubRenderSuppressed = false
    let restoredSubScale = cachedSubScale ?? player.mpv.getDouble(MPVOption.Subtitles.subScale)
    cachedSubScale = nil
    isManagedSubScaleChange = true
    player.mpv.setDouble(MPVOption.Subtitles.subScale, restoredSubScale, level: .verbose)
  }

  private func subtitleASSScript(for extradata: String?) -> MiniPlayerASSScript {
    let normalizedExtradata = extradata ?? ""
    if cachedSubtitleASSExtradata != normalizedExtradata || cachedSubtitleASSScript == nil {
      cachedSubtitleASSExtradata = normalizedExtradata
      cachedSubtitleASSScript = MiniPlayerASSRenderer.parseScript(from: normalizedExtradata)
    }
    return cachedSubtitleASSScript ?? .fallback
  }

  private func subtitleASSFile(at path: String?) -> MiniPlayerASSFile? {
    guard let path, !path.isEmpty else { return nil }
    if cachedExternalSubtitleASSPath != path || cachedExternalSubtitleASSFile == nil {
      cachedExternalSubtitleASSPath = path
      cachedExternalSubtitleASSFile = MiniPlayerASSRenderer.parseFile(at: path)
    }
    return cachedExternalSubtitleASSFile
  }

  private func updateASSSubtitleOverlay(with cues: [MiniPlayerASSRenderedCue], script: MiniPlayerASSScript) {
    hideSubtitleWorkItem?.cancel()
    hideSubtitleWorkItem = nil
    subtitleOverlayView.isHidden = false
    plainSubtitleLabel.isHidden = true
    plainSubtitleLabel.stringValue = ""
    removeSubtitleCueViews()
    subtitleOverlayView.layoutSubtreeIfNeeded()

    let bounds = subtitleOverlayView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return }
    let safePlayResX = max(script.playResX, 1)
    let safePlayResY = max(script.playResY, 1)
    let xScale = bounds.width / safePlayResX
    let yScale = bounds.height / safePlayResY

    for cue in cues.sorted(by: MiniPlayerASSRenderedCue.shouldDisplayBefore) {
      let label = makeSubtitleCueLabel(for: cue, in: bounds, xScale: xScale, yScale: yScale)
      subtitleOverlayView.addSubview(label)
      subtitleCueViews.append(label)
    }
  }

  private func makeSubtitleCueLabel(for cue: MiniPlayerASSRenderedCue,
                                    in bounds: NSRect,
                                    xScale: CGFloat,
                                    yScale: CGFloat) -> NSTextField {
    let attributedString = MiniPlayerASSRenderer.scaledAttributedString(cue.attributedString, yScale: yScale)
    let padding = cue.padding(yScale: yScale)
    let maxWidth = max(80, availableCueTextWidth(for: cue, in: bounds, xScale: xScale) - padding.width * 2)
    let wrappedBounds = attributedString.boundingRect(with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                                      options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                      context: nil).integral
    let naturalSize = attributedString.size()
    let textWidth = min(maxWidth, max(1, ceil(naturalSize.width)))
    let cueSize = NSSize(width: min(bounds.width, max(1, textWidth + padding.width * 2)),
                         height: min(bounds.height, ceil(wrappedBounds.height + padding.height * 2)))
    var frame = NSRect(origin: cueOrigin(for: cue, size: cueSize, in: bounds, xScale: xScale, yScale: yScale),
                       size: cueSize)
    frame.origin.x = min(max(frame.origin.x, 0), max(bounds.width - cueSize.width, 0))
    frame.origin.y = min(max(frame.origin.y, 0), max(bounds.height - cueSize.height, 0))

    let label = NSTextField(wrappingLabelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = true
    label.frame = frame
    label.isEditable = false
    label.isSelectable = false
    label.isBezeled = false
    label.drawsBackground = cue.backgroundColor != nil
    label.backgroundColor = cue.backgroundColor ?? .clear
    label.wantsLayer = cue.backgroundColor != nil
    label.layer?.cornerRadius = cue.backgroundColor == nil ? 0 : 4
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 0
    label.alignment = cue.textAlignment
    label.attributedStringValue = attributedString
    return label
  }

  private func availableCueTextWidth(for cue: MiniPlayerASSRenderedCue,
                                     in bounds: NSRect,
                                     xScale: CGFloat) -> CGFloat {
    let availableWidth = bounds.width - cue.marginLeft * xScale - cue.marginRight * xScale
    return availableWidth > 0 ? availableWidth : bounds.width * 0.92
  }

  private func cueOrigin(for cue: MiniPlayerASSRenderedCue,
                         size: NSSize,
                         in bounds: NSRect,
                         xScale: CGFloat,
                         yScale: CGFloat) -> CGPoint {
    if let position = cue.position {
      return cueOrigin(forAlignedPoint: CGPoint(x: position.x * xScale, y: position.y * yScale),
                       alignment: cue.alignment,
                       size: size)
    }

    let x: CGFloat
    switch cue.alignment {
    case 1, 4, 7:
      x = cue.marginLeft * xScale
    case 3, 6, 9:
      x = bounds.width - cue.marginRight * xScale - size.width
    default:
      x = (bounds.width - size.width) / 2
    }

    let y: CGFloat
    switch cue.alignment {
    case 7, 8, 9:
      y = cue.marginVertical * yScale
    case 4, 5, 6:
      y = (bounds.height - size.height) / 2
    default:
      y = bounds.height - cue.marginVertical * yScale - size.height
    }

    return CGPoint(x: x, y: y)
  }

  private func cueOrigin(forAlignedPoint point: CGPoint, alignment: Int, size: NSSize) -> CGPoint {
    switch alignment {
    case 7:
      return point
    case 8:
      return CGPoint(x: point.x - size.width / 2, y: point.y)
    case 9:
      return CGPoint(x: point.x - size.width, y: point.y)
    case 4:
      return CGPoint(x: point.x, y: point.y - size.height / 2)
    case 5:
      return CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
    case 6:
      return CGPoint(x: point.x - size.width, y: point.y - size.height / 2)
    case 1:
      return CGPoint(x: point.x, y: point.y - size.height)
    case 3:
      return CGPoint(x: point.x - size.width, y: point.y - size.height)
    default:
      return CGPoint(x: point.x - size.width / 2, y: point.y - size.height)
    }
  }

  private func removeSubtitleCueViews() {
    subtitleCueViews.forEach { $0.removeFromSuperview() }
    subtitleCueViews.removeAll()
  }

  // MARK: - NSPopoverDelegate

  func popoverWillClose(_ notification: Notification) {
    if NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) != window!.windowNumber {
      hideControl()
    }
  }

  func handleVolumePopover(_ isTrackpadBegan: Bool, _ isTrackpadEnd: Bool, _ isMouse: Bool) {
    hideVolumePopover.cancel()
    hideVolumePopover = DispatchWorkItem {
      self.volumePopover.animates = true
      self.volumePopover.performClose(self)
    }
    if isTrackpadBegan {
       // enabling animation here causes user not seeing their volume changes during popover transition
       volumePopover.animates = false
       volumePopover.show(relativeTo: volumeButton.bounds, of: volumeButton, preferredEdge: .minY)
     } else if isTrackpadEnd {
       DispatchQueue.main.asyncAfter(deadline: .now(), execute: hideVolumePopover)
     } else if isMouse {
       // if it's a mouse, simply show popover then hide after a while when user stops scrolling
       if !volumePopover.isShown {
         volumePopover.animates = false
         volumePopover.show(relativeTo: volumeButton.bounds, of: volumeButton, preferredEdge: .minY)
       }
       let timeout = Preference.double(for: .osdAutoHideTimeout)
       DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: hideVolumePopover)
     }
  }

  // MARK: - IBActions

  func showPlaylistAction(_ tab: PlaylistViewController.TabViewType) {
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
    guard let window = window else { return }
    if isPlaylistVisible {
      // hide
      isPlaylistVisible = false
      setToInitialWindowSize()
    } else {
      // show
      isPlaylistVisible = true
      playlistView.reloadData(playlist: true, chapters: true)

      var newFrame = window.frame
      newFrame.origin.y -= DefaultPlaylistHeight
      newFrame.size.height += DefaultPlaylistHeight
      window.setFrame(newFrame, display: true, animate: true)
    }
    Preference.set(isPlaylistVisible, for: .musicModeShowPlaylist)
  }

  @IBAction func toggleVideoView(_ sender: Any) {
    guard let window = window else { return }
    isVideoVisible = !isVideoVisible
    videoWrapperViewBottomConstraint.isActive = isVideoVisible
    controlViewTopConstraint.isActive = !isVideoVisible
    closeButtonBackgroundViewVE.isHidden = !isVideoVisible
    closeButtonBackgroundViewBox.isHidden = isVideoVisible
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
    refreshSubtitleOverlay()
  }

  func clearSubtitleOverlay(immediately: Bool = false) {
    hideSubtitleWorkItem?.cancel()
    hideSubtitleWorkItem = nil

    if immediately {
      removeSubtitleCueViews()
      plainSubtitleLabel.isHidden = true
      plainSubtitleLabel.stringValue = ""
      subtitleOverlayView.isHidden = true
      return
    }

    guard !subtitleOverlayView.isHidden else { return }
    let workItem = DispatchWorkItem { [weak self] in
      self?.removeSubtitleCueViews()
      self?.plainSubtitleLabel.isHidden = true
      self?.plainSubtitleLabel.stringValue = ""
      self?.subtitleOverlayView.isHidden = true
      self?.hideSubtitleWorkItem = nil
    }
    hideSubtitleWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
  }

  func updatePlainSubtitleLabel(with text: String) {
    guard !text.isEmpty else {
      clearSubtitleOverlay()
      return
    }

    hideSubtitleWorkItem?.cancel()
    hideSubtitleWorkItem = nil
    removeSubtitleCueViews()
    subtitleOverlayView.isHidden = false
    plainSubtitleLabel.stringValue = text
    plainSubtitleLabel.isHidden = false
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
    if volumePopover.isShown {
      volumePopover.performClose(self)
    } else {
      volumePopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
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

fileprivate final class MiniPlayerSubtitleOverlayView: NSView {
  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

fileprivate struct MiniPlayerASSStyle {
  let name: String
  let fontName: String
  let fontSize: CGFloat
  let primaryColor: NSColor
  let outlineColor: NSColor
  let backColor: NSColor
  let bold: Bool
  let italic: Bool
  let underline: Bool
  let borderStyle: Int
  let outline: CGFloat
  let shadow: CGFloat
  let alignment: Int
  let marginLeft: CGFloat
  let marginRight: CGFloat
  let marginVertical: CGFloat

  static var fallback: MiniPlayerASSStyle {
    let fontName = Preference.string(for: .subTextFont) ?? Constants.String.mpvDefaultFont
    let fontSize = CGFloat(Preference.float(for: .subTextSize))
    let primaryColor = NSColor(mpvColorString: Preference.string(for: .subTextColorString) ?? "") ?? .white
    let outlineColor = NSColor(mpvColorString: Preference.string(for: .subBorderColorString) ?? "") ?? .black
    let backColor = NSColor(mpvColorString: Preference.string(for: .subShadowColorString) ?? "") ?? .clear
    return MiniPlayerASSStyle(name: "Default",
                              fontName: fontName,
                              fontSize: fontSize,
                              primaryColor: primaryColor,
                              outlineColor: outlineColor,
                              backColor: backColor,
                              bold: Preference.bool(for: .subBold),
                              italic: Preference.bool(for: .subItalic),
                              underline: false,
                              borderStyle: 1,
                              outline: CGFloat(Preference.float(for: .subBorderSize)),
                              shadow: CGFloat(Preference.float(for: .subShadowSize)),
                              alignment: 2,
                              marginLeft: CGFloat(Preference.float(for: .subMarginX)),
                              marginRight: CGFloat(Preference.float(for: .subMarginX)),
                              marginVertical: CGFloat(Preference.float(for: .subMarginY)))
  }
}

fileprivate struct MiniPlayerASSScript {
  let playResX: CGFloat
  let playResY: CGFloat
  let wrapStyle: Int
  let styles: [String: MiniPlayerASSStyle]

  static let fallback = MiniPlayerASSScript(playResX: 384,
                                            playResY: 288,
                                            wrapStyle: 0,
                                            styles: ["Default": .fallback])

  var defaultStyle: MiniPlayerASSStyle {
    styles["Default"] ?? .fallback
  }
}

fileprivate struct MiniPlayerASSCueDefinition {
  let sourceIndex: Int
  let layer: Int
  let styleName: String
  let marginLeft: CGFloat
  let marginRight: CGFloat
  let marginVertical: CGFloat
  let text: String
}

fileprivate struct MiniPlayerASSTimedCueDefinition {
  let sourceIndex: Int
  let layer: Int
  let startTime: Double
  let endTime: Double
  let styleName: String
  let marginLeft: CGFloat
  let marginRight: CGFloat
  let marginVertical: CGFloat
  let text: String

  var cueDefinition: MiniPlayerASSCueDefinition {
    MiniPlayerASSCueDefinition(sourceIndex: sourceIndex,
                               layer: layer,
                               styleName: styleName,
                               marginLeft: marginLeft,
                               marginRight: marginRight,
                               marginVertical: marginVertical,
                               text: text)
  }

  func isActive(at time: Double) -> Bool {
    time >= startTime && time < endTime
  }
}

fileprivate struct MiniPlayerASSFile {
  let script: MiniPlayerASSScript
  let cues: [MiniPlayerASSTimedCueDefinition]
}

fileprivate struct MiniPlayerASSRenderedCue {
  let sourceIndex: Int
  let layer: Int
  let attributedString: NSAttributedString
  let alignment: Int
  let position: CGPoint?
  let marginLeft: CGFloat
  let marginRight: CGFloat
  let marginVertical: CGFloat
  let backgroundColor: NSColor?
  let outlineSize: CGFloat
  let shadowSize: CGFloat

  var textAlignment: NSTextAlignment {
    switch alignment {
    case 1, 4, 7:
      return .left
    case 3, 6, 9:
      return .right
    default:
      return .center
    }
  }

  func padding(yScale: CGFloat) -> CGSize {
    let effectPadding = ceil(shadowSize * max(yScale, 0.5))
    return CGSize(width: max(8, effectPadding * 2 + 4), height: max(6, effectPadding + 4))
  }

  static func shouldDisplayBefore(_ lhs: MiniPlayerASSRenderedCue, _ rhs: MiniPlayerASSRenderedCue) -> Bool {
    if lhs.layer != rhs.layer {
      return lhs.layer < rhs.layer
    }
    return lhs.sourceIndex < rhs.sourceIndex
  }
}

fileprivate struct MiniPlayerASSRenderState {
  var fontName: String
  var fontSize: CGFloat
  var primaryColor: NSColor
  var outlineColor: NSColor
  var backColor: NSColor
  var bold: Bool
  var italic: Bool
  var underline: Bool
  var borderStyle: Int
  var outline: CGFloat
  var shadow: CGFloat
  var alignment: Int
  var marginLeft: CGFloat
  var marginRight: CGFloat
  var marginVertical: CGFloat
  var position: CGPoint?
  var drawingMode = false

  init(style: MiniPlayerASSStyle, cue: MiniPlayerASSCueDefinition) {
    fontName = style.fontName
    fontSize = style.fontSize
    primaryColor = style.primaryColor
    outlineColor = style.outlineColor
    backColor = style.backColor
    bold = style.bold
    italic = style.italic
    underline = style.underline
    borderStyle = style.borderStyle
    outline = style.outline
    shadow = style.shadow
    alignment = style.alignment
    marginLeft = cue.marginLeft == 0 ? style.marginLeft : cue.marginLeft
    marginRight = cue.marginRight == 0 ? style.marginRight : cue.marginRight
    marginVertical = cue.marginVertical == 0 ? style.marginVertical : cue.marginVertical
  }

  mutating func reset(to style: MiniPlayerASSStyle, cue: MiniPlayerASSCueDefinition) {
    self = MiniPlayerASSRenderState(style: style, cue: cue)
  }

  func textAttributes(yScale: CGFloat) -> [NSAttributedString.Key: Any] {
    let fontSize = max(8, self.fontSize * max(yScale, 0.5) * 0.82)
    let font = MiniPlayerASSRenderer.makeFont(named: fontName, size: fontSize, bold: bold, italic: italic)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = textAlignment
    paragraphStyle.lineBreakMode = .byWordWrapping

    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: MiniPlayerASSRenderer.displayTextColor(primaryColor),
      .paragraphStyle: paragraphStyle
    ]

    if underline {
      attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }

    if let shadow = MiniPlayerASSRenderer.displayShadow(shadowSize: shadow,
                                                        shadowColor: backColor,
                                                        yScale: yScale) {
      attributes[.shadow] = shadow
    } else {
      attributes[.shadow] = MiniPlayerASSRenderer.defaultTextShadow
    }

    return attributes
  }

  var textAlignment: NSTextAlignment {
    switch alignment {
    case 1, 4, 7:
      return .left
    case 3, 6, 9:
      return .right
    default:
      return .center
    }
  }

  var backgroundColor: NSColor? {
    guard borderStyle == 3, backColor.alphaComponent > 0 else { return nil }
    return backColor
  }
}

fileprivate enum MiniPlayerASSRenderer {
  private static let styleFieldSeparator = ","
  private static let dialogueFieldCount = 10

  static func supportsExternalASSFile(at path: String) -> Bool {
    let lowercasedPath = path.lowercased()
    return lowercasedPath.hasSuffix(".ass") || lowercasedPath.hasSuffix(".ssa")
  }

  static func parseFile(at path: String) -> MiniPlayerASSFile? {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return parseFileContents(contents)
  }

  static func parseScript(from extradata: String) -> MiniPlayerASSScript {
    guard !extradata.isEmpty else { return .fallback }

    var playResX = MiniPlayerASSScript.fallback.playResX
    var playResY = MiniPlayerASSScript.fallback.playResY
    var wrapStyle = 0
    var currentSection = ""
    var styleFormat: [String] = []
    var styles: [String: MiniPlayerASSStyle] = [:]

    for rawLine in extradata.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }

      if line.hasPrefix("[") && line.hasSuffix("]") {
        currentSection = line
        continue
      }

      switch currentSection {
      case "[Script Info]":
        guard let separator = line.firstIndex(of: ":") else { continue }
        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "playresx":
          playResX = CGFloat(Double(value) ?? Double(playResX))
        case "playresy":
          playResY = CGFloat(Double(value) ?? Double(playResY))
        case "wrapstyle":
          wrapStyle = Int(value) ?? wrapStyle
        default:
          break
        }

      case "[V4+ Styles]":
        if line.hasPrefix("Format:") {
          styleFormat = line.dropFirst("Format:".count)
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        } else if line.hasPrefix("Style:"), !styleFormat.isEmpty {
          let values = splitASSFields(String(line.dropFirst("Style:".count)),
                                      expectedCount: styleFormat.count)
          guard values.count == styleFormat.count else { continue }
          let fields = Dictionary(uniqueKeysWithValues: zip(styleFormat, values))
          let style = parseStyle(fields)
          styles[style.name] = style
        }

      default:
        break
      }
    }

    if styles["Default"] == nil {
      styles["Default"] = .fallback
    }

    return MiniPlayerASSScript(playResX: max(playResX, 1),
                               playResY: max(playResY, 1),
                               wrapStyle: wrapStyle,
                               styles: styles)
  }

  static func parseFileContents(_ contents: String) -> MiniPlayerASSFile {
    var playResX = MiniPlayerASSScript.fallback.playResX
    var playResY = MiniPlayerASSScript.fallback.playResY
    var wrapStyle = 0
    var currentSection = ""
    var styleFormat: [String] = []
    var eventFormat: [String] = []
    var styles: [String: MiniPlayerASSStyle] = [:]
    var cues: [MiniPlayerASSTimedCueDefinition] = []

    for (index, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }

      if line.hasPrefix("[") && line.hasSuffix("]") {
        currentSection = line
        continue
      }

      switch currentSection {
      case "[Script Info]":
        guard let separator = line.firstIndex(of: ":") else { continue }
        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "playresx":
          playResX = CGFloat(Double(value) ?? Double(playResX))
        case "playresy":
          playResY = CGFloat(Double(value) ?? Double(playResY))
        case "wrapstyle":
          wrapStyle = Int(value) ?? wrapStyle
        default:
          break
        }

      case "[V4+ Styles]":
        if line.hasPrefix("Format:") {
          styleFormat = line.dropFirst("Format:".count)
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        } else if line.hasPrefix("Style:"), !styleFormat.isEmpty {
          let values = splitASSFields(String(line.dropFirst("Style:".count)),
                                      expectedCount: styleFormat.count)
          guard values.count == styleFormat.count else { continue }
          let fields = Dictionary(uniqueKeysWithValues: zip(styleFormat, values))
          let style = parseStyle(fields)
          styles[style.name] = style
        }

      case "[Events]":
        if line.hasPrefix("Format:") {
          eventFormat = line.dropFirst("Format:".count)
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        } else if line.hasPrefix("Dialogue:"), !eventFormat.isEmpty {
          let values = splitASSFields(String(line.dropFirst("Dialogue:".count)),
                                      expectedCount: eventFormat.count)
          guard values.count == eventFormat.count else { continue }
          let fields = Dictionary(uniqueKeysWithValues: zip(eventFormat, values))
          guard let startTime = assTime(from: fields["start"]),
                let endTime = assTime(from: fields["end"]) else { continue }
          cues.append(MiniPlayerASSTimedCueDefinition(sourceIndex: index,
                                                     layer: Int(fields["layer"] ?? "") ?? 0,
                                                     startTime: startTime,
                                                     endTime: endTime,
                                                     styleName: fields["style"] ?? "Default",
                                                     marginLeft: CGFloat(Int(fields["marginl"] ?? "") ?? 0),
                                                     marginRight: CGFloat(Int(fields["marginr"] ?? "") ?? 0),
                                                     marginVertical: CGFloat(Int(fields["marginv"] ?? "") ?? 0),
                                                     text: fields["text"] ?? ""))
        }

      default:
        break
      }
    }

    if styles["Default"] == nil {
      styles["Default"] = .fallback
    }

    let script = MiniPlayerASSScript(playResX: max(playResX, 1),
                                     playResY: max(playResY, 1),
                                     wrapStyle: wrapStyle,
                                     styles: styles)
    return MiniPlayerASSFile(script: script, cues: cues)
  }

  static func renderCues(from assFullText: String,
                         assText: String,
                         script: MiniPlayerASSScript) -> [MiniPlayerASSRenderedCue] {
    let cueDefinitions = parseCueDefinitions(from: assFullText, assText: assText)
    return cueDefinitions.compactMap { renderCue($0, with: script) }
  }

  static func renderCues(from timedCueDefinitions: [MiniPlayerASSTimedCueDefinition],
                         script: MiniPlayerASSScript) -> [MiniPlayerASSRenderedCue] {
    timedCueDefinitions.compactMap { renderCue($0.cueDefinition, with: script) }
  }

  static func makeFont(named fontName: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
    let normalizedFontName = fontName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let resolvedFont: NSFont
    switch normalizedFontName {
    case Constants.String.mpvDefaultFont.lowercased(),
         "sans-serif",
         "sans",
         "arial",
         "helvetica",
         "helvetica neue",
         "ui-sans-serif",
         "-apple-system",
         ".appleSystemUIFont":
      let defaultWeight: NSFont.Weight = bold ? .semibold : .medium
      resolvedFont = NSFont.systemFont(ofSize: size, weight: defaultWeight)
    default:
      resolvedFont = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .medium)
    }

    var convertedFont = resolvedFont
    if bold {
      convertedFont = NSFontManager.shared.convert(convertedFont, toHaveTrait: .boldFontMask)
    }
    if italic {
      convertedFont = NSFontManager.shared.convert(convertedFont, toHaveTrait: .italicFontMask)
    }
    return convertedFont
  }

  static func displayShadow(shadowSize: CGFloat,
                            shadowColor: NSColor,
                            yScale: CGFloat) -> NSShadow? {
    guard shadowSize > 0, shadowColor.alphaComponent > 0.01 else { return nil }

    let scaledShadow = shadowSize * max(yScale, 0.5)
    let shadow = NSShadow()
    shadow.shadowColor = shadowColor.withAlphaComponent(min(max(shadowColor.alphaComponent, 0.35), 0.85))
    shadow.shadowBlurRadius = max(0.5, min(2.0, scaledShadow * 0.8))
    shadow.shadowOffset = NSSize(width: 0, height: max(0.5, min(1.5, scaledShadow * 0.45)))
    return shadow
  }

  static func displayTextColor(_ color: NSColor) -> NSColor {
    let workingColor = color.usingColorSpace(.sRGB) ?? color
    guard workingColor.alphaComponent >= 0.95 else { return workingColor }

    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    workingColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    if red >= 0.9, green >= 0.9, blue >= 0.9 {
      return .white
    }
    return workingColor
  }

  static var defaultTextShadow: NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.75)
    shadow.shadowBlurRadius = 2
    shadow.shadowOffset = NSSize(width: 0, height: 1)
    return shadow
  }

  static func scaledAttributedString(_ attributedString: NSAttributedString, yScale: CGFloat) -> NSAttributedString {
    let scale = max(yScale, 0.5)
    let scaledAttributedString = NSMutableAttributedString(attributedString: attributedString)
    let fullRange = NSRange(location: 0, length: scaledAttributedString.length)
    scaledAttributedString.enumerateAttributes(in: fullRange) { attributes, range, _ in
      var updatedAttributes = attributes

      if let font = attributes[.font] as? NSFont {
        updatedAttributes[.font] = font.withSize(max(8, font.pointSize * scale))
      }

      if let shadow = attributes[.shadow] as? NSShadow {
        let scaledShadow = NSShadow()
        scaledShadow.shadowColor = shadow.shadowColor
        scaledShadow.shadowBlurRadius = shadow.shadowBlurRadius * scale
        scaledShadow.shadowOffset = NSSize(width: shadow.shadowOffset.width * scale,
                                           height: shadow.shadowOffset.height * scale)
        updatedAttributes[.shadow] = scaledShadow
      }

      scaledAttributedString.setAttributes(updatedAttributes, range: range)
    }
    return scaledAttributedString
  }

  private static func parseCueDefinitions(from assFullText: String, assText: String) -> [MiniPlayerASSCueDefinition] {
    let dialogueCues = assFullText
      .components(separatedBy: .newlines)
      .enumerated()
      .compactMap { index, rawLine -> MiniPlayerASSCueDefinition? in
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("Dialogue:") else { return nil }
        let values = splitASSFields(String(line.dropFirst("Dialogue:".count)),
                                    expectedCount: dialogueFieldCount)
        guard values.count == dialogueFieldCount else { return nil }
        return MiniPlayerASSCueDefinition(sourceIndex: index,
                                          layer: Int(values[0]) ?? 0,
                                          styleName: values[3],
                                          marginLeft: CGFloat(Int(values[5]) ?? 0),
                                          marginRight: CGFloat(Int(values[6]) ?? 0),
                                          marginVertical: CGFloat(Int(values[7]) ?? 0),
                                          text: values[9])
      }

    guard dialogueCues.isEmpty else { return dialogueCues }

    return assText
      .components(separatedBy: .newlines)
      .enumerated()
      .compactMap { index, rawLine -> MiniPlayerASSCueDefinition? in
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        return MiniPlayerASSCueDefinition(sourceIndex: index,
                                          layer: 0,
                                          styleName: "Default",
                                          marginLeft: 0,
                                          marginRight: 0,
                                          marginVertical: 0,
                                          text: line)
      }
  }

  private static func parseStyle(_ fields: [String: String]) -> MiniPlayerASSStyle {
    let fallback = MiniPlayerASSStyle.fallback
    let name = fields["name"] ?? fallback.name
    let fontName = fields["fontname"] ?? fallback.fontName
    let fontSize = CGFloat(Double(fields["fontsize"] ?? "") ?? Double(fallback.fontSize))
    let primaryColor = assColor(from: fields["primarycolour"]) ?? fallback.primaryColor
    let outlineColor = assColor(from: fields["outlinecolour"]) ?? fallback.outlineColor
    let backColor = assColor(from: fields["backcolour"]) ?? fallback.backColor
    let bold = assBool(from: fields["bold"], fallback: fallback.bold)
    let italic = assBool(from: fields["italic"], fallback: fallback.italic)
    let underline = assBool(from: fields["underline"], fallback: fallback.underline)
    let borderStyle = Int(fields["borderstyle"] ?? "") ?? fallback.borderStyle
    let outline = CGFloat(Double(fields["outline"] ?? "") ?? Double(fallback.outline))
    let shadow = CGFloat(Double(fields["shadow"] ?? "") ?? Double(fallback.shadow))
    let alignment = Int(fields["alignment"] ?? "") ?? fallback.alignment
    let marginLeft = CGFloat(Double(fields["marginl"] ?? "") ?? Double(fallback.marginLeft))
    let marginRight = CGFloat(Double(fields["marginr"] ?? "") ?? Double(fallback.marginRight))
    let marginVertical = CGFloat(Double(fields["marginv"] ?? "") ?? Double(fallback.marginVertical))

    return MiniPlayerASSStyle(name: name,
                              fontName: fontName,
                              fontSize: fontSize,
                              primaryColor: primaryColor,
                              outlineColor: outlineColor,
                              backColor: backColor,
                              bold: bold,
                              italic: italic,
                              underline: underline,
                              borderStyle: borderStyle,
                              outline: outline,
                              shadow: shadow,
                              alignment: alignment,
                              marginLeft: marginLeft,
                              marginRight: marginRight,
                              marginVertical: marginVertical)
  }

  private static func renderCue(_ cue: MiniPlayerASSCueDefinition,
                                with script: MiniPlayerASSScript) -> MiniPlayerASSRenderedCue? {
    let baseStyle = script.styles[cue.styleName] ?? script.defaultStyle
    var state = MiniPlayerASSRenderState(style: baseStyle, cue: cue)
    let attributed = NSMutableAttributedString()
    var cursor = cue.text.startIndex

    while cursor < cue.text.endIndex {
      if cue.text[cursor] == "{",
         let closingBrace = cue.text[cursor...].firstIndex(of: "}") {
        let overrideText = String(cue.text[cue.text.index(after: cursor)..<closingBrace])
        applyOverrides(overrideText, state: &state, script: script, cue: cue, baseStyle: baseStyle)
        cursor = cue.text.index(after: closingBrace)
        continue
      }

      let nextBrace = cue.text[cursor...].firstIndex(of: "{") ?? cue.text.endIndex
      let textSegment = decodeText(String(cue.text[cursor..<nextBrace]))
      if !state.drawingMode && !textSegment.isEmpty {
        attributed.append(NSAttributedString(string: textSegment,
                                             attributes: state.textAttributes(yScale: 1)))
      }
      cursor = nextBrace
    }

    guard !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }

    return MiniPlayerASSRenderedCue(sourceIndex: cue.sourceIndex,
                                    layer: cue.layer,
                                    attributedString: attributed,
                                    alignment: state.alignment,
                                    position: state.position,
                                    marginLeft: state.marginLeft,
                                    marginRight: state.marginRight,
                                    marginVertical: state.marginVertical,
                                    backgroundColor: state.backgroundColor,
                                    outlineSize: state.outline,
                                    shadowSize: state.shadow)
  }

  private static func applyOverrides(_ overrideText: String,
                                     state: inout MiniPlayerASSRenderState,
                                     script: MiniPlayerASSScript,
                                     cue: MiniPlayerASSCueDefinition,
                                     baseStyle: MiniPlayerASSStyle) {
    let tokens = overrideText.split(separator: "\\", omittingEmptySubsequences: true)
    for tokenSub in tokens {
      let token = String(tokenSub)
      switch token {
      case let value where value.hasPrefix("r"):
        let styleName = String(value.dropFirst())
        let resetStyle = styleName.isEmpty ? baseStyle : (script.styles[styleName] ?? baseStyle)
        state.reset(to: resetStyle, cue: cue)

      case let value where value.hasPrefix("an"):
        if let alignment = Int(String(value.dropFirst(2))) {
          state.alignment = alignment
        }

      case let value where value.hasPrefix("pos("):
        if let position = parsePoint(from: value) {
          state.position = position
        }

      case let value where value.hasPrefix("fn"):
        let fontName = String(value.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        if !fontName.isEmpty {
          state.fontName = fontName
        }

      case let value where value.hasPrefix("fs"):
        let sizeText = String(value.dropFirst(2))
        if let size = Double(sizeText), !sizeText.hasPrefix("+"), !sizeText.hasPrefix("-") {
          state.fontSize = CGFloat(size)
        }

      case let value where value.hasPrefix("b"):
        state.bold = assBool(from: String(value.dropFirst()), fallback: state.bold)

      case let value where value.hasPrefix("i"):
        state.italic = assBool(from: String(value.dropFirst()), fallback: state.italic)

      case let value where value.hasPrefix("u"):
        state.underline = assBool(from: String(value.dropFirst()), fallback: state.underline)

      case let value where value.hasPrefix("alpha"):
        if let alpha = assAlpha(from: String(value.dropFirst(5))) {
          state.primaryColor = state.primaryColor.withAlphaComponent(alpha)
        }

      case let value where value.hasPrefix("1a"):
        if let alpha = assAlpha(from: String(value.dropFirst(2))) {
          state.primaryColor = state.primaryColor.withAlphaComponent(alpha)
        }

      case let value where value.hasPrefix("3a"):
        if let alpha = assAlpha(from: String(value.dropFirst(2))) {
          state.outlineColor = state.outlineColor.withAlphaComponent(alpha)
        }

      case let value where value.hasPrefix("4a"):
        if let alpha = assAlpha(from: String(value.dropFirst(2))) {
          state.backColor = state.backColor.withAlphaComponent(alpha)
        }

      case let value where value.hasPrefix("1c"):
        if let color = assColor(from: String(value.dropFirst(2))) {
          state.primaryColor = color.withAlphaComponent(state.primaryColor.alphaComponent)
        }

      case let value where value.hasPrefix("3c"):
        if let color = assColor(from: String(value.dropFirst(2))) {
          state.outlineColor = color.withAlphaComponent(state.outlineColor.alphaComponent)
        }

      case let value where value.hasPrefix("4c"):
        if let color = assColor(from: String(value.dropFirst(2))) {
          state.backColor = color.withAlphaComponent(state.backColor.alphaComponent)
        }

      case let value where value.hasPrefix("c"):
        if let color = assColor(from: String(value.dropFirst())) {
          state.primaryColor = color.withAlphaComponent(state.primaryColor.alphaComponent)
        }

      case let value where value.hasPrefix("p"):
        state.drawingMode = (Int(String(value.dropFirst())) ?? 0) > 0

      default:
        break
      }
    }
  }

  private static func decodeText(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\N", with: "\n")
      .replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\h", with: "\u{00A0}")
  }

  private static func parsePoint(from token: String) -> CGPoint? {
    guard token.hasPrefix("pos("), token.hasSuffix(")") else { return nil }
    let contents = token.dropFirst(4).dropLast()
    let components = contents.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
    guard components.count == 2,
          let x = Double(components[0].trimmingCharacters(in: .whitespacesAndNewlines)),
          let y = Double(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return nil
    }
    return CGPoint(x: x, y: y)
  }

  private static func splitASSFields(_ text: String, expectedCount: Int) -> [String] {
    text.split(separator: ",",
               maxSplits: max(expectedCount - 1, 0),
               omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  private static func assBool(from text: String?, fallback: Bool) -> Bool {
    guard let text else { return fallback }
    if text.isEmpty { return true }
    return (Int(text) ?? 0) != 0
  }

  private static func assColor(from text: String?) -> NSColor? {
    guard var text else { return nil }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    let uppercased = text.uppercased()
      .replacingOccurrences(of: "&H", with: "")
      .replacingOccurrences(of: "&", with: "")
    let padded: String
    switch uppercased.count {
    case 1...6:
      padded = String(repeating: "0", count: 6 - uppercased.count) + uppercased
    case 7:
      padded = "0" + uppercased
    default:
      padded = String(uppercased.suffix(8))
    }

    let alphaHex = padded.count == 8 ? String(padded.prefix(2)) : "00"
    let colorHex = padded.count == 8 ? String(padded.suffix(6)) : padded
    guard let alphaValue = UInt8(alphaHex, radix: 16),
          let blueValue = UInt8(colorHex.prefix(2), radix: 16),
          let greenValue = UInt8(colorHex.dropFirst(2).prefix(2), radix: 16),
          let redValue = UInt8(colorHex.suffix(2), radix: 16) else {
      return nil
    }

    let alpha = 1 - CGFloat(alphaValue) / 255
    return NSColor(red: CGFloat(redValue) / 255,
                   green: CGFloat(greenValue) / 255,
                   blue: CGFloat(blueValue) / 255,
                   alpha: alpha)
  }

  private static func assAlpha(from text: String?) -> CGFloat? {
    guard let text else { return nil }
    let normalized = text.uppercased()
      .replacingOccurrences(of: "&H", with: "")
      .replacingOccurrences(of: "&", with: "")
    guard let alpha = UInt8(normalized, radix: 16) else { return nil }
    return 1 - CGFloat(alpha) / 255
  }

  private static func assTime(from text: String?) -> Double? {
    guard let text else { return nil }
    let components = text.split(separator: ":", omittingEmptySubsequences: false)
    guard components.count == 3,
          let hours = Double(components[0]),
          let minutes = Double(components[1]),
          let seconds = Double(components[2]) else {
      return nil
    }
    return hours * 3600 + minutes * 60 + seconds
  }
}
