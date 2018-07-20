//
//  MiniPlayerWindowController.swift
//  iina
//
//  Created by lhc on 30/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate typealias PK = Preference.Key

fileprivate let DefaultPlaylistHeight: CGFloat = 300
fileprivate let AutoHidePlaylistThreshold: CGFloat = 200
fileprivate let AnimationDurationShowControl: TimeInterval = 0.2

class MiniPlayerWindowController: NSWindowController, NSWindowDelegate, NSPopoverDelegate {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("MiniPlayerWindowController")
  }

  @objc let monospacedFont: NSFont = {
    let fontSize = NSFont.systemFontSize(for: .mini)
    return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }()

  unowned var player: PlayerCore

  var menuActionHandler: MainMenuActionHandler!

  // MARK: - Observed user defaults

  private let observedPrefKeys: [Preference.Key] = [
    .showRemainingTime,
    .alwaysFloatOnTop,
    .maxVolume
  ]

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

    guard let keyPath = keyPath, let change = change else { return }

    switch keyPath {

    case PK.showRemainingTime.rawValue:
      if let newValue = change[.newKey] as? Bool {
        rightLabel.mode = newValue ? .remaining : .duration
      }

    case PK.alwaysFloatOnTop.rawValue:
      if let newValue = change[.newKey] as? Bool {
        self.isOntop = newValue
        setWindowFloatingOnTop(newValue)
      }

    case PK.maxVolume.rawValue:
      if let newValue = change[.newKey] as? Int {
        volumeSlider.maxValue = Double(newValue)
        if player.mpv.getDouble(MPVOption.Audio.volume) > Double(newValue) {
          player.mpv.setDouble(MPVOption.Audio.volume, Double(newValue))
        }
      }

    default:
      return
    }
  }

  @IBOutlet weak var muteButton: NSButton!
  @IBOutlet weak var volumeButton: NSButton!
  @IBOutlet var volumePopover: NSPopover!
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
  @IBOutlet weak var titleLabel: NSTextField!
  @IBOutlet weak var titleLabelTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var artistAlbumLabel: NSTextField!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var leftLabel: NSTextField!
  @IBOutlet weak var rightLabel: DurationDisplayTextField!
  @IBOutlet weak var playSlider: NSSlider!
  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var volumeLabel: NSTextField!
  @IBOutlet weak var defaultAlbumArt: NSView!

  var isOntop = false
  var isPlaylistVisible = false
  var isVideoVisible = true

  var videoViewAspectConstraint: NSLayoutConstraint?

  private var originalWindowFrame: NSRect!

  init(player: PlayerCore) {
    self.player = player
    super.init(window: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    guard let window = window else { return }

    menuActionHandler = MainMenuActionHandler(playerCore: player)
    let responder = window.nextResponder
    window.nextResponder = menuActionHandler
    menuActionHandler.nextResponder = responder

    window.initialFirstResponder = nil
    window.styleMask = [.fullSizeContentView, .titled, .resizable, .closable]
    window.isMovableByWindowBackground = true
    window.appearance = NSAppearance(named: .vibrantDark)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindow.ButtonType]).forEach {
      window.standardWindowButton($0)?.isHidden = true
    }

    setToInitialWindowSize(display: false, animate: false)
    
    controlViewTopConstraint.isActive = false

    // tracking area
    let trackingView = NSView()
    trackingView.translatesAutoresizingMaskIntoConstraints = false
    window.contentView?.addSubview(trackingView, positioned: .above, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|"], ["v": trackingView])
    NSLayoutConstraint.activate([
      NSLayoutConstraint(item: trackingView, attribute: .bottom, relatedBy: .equal, toItem: backgroundView, attribute: .bottom, multiplier: 1, constant: 0),
      NSLayoutConstraint(item: trackingView, attribute: .top, relatedBy: .equal, toItem: videoWrapperView, attribute: .top, multiplier: 1, constant: 0)
    ])
    trackingView.addTrackingArea(NSTrackingArea(rect: trackingView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))

    backgroundView.state = .active
    [backgroundView, playlistWrapperView].forEach { view in
      view?.material = .ultraDark
    }

    // default album art
    defaultAlbumArt.isHidden = false
    defaultAlbumArt.wantsLayer = true
    defaultAlbumArt.layer?.contents = #imageLiteral(resourceName: "default-album-art")

    // close button
    closeButtonVE.action = #selector(self.close)
    closeButtonBox.action = #selector(self.close)
    closeButtonView.alphaValue = 0
    closeButtonBackgroundViewVE.layer?.cornerRadius = 8
    closeButtonBackgroundViewBox.isHidden = true

    // switching UI
    controlView.alphaValue = 0

    // notifications
    NotificationCenter.default.addObserver(self, selector: #selector(updateTrack), name: .iinaMediaTitleChanged, object: player)

    updateVolume()
    updatePlayButtonState(player.info.isPaused ? .off : .on)
    rightLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    if Preference.bool(for: .alwaysFloatOnTop) {
      setWindowFloatingOnTop(true)
    }
    volumeSlider.maxValue = Double(Preference.integer(for: .maxVolume))
    volumePopover.delegate = self

    // add use default observers
    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    player.switchedToMiniPlayerManually = false
    player.switchedBackFromMiniPlayerManually = false
    player.switchBackFromMiniPlayer(automatically: true, showMainWindow: false)
    player.mainWindow.close()
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    originalWindowFrame = window!.frame
  }

  override func keyDown(with event: NSEvent) {
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    if let kb = PlayerCore.keyBindings[keyCode] {
      if kb.isIINACommand {
        // - IINA command
        if let iinaCommand = IINACommand(rawValue: kb.rawAction) {
          handleIINACommand(iinaCommand)
        } else {
          Logger.log("Unknown iina command \(kb.rawAction)", level: .error)
        }
      } else {
        // - mpv command
        let returnValue: Int32
        // execute the command
        switch kb.action[0] {
        case MPVCommand.abLoop.rawValue:
          player.abLoop()
          returnValue = 0
        default:
          returnValue = player.mpv.command(rawString: kb.rawAction)
        }
        // handle return value
        if returnValue != 0 {
          Logger.log("Return value \(returnValue) when executing key command \(kb.rawAction)", level: .warning)
        }
      }
    } else {
      super.keyDown(with: event)
    }
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(window)
    super.mouseDown(with: event)
  }

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
    }, completionHandler: {})
  }

  override func mouseEntered(with event: NSEvent) {
    showControl()
  }

  override func mouseExited(with event: NSEvent) {
    guard !volumePopover.isShown else { return }
    hideControl()
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let window = window else { return }
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
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = window, !window.inLiveResize else { return }
    self.player.mainWindow.videoView.videoLayer.draw()
  }

  // MARK: - NSPopoverDelegate

  func popoverWillClose(_ notification: Notification) {
    if NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) != window!.windowNumber {
      hideControl()
    }
  }

  // MARK: - Sync UI with playback

  func updatePlayButtonState(_ state: NSControl.StateValue) {
    guard isWindowLoaded else { return }
    playButton.state = state
  }

  func updatePlayTime(withDuration: Bool, andProgressBar: Bool) {
    guard isWindowLoaded else { return }
    guard let duration = player.info.videoDuration, let pos = player.info.videoPosition else {
      Logger.fatal("video info not available")
    }
    let percentage = (pos.second / duration.second) * 100
    leftLabel.stringValue = pos.stringRepresentation
    rightLabel.updateText(with: duration, given: pos)
    if andProgressBar {
      playSlider.doubleValue = percentage
      if #available(macOS 10.12.2, *) {
        player.touchBarSupport.touchBarPlaySlider?.setDoubleValueSafely(percentage)
        player.touchBarSupport.touchBarPosLabels.forEach { $0.updateText(with: duration, given: pos) }
      }
    }
  }

  @objc
  func updateTrack() {
    DispatchQueue.main.async {
      let (mediaTitle, mediaAlbum, mediaArtist) = self.player.getMusicMetadata()
      self.titleLabel.stringValue = mediaTitle
      self.window?.title = mediaTitle
      // hide artist & album label when info not available
      if mediaArtist.isEmpty && mediaAlbum.isEmpty {
        self.titleLabelTopConstraint.constant = 6 + 10
        self.artistAlbumLabel.stringValue = ""
      } else {
        self.titleLabelTopConstraint.constant = 6
        if mediaArtist.isEmpty || mediaAlbum.isEmpty {
          self.artistAlbumLabel.stringValue = "\(mediaArtist)\(mediaAlbum)"
        } else {
          self.artistAlbumLabel.stringValue = "\(mediaArtist) - \(mediaAlbum)"
        }
      }
    }
  }

  func updateVolume() {
    guard isWindowLoaded else { return }
    volumeSlider.doubleValue = player.info.volume
    volumeLabel.intValue = Int32(player.info.volume)
    muteButton.state = player.info.isMuted ? .on : .off
  }

  func updateVideoSize() {
    guard let window = window else { return }
    let videoView = player.mainWindow.videoView
    let (width, height) = player.videoSizeForDisplay
    let aspect = CGFloat(width) / CGFloat(height)
    let currentHeight = videoView.frame.height
    let newHeight = videoView.frame.width / aspect
    updateVideoViewAspectConstraint(withAspect: aspect)
    // resize window
    var frame = window.frame
    frame.size.height += newHeight - currentHeight - 0.5
    window.setFrame(frame, display: true, animate: false)
  }

  func updateVideoViewAspectConstraint(withAspect aspect: CGFloat) {
    if let constraint = videoViewAspectConstraint {
      constraint.isActive = false
    }
    let videoView = player.mainWindow.videoView
    videoViewAspectConstraint = NSLayoutConstraint(item: videoView, attribute: .width, relatedBy: .equal,
                                                   toItem: videoView, attribute: .height, multiplier: aspect, constant: 0)
    videoViewAspectConstraint?.isActive = true
  }

  func setToInitialWindowSize(display: Bool = true, animate: Bool = true) {
    guard let window = window else { return }
    window.setFrame(window.frame.rectWithoutPlaylistHeight(providedWindowHeight: normalWindowHeight()), display: display, animate: animate)
  }

  // MARK: - IBAction

  @IBAction func togglePlaylist(_ sender: Any) {
    guard let window = window else { return }
    if isPlaylistVisible {
      // hide
      isPlaylistVisible = false
      setToInitialWindowSize()
    } else {
      // show
      isPlaylistVisible = true
      player.mainWindow.playlistView.reloadData(playlist: true, chapters: true)

      var newFrame = window.frame
      newFrame.origin.y -= DefaultPlaylistHeight
      newFrame.size.height += DefaultPlaylistHeight
      window.setFrame(newFrame, display: true, animate: true)
    }
  }

  @IBAction func toogleVideoView(_ sender: Any) {
    guard let window = window else { return }
    isVideoVisible = !isVideoVisible
    videoWrapperViewBottomConstraint.isActive = isVideoVisible
    controlViewTopConstraint.isActive = !isVideoVisible
    closeButtonBackgroundViewVE.isHidden = !isVideoVisible
    closeButtonBackgroundViewBox.isHidden = isVideoVisible
    let videoViewHeight = round(player.mainWindow.videoView.frame.height)
    if isVideoVisible {
      var frame = window.frame
      frame.size.height += videoViewHeight
      window.setFrame(frame, display: true, animate: false)
    } else {
      var frame = window.frame
      frame.size.height -= videoViewHeight
      window.setFrame(frame, display: true, animate: false)
    }
  }

  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    player.mainWindow.volumeSliderChanges(sender)
  }

  @IBAction func backBtnAction(_ sender: NSButton) {
    window?.orderOut(self)
    player.switchBackFromMiniPlayer(automatically: false)
  }

  @IBAction func playBtnAction(_ sender: NSButton) {
    if player.info.isPaused {
      player.togglePause(false)
    } else {
      player.togglePause(true)
    }
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

  @IBAction func muteBtnAction(_ sender: NSButton) {
    player.toogleMute()
  }

  @IBAction func playSliderChanges(_ sender: NSSlider) {
    let percentage = 100 * sender.doubleValue / sender.maxValue
    player.seek(percent: percentage, forceExact: true)
  }


  // MARK: - Utils

  func setWindowFloatingOnTop(_ onTop: Bool) {
    guard let window = window else { return }
    if onTop {
      window.level = .iinaFloating
    } else {
      window.level = .normal
    }
  }
  
  private func normalWindowHeight() -> CGFloat {
    return 72 + (isVideoVisible ? videoWrapperView.frame.height : 0)
  }

  private func handleIINACommand(_ cmd: IINACommand) {
    let appDeletate = (NSApp.delegate! as! AppDelegate)
    switch cmd {
    case .openFile:
      appDeletate.openFile(self)
    case .openURL:
      appDeletate.openURL(self)
    case .toggleMusicMode:
      self.menuSwitchToMiniPlayer(.dummy)
    case .flip:
      self.menuActionHandler.menuToggleFlip(.dummy)
    case .mirror:
      self.menuActionHandler.menuToggleMirror(.dummy)
    case .saveCurrentPlaylist:
      self.menuActionHandler.menuSavePlaylist(.dummy)
    case .deleteCurrentFile:
      self.menuActionHandler.menuDeleteCurrentFile(.dummy)
    case .findOnlineSubs:
      self.menuActionHandler.menuFindOnlineSub(.dummy)
    case .saveDownloadedSub:
      self.menuActionHandler.saveDownloadedSub(.dummy)
    default:
      break
    }
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
