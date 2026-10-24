//
//  VideoPIPViewController.swift
//  iina
//
//  Created by low-batt on 3/29/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Cocoa

class VideoPIPViewController: PIPViewController, NSWindowDelegate {

  private var currentScreen: NSScreen?
  private weak var lastVideoWindow: NSWindow?
  private var lastVideoSize: NSSize?
  private var lastVideoScale: CGFloat?

  /// Force a draw, if needed.
  ///
  /// The `forceDraw` method in `PlayerWindowController` will check to see if drawing is really needed and if so, force a
  /// draw of the view.
  private func forceDraw(_ reason: String) {
    guard let controller = delegate as? MainWindowController else { return }
    controller.forceDraw(reason)
  }

  /// Flushing from layout can publish a new surface before the PiP host receives matching bounds.
  /// Keep rendering in the native transaction; PiP flight does not resize this view.
  /// On macOS 10.15, `presentAsPictureInPicture` behaves asynchronously.
  override func viewDidLayout() {
    super.viewDidLayout()
    guard let window = view.window else {
      // Internal error, should not occur.
      Logger.log("VideoPIPViewController.viewDidLayout window is nil", level: .error)
      return
    }
    window.delegate = self
    // The remote host is prepared with an empty container. Its early layout
    // must not invalidate the video that is still playing in the source window.
    guard let controller = delegate as? MainWindowController,
          controller.videoView.window === window else { return }
    guard lastVideoWindow !== window || lastVideoSize != view.bounds.size ||
            lastVideoScale != window.backingScaleFactor else { return }
    // Record first: displaying can flush pending layout and re-enter this method.
    lastVideoWindow = window
    lastVideoSize = view.bounds.size
    lastVideoScale = window.backingScaleFactor
    controller.videoView.prepareForPIPDisplay(render: false)
  }

  /// Force a draw after exiting PiP.
  ///
  /// If playback is paused then after exiting PiP mode the main window will sometimes be black. Force a draw to ensure this does not
  /// happen and a frame is displayed. See issue #4268 and PR #4286 for details.
  override func viewDidDisappear() {
    super.viewDidDisappear()
    forceDraw("exited PiP")
  }

  /// PiP window has changed screens.
  ///
  /// When the PiP window moves to a new screen the configuration of the display link may need to be changed and the ability of the
  /// screen to support HDR needs to be re-evaluated.
  func windowDidChangeScreen(_ notification: Notification) {
    let screen = self.view.window?.screen
    guard currentScreen != screen else { return }
    currentScreen = screen
    NSScreen.log("PiP window moved to screen", screen)
    guard let controller = self.delegate as? PlayerWindowController else {
      // Internal error, should not occur.
      Logger.log("VideoPIPViewController.windowDidChangeScreen delegate", level: .error)
      return
    }
    controller.videoView.updateDisplayLink()
  }
}
