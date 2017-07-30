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

  override var windowNibName: String {
    return "MiniPlayerWindowController"
  }

  unowned var player: PlayerCore

  @IBOutlet weak var closeButton: NSButton!
  @IBOutlet weak var playlistWrapperView: NSView!
  @IBOutlet weak var mediaInfoView: NSView!
  @IBOutlet weak var controlView: NSView!

  private var isPlaylistVisible = false
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

    window.isMovableByWindowBackground = true
    if #available(OSX 10.11, *) {
      (window.contentView as? NSVisualEffectView)?.material = .ultraDark
    } else {
      (window.contentView as? NSVisualEffectView)?.material = .dark
    }
    window.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindowButton]).forEach {
      window.standardWindowButton($0)?.isHidden = true
    }

    window.setFrame(window.frame.rectWithoutPlaylistHeight(), display: false, animate: false)

    // tracking area
    let trackingView = NSView()
    trackingView.translatesAutoresizingMaskIntoConstraints = false
    window.contentView?.addSubview(trackingView, positioned: .above, relativeTo: nil)
    Utility.quickConstraints(["H:|[v]|", "V:|[v(==72)]"], ["v": trackingView])
    trackingView.addTrackingArea(NSTrackingArea(rect: trackingView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))

    // close button
    closeButton.image = NSImage(named: NSImageNameStopProgressFreestandingTemplate)
    closeButton.image?.isTemplate = true
    closeButton.action = #selector(self.close)

    // switching UI
    controlView.alphaValue = 0
  }

  func windowWillClose(_ notification: Notification) {
    player.switchBackFromMiniPlayer()
  }

  func windowWillStartLiveResize(_ notification: Notification) {
    originalWindowFrame = window!.frame
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
      var newFrame = window.frame
      newFrame.origin.y -= DefaultPlaylistHeight
      newFrame.size.height += DefaultPlaylistHeight
      window.setFrame(newFrame, display: true, animate: true)
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
