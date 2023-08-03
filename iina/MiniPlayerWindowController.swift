//
//  MiniPlayerWindowController.swift
//  iina
//
//  Created by lhc on 30/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

// Hide playlist if its height is too small to display at least 3 items:
fileprivate let PlaylistMinHeight: CGFloat = 138
fileprivate let AnimationDurationShowControl: TimeInterval = 0.2
fileprivate let MiniPlayerMinWidth: CGFloat = 300
fileprivate let UIAnimationDuration = 0.25

class MiniPlayerWindowController: PlayerWindowController, NSPopoverDelegate {

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
  // Mini island containing window buttons which hover over album art / video:
  @IBOutlet weak var closeButtonBackgroundViewVE: NSVisualEffectView!
  // Mini island containing window buttons which appear next to controls (when video not visible):
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

  /// When resizing the window, need to control the aspect ratio of `videoView`. But cannot use an `aspectRatio` constraint,
  /// because: when playlist is hidden but videoView is shown, that prevents the window from being expanded when the user drags
  /// from the right window edge. Possibly AppKit treats it like a fixed-width constraint. Workaround: use only a `height` constraint
  /// and recalculate it from the video's aspect ratio whenever the window's width changes.
  private var videoWrapperViewHeightConstraint: NSLayoutConstraint!

  private var videoAspectRatio: CGFloat = 1

  var isPlaylistVisible: Bool {
    get {
      Preference.bool(for: .musicModeShowPlaylist)
    }
    set {
      // We already use autosave to save the window frame across launches, so one would think we could
      // determinte whether the playlist is visible just by inspecting the window's size.
      // But we still need to save this info and restore it in case IINA is later relaunched using
      // some very different display/resolution which changes the window size.
      Preference.set(newValue, for: .musicModeShowPlaylist)
    }
  }

  var isVideoVisible: Bool {
    get {
      Preference.bool(for: .musicModeShowAlbumArt)
    }
    set {
      Preference.set(newValue, for: .musicModeShowAlbumArt)
    }
  }

  static let maxWindowWidth = CGFloat(Preference.float(for: .musicModeMaxWidth))

  lazy var hideVolumePopover: DispatchWorkItem = {
    DispatchWorkItem {
      self.volumePopover.animates = true
      self.volumePopover.performClose(self)
    }
  }()

  override var mouseActionDisabledViews: [NSView?] {[backgroundView, playlistWrapperView] as [NSView?]}

  // MARK: - Initialization

  override func windowDidLoad() {
    super.windowDidLoad()

    guard let window = window,
          let contentView = window.contentView else { return }

    window.styleMask = [.fullSizeContentView, .titled, .resizable, .closable]
    window.isMovableByWindowBackground = true
    window.titleVisibility = .hidden
    ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindow.ButtonType]).forEach {
      let button = window.standardWindowButton($0)
      button?.isHidden = true
      // The close button, being obscured by standard buttons, won't respond to clicking when window is inactive.
      // i.e. clicking close button (or any position located in the standard buttons's frame) will only order the window
      // to front, but it never becomes key or main window.
      // Removing the button directly will also work but it causes crash on 10.12-, so for the sake of safety we don't use that way for now.
      // FIXME: Not a perfect solution. It should respond to the first click.
      button?.frame.size = .zero
    }

    contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: MiniPlayerMinWidth).isActive = true
    contentView.widthAnchor.constraint(lessThanOrEqualToConstant: MiniPlayerWindowController.maxWindowWidth).isActive = true

    playlistWrapperView.heightAnchor.constraint(greaterThanOrEqualToConstant: PlaylistMinHeight).isActive = true

    controlViewTopConstraint.isActive = false

    // tracking area
    let trackingView = NSView()
    trackingView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(trackingView, positioned: .above, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|"], ["v": trackingView])
    NSLayoutConstraint.activate([
      NSLayoutConstraint(item: trackingView, attribute: .bottom, relatedBy: .equal, toItem: backgroundView, attribute: .bottom, multiplier: 1, constant: 0),
      NSLayoutConstraint(item: trackingView, attribute: .top, relatedBy: .equal, toItem: videoWrapperView, attribute: .top, multiplier: 1, constant: 0)
    ])
    trackingView.addTrackingArea(NSTrackingArea(rect: trackingView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))

    // default album art
    defaultAlbumArt.wantsLayer = true
    defaultAlbumArt.layer?.contents = #imageLiteral(resourceName: "default-album-art")

    // close button
    closeButtonVE.action = #selector(self.close)
    closeButtonBox.action = #selector(self.close)
    closeButtonBackgroundViewVE.roundCorners(withRadius: 8)
    closeButtonBackgroundViewBox.isHidden = true

    // hide controls initially
    closeButtonBackgroundViewBox.isHidden = true
    closeButtonView.alphaValue = 0
    controlView.alphaValue = 0

    updateVideoViewLayout()
    
    // tool tips
    togglePlaylistButton.toolTip = Preference.ToolBarButton.playlist.description()
    toggleAlbumArtButton.toolTip = NSLocalizedString("mini_player.album_art", comment: "album_art")
    volumeButton.toolTip = NSLocalizedString("mini_player.volume", comment: "volume")
    closeButtonVE.toolTip = NSLocalizedString("mini_player.close", comment: "close")
    backButtonVE.toolTip = NSLocalizedString("mini_player.back", comment: "back")

    if Preference.bool(for: .alwaysFloatOnTop) {
      setWindowFloatingOnTop(true)
    }
    volumeSlider.maxValue = Double(Preference.integer(for: .maxVolume))
    volumePopover.delegate = self

    addObserver(to: .default, forName: .iinaTracklistChanged, object: player) { [self] _ in
      adjustLayoutForVideoChange()
    }
  }

  override internal func setMaterial(_ theme: Preference.Theme?) {
    if #available(macOS 10.14, *) {
      super.setMaterial(theme)
      return
    }
    guard let window = window, let theme = theme else { return }

    let (appearance, material) = Utility.getAppearanceAndMaterial(from: theme)

    [backgroundView, closeButtonBackgroundViewVE, playlistWrapperView].forEach {
      $0?.appearance = appearance
      $0?.material = material
    }

    window.appearance = appearance
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

  override func showWindow(_ sender: Any?) {
    /// Video aspect ratio may have changed if a different video is being shown than last time.
    /// Use `constrainWindowSize()` and `setFrame()` to gracefully adapt layout as needed
    adjustLayoutForVideoChange()

    super.showWindow(sender)
  }

  func windowWillClose(_ notification: Notification) {
    player.switchedToMiniPlayerManually = false
    player.switchedBackFromMiniPlayerManually = false
    if !player.isShuttingDown {
      // not needed if called when terminating the whole app
      player.switchBackFromMiniPlayer(automatically: true, showMainWindow: false)
    }
    player.mainWindow.close()
  }

  // MARK: - Window delegate: Size

  func windowWillResize(_ window: NSWindow, to requestedSize: NSSize) -> NSSize {
    if !window.inLiveResize && requestedSize.width <= MiniPlayerMinWidth {
      // Responding with the current size seems to work much better with certain window management tools
      // (e.g. BetterTouchTool's window snapping) than trying to respond with the min size,
      // which seems to result in the window manager retrying with different sizes, which results in flickering.
      Logger.log("WindowWillResize: requestedSize smaller than min \(MiniPlayerMinWidth); returning existing size", level: .verbose, subsystem: player.subsystem)
      return window.frame.size
    }

    return constrainWindowSize(requestedSize)
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = window, !window.inLiveResize else { return }

    updateVideoViewHeightConstraint()
    videoView.videoLayer.draw()
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    let playlistHeight = currentPlaylistHeight()
    if playlistHeight >= PlaylistMinHeight {
      // save playlist height
      Logger.log("Saving playlist height: \(playlistHeight)")
      Preference.set(playlistHeight, for: .musicModePlaylistHeight)
    }
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
    if player.info.isMuted {
      volumeButton.image = NSImage(named: "mute")
    } else {
      switch volumeLabel.intValue {
        case 0:
          volumeButton.image = NSImage(named: "volume-0")
        case 1...33:
          volumeButton.image = NSImage(named: "volume-1")
        case 34...66:
          volumeButton.image = NSImage(named: "volume-2")
        case 67...1000:
          volumeButton.image = NSImage(named: "volume")
        default:
          break
      }
    }
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

  @IBAction func backBtnAction(_ sender: NSButton) {
    player.switchBackFromMiniPlayer(automatically: false)
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

  @IBAction func togglePlaylist(_ sender: Any) {
    guard let window = window else { return }
    guard let screen = window.screen else { return }
    let showPlaylist = !isPlaylistVisible
    Logger.log("Toggling playlist visibility from \(!showPlaylist) to \(showPlaylist)", level: .verbose)
    self.isPlaylistVisible = showPlaylist
    let currentPlaylistHeight = currentPlaylistHeight()
    var newFrame = window.frame

    if showPlaylist {
      player.mainWindow.playlistView.reloadData(playlist: true, chapters: true)

      // Try to show playlist using previous height
      let desiredPlaylistHeight = CGFloat(Preference.float(for: .musicModePlaylistHeight))
      // The window may be in the middle of a previous toggle, so we can't just assume window's current frame
      // represents a state where the playlist is fully shown or fully hidden. Instead, start by computing the height
      // we want to set, and then figure out the changes needed to the window's existing frame.
      let targetHeightToAdd = desiredPlaylistHeight - currentPlaylistHeight
      // Fill up screen if needed
      newFrame.size.height += targetHeightToAdd
    } else { // hide playlist
      // Save playlist height first
      if currentPlaylistHeight > PlaylistMinHeight {
        Preference.set(currentPlaylistHeight, for: .musicModePlaylistHeight)
      }
    }

    // May need to reduce size of video/art to fit playlist on screen, or other adjustments:
    newFrame.size = constrainWindowSize(newFrame.size)
    let heightDifference = newFrame.height - window.frame.height
    // adjust window origin to expand downwards, but do not allow bottom of window to fall offscreen
    newFrame.origin.y = max(newFrame.origin.y - heightDifference, screen.visibleFrame.origin.y)

    window.animator().setFrame(newFrame, display: true, animate: !AccessibilityPreferences.motionReductionEnabled)
  }

  @IBAction func toggleVideoView(_ sender: Any) {
    guard let window = window else { return }
    isVideoVisible = !isVideoVisible
    Logger.log("Toggling videoView visibility from \(!isVideoVisible) to \(isVideoVisible)", level: .verbose)
    updateVideoViewLayout()
    let videoViewHeight = round(videoView.frame.height)
    var frame = window.frame
    if isVideoVisible {
      frame.size.height += videoViewHeight
    } else {
      frame.size.height -= videoViewHeight
    }
    frame.size = constrainWindowSize(frame.size)
    window.setFrame(frame, display: true, animate: false)
  }

  // MARK: - Layout

  private func updateVideoViewLayout() {
    videoWrapperViewBottomConstraint.isActive = isVideoVisible
    controlViewTopConstraint.isActive = !isVideoVisible
    closeButtonBackgroundViewVE.isHidden = !isVideoVisible
    closeButtonBackgroundViewBox.isHidden = isVideoVisible
  }

  /// The MiniPlayerWindow's width must be between `MiniPlayerMinWidth` and `Preference.musicModeMaxWidth`.
  /// It is composed of up to 3 vertical sections:
  /// 1. `videoWrapperView`: Visible if `isVideoVisible` is true). Scales with the aspect ratio of its video
  /// 2. `backgroundView`: Visible always. Fixed height
  /// 3. `playlistWrapperView`: Visible if `isPlaylistVisible` is true. Height is user resizable, and must be >= `PlaylistMinHeight`
  /// Must also ensure that window stays within the bounds of the screen it is in. Almost all of the time the window  will be
  /// height-bounded instead of width-bounded.
  private func constrainWindowSize(_ requestedSize: NSSize, animate: Bool = false) -> NSSize {
    guard let screen = window?.screen else { return requestedSize }
    /// When the window's width changes, the video scales to match while keeping its aspect ratio,
    /// and the control bar (`backgroundView`) and playlist are pushed down.
    /// Calculate the maximum width/height the art can grow to so that `backgroundView` is not pushed off the screen.
    let visibleScreenSize = screen.visibleFrame.size
    let minPlaylistHeight = isPlaylistVisible ? PlaylistMinHeight : 0

    let maxWindowWidth: CGFloat
    if isVideoVisible {
      var maxVideoHeight = visibleScreenSize.height - backgroundView.frame.height - minPlaylistHeight
      /// `maxVideoHeight` can be negative if very short screen! Fall back to height based on `MiniPlayerMinWidth` if needed
      maxVideoHeight = max(maxVideoHeight, MiniPlayerMinWidth / videoAspectRatio)
      maxWindowWidth = maxVideoHeight * videoAspectRatio
    } else {
      maxWindowWidth = MiniPlayerWindowController.maxWindowWidth
    }

    let newWidth: CGFloat
    if requestedSize.width < MiniPlayerMinWidth {
      // Clamp to min width
      newWidth = MiniPlayerMinWidth
    } else if requestedSize.width > maxWindowWidth {
      // Clamp to max width
      newWidth = maxWindowWidth
    } else {
      // Requested size is valid
      newWidth = requestedSize.width
    }
    let videoHeight = isVideoVisible ? newWidth / videoAspectRatio : 0
    let minWindowHeight = videoHeight + backgroundView.frame.height + minPlaylistHeight
    // Make sure height is within acceptable values
    var newHeight = max(requestedSize.height, minWindowHeight)
    let maxHeight = isPlaylistVisible ? visibleScreenSize.height : minWindowHeight
    newHeight = min(newHeight, maxHeight)
    let newWindowSize = NSSize(width: newWidth, height: newHeight)
    Logger.log("Constrained miniPlayerWindow. VideoAspect: \(videoAspectRatio), RequestedSize: \(requestedSize), NewSize: \(newWindowSize)", level: .verbose)

    updateVideoViewHeightConstraint(height: videoHeight, animate: animate)
    return newWindowSize
  }

  // Returns the current height of the window,
  // including the album art, but not including the playlist.
  private var windowHeightWithoutPlaylist: CGFloat {
    guard let window = window else { return backgroundView.frame.height }
    return backgroundView.frame.height + (isVideoVisible ? window.frame.width / videoAspectRatio : 0)
  }

  private func currentPlaylistHeight() -> CGFloat {
    guard let window = window else { return 0 }
    return window.frame.height - windowHeightWithoutPlaylist
  }

  private func updateVideoViewHeightConstraint(height: CGFloat? = nil, animate: Bool = false) {
    let newHeight: CGFloat
    guard isVideoVisible else { return }
    guard let window = window else { return }

    newHeight = height ?? window.frame.width / videoAspectRatio
    Logger.log("Updating videoWrapperViewHeightConstraint to \(newHeight)")

    if let videoWrapperViewHeightConstraint = videoWrapperViewHeightConstraint {
      if animate {
        videoWrapperViewHeightConstraint.animator().constant = newHeight
      } else {
        videoWrapperViewHeightConstraint.constant = newHeight
      }
    } else {
      videoWrapperViewHeightConstraint = videoWrapperView.heightAnchor.constraint(equalToConstant: newHeight)
      videoWrapperViewHeightConstraint.isActive = true
    }
    videoWrapperView.superview!.layout()
  }

  private func adjustLayoutForVideoChange() {
    guard let window = window else { return }

    let (width, height) = player.originalVideoSize
    videoAspectRatio = (width == 0 || height == 0) ? 1 : CGFloat(width) / CGFloat(height)

    defaultAlbumArt.isHidden = player.info.vid != 0

    NSAnimationContext.runAnimationGroup({ (context) in
      context.duration = UIAnimationDuration

      var newFrame = window.frame
      newFrame.size = constrainWindowSize(newFrame.size, animate: true)
      window.animator().setFrame(newFrame, display: true, animate: !AccessibilityPreferences.motionReductionEnabled)
    })
  }

  // MARK: - Utils

  internal override func handleIINACommand(_ cmd: IINACommand) {
    super.handleIINACommand(cmd)
    switch cmd {
    case .toggleMusicMode:
      menuSwitchToMiniPlayer(.dummy)
    default:
      break
    }
  }

}
