//
//  CustomFloatingWindowController.swift
//  iina
//
//  Copyright © 2026 lhc. All rights reserved.
//

import Cocoa

protocol CustomFloatingWindowControllerDelegate: AnyObject {
  func customFloatingWindowWillClose(_ controller: CustomFloatingWindowController)
}

class CustomFloatingPanel: NSPanel {

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    true
  }
}

class CustomFloatingWindowController: NSWindowController, NSWindowDelegate {

  weak var delegate: CustomFloatingWindowControllerDelegate?
  private let videoView: VideoView

  init(videoView: VideoView, title: String, initialFrame: NSRect, nextResponder: NSResponder?) {
    self.videoView = videoView
    let contentView = NSView(frame: NSRect(origin: .zero, size: initialFrame.size))
    let window = CustomFloatingPanel(
      contentRect: initialFrame,
      styleMask: [.borderless, .resizable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.contentView = contentView
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary, .transient]
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false
    window.backgroundColor = .black
    window.isMovableByWindowBackground = true
    window.minSize = NSSize(width: 240, height: 135)
    window.aspectRatio = initialFrame.size

    super.init(window: window)
    window.delegate = self
    window.nextResponder = nextResponder
    attachVideoView(to: contentView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func windowWillClose(_ notification: Notification) {
    delegate?.customFloatingWindowWillClose(self)
  }

  private func attachVideoView(to contentView: NSView) {
    contentView.addSubview(videoView)
    videoView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      videoView.topAnchor.constraint(equalTo: contentView.topAnchor),
      videoView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      videoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      videoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    ])
  }
}
