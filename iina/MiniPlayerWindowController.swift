//
//  MiniPlayerWindowController.swift
//  iina
//
//  Created by lhc on 30/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let DefaultPlaylistHeight: CGFloat = 300
fileprivate let AutoHidePlaylistThreshold: CGFloat = 72 + 200
fileprivate let AnimationDurationShowControl: TimeInterval = 0.2

class MiniPlayerWindowController: NSWindowController, NSWindowDelegate {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("MiniPlayerWindowController")
  }

  unowned var player: PlayerCore

  var menuActionHandler: MainMenuActionHandler!

  @IBOutlet var volumePopover: NSPopover!
  @IBOutlet weak var backgroundView: NSVisualEffectView!
  @IBOutlet weak var closeButton: NSButton!
  @IBOutlet weak var playlistWrapperView: NSView!
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
  
  // touch bar views
  weak var touchBarPlayPauseBtn: NSButton?
  weak var touchBarCurrentPosLabel: DurationDisplayTextField?

  var isOntop = false
  var isPlaylistVisible = false
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

    window.isMovableByWindowBackground = true
    if #available(OSX 10.11, *) {
      (window.contentView as? NSVisualEffectView)?.material = .ultraDark
    } else {
      (window.contentView as? NSVisualEffectView)?.material = .dark
    }
    window.appearance = NSAppearance(named: .vibrantDark)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindow.ButtonType]).forEach {
      window.standardWindowButton($0)?.isHidden = true
    }

    window.setFrame(window.frame.rectWithoutPlaylistHeight(), display: false, animate: false)

    // tracking area
    let trackingView = NSView()
    trackingView.translatesAutoresizingMaskIntoConstraints = false
    window.contentView?.addSubview(trackingView, positioned: .above, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|", "V:|[v(==72)]"], ["v": trackingView])
    trackingView.addTrackingArea(NSTrackingArea(rect: trackingView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))

    backgroundView.state = .active

    // close button
    closeButton.image = NSImage(named: .stopProgressFreestandingTemplate)
    closeButton.image?.isTemplate = true
    closeButton.action = #selector(self.close)

    // switching UI
    controlView.alphaValue = 0

    // notifications
    NotificationCenter.default.addObserver(self, selector: #selector(updateTrack), name: Constants.Noti.fileLoaded, object: nil)

    updateVolume()
  }

  func windowWillClose(_ notification: Notification) {
    player.switchBackFromMiniPlayer()
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    originalWindowFrame = window!.frame
  }

  override func mouseDown(with event: NSEvent) {
    if volumePopover.isShown {
      volumePopover.performClose(self)
    } else {
      super.mouseDown(with: event)
    }
  }

  override func mouseEntered(with event: NSEvent) {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AnimationDurationShowControl
      controlView.animator().alphaValue = 1
      mediaInfoView.animator().alphaValue = 0
    }, completionHandler: {})
  }

  override func mouseExited(with event: NSEvent) {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = AnimationDurationShowControl
      controlView.animator().alphaValue = 0
      mediaInfoView.animator().alphaValue = 1
    }, completionHandler: {})
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let window = window else { return }
    if isPlaylistVisible {
      // hide
      if window.frame.height < AutoHidePlaylistThreshold {
        isPlaylistVisible = false
        window.setFrame(window.frame.rectWithoutPlaylistHeight(), display: true, animate: true)
      }
    } else {
      // show
      if window.frame.height < AutoHidePlaylistThreshold {
        window.setFrame(window.frame.rectWithoutPlaylistHeight(), display: true, animate: true)
      } else {
        isPlaylistVisible = true
      }
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
      Utility.fatal("video info not available")
    }
    let percentage = (pos.second / duration.second) * 100
    leftLabel.stringValue = pos.stringRepresentation
    rightLabel.updateText(with: duration, given: pos)
    
    // update touch bar label
    touchBarCurrentPosLabel?.updateText(with: duration, given: pos)
    
    if andProgressBar {
      playSlider.doubleValue = percentage
    }
  }

  func updateVolume() {
    guard isWindowLoaded else { return }
    volumeSlider.doubleValue = player.info.volume
    volumeLabel.intValue = Int32(Int(player.info.volume))
  }

  // MARK: - IBAction

  @IBAction func togglePlaylist(_ sender: Any) {
    guard let window = window else { return }
    if isPlaylistVisible {
      // hide
      isPlaylistVisible = false
      window.setFrame(window.frame.rectWithoutPlaylistHeight(), display: true, animate: true)
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

  @IBAction func volumeSliderChanges(_ sender: NSSlider) {
    let value = sender.doubleValue
    player.setVolume(value)
  }

  @IBAction func playBtnAction(_ sender: NSButton) {
    if player.info.isPaused {
      player.togglePause(false)
    } else {
      player.togglePause(true)
    }
  }

  @IBAction func nextBtnAction(_ sender: NSButton) {
    player.navigateInPlaylist(nextOrPrev: true)
  }

  @IBAction func prevBtnAction(_ sender: NSButton) {
    player.navigateInPlaylist(nextOrPrev: false)
  }

  @IBAction func volumeBtnAction(_ sender: NSButton) {
    if volumePopover.isShown {
      volumePopover.performClose(self)
    } else {
      volumePopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
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

  @objc
  func updateTrack() {
    DispatchQueue.main.async {
      let mediaTitle = self.player.mpv.getString(MPVProperty.mediaTitle) ?? ""
      let mediaArtist = self.player.mpv.getString("metadata/by-key/artist") ?? ""
      let mediaAlbum = self.player.mpv.getString("metadata/by-key/album") ?? ""
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
}

fileprivate extension NSRect {
  func rectWithoutPlaylistHeight() -> NSRect {
    var newRect = self
    newRect.origin.y += (newRect.height - 72)
    newRect.size.height = 72
    return newRect
  }
}
