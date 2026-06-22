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

class CustomFloatingWindowController: NSWindowController, NSWindowDelegate {

  weak var delegate: CustomFloatingWindowControllerDelegate?
  private let videoView: VideoView

  init(videoView: VideoView, title: String, initialFrame: NSRect) {
    self.videoView = videoView
    let contentView = NSView(frame: NSRect(origin: .zero, size: initialFrame.size))
    let window = NSWindow(
      contentRect: initialFrame,
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.contentView = contentView
    window.level = .iinaFloating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.backgroundColor = .black
    window.minSize = NSSize(width: 240, height: 135)

    super.init(window: window)
    window.delegate = self
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
