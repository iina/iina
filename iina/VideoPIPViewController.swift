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

  /// Force a draw, if needed.
  ///
  /// The `forceDraw` method in `PlayerWindowController` will check to see if drawing is really needed and if so, force a
  /// draw of the view.
  private func forceDraw(_ reason: String) {
    guard let controller = delegate as? MainWindowController else { return }
    controller.forceDraw(reason)
  }

  /// Force a draw after entering PiP.
  ///
  /// If playback is paused then after entering PiP mode the PiP window will sometimes be white. Force a draw to ensure this does not
  /// happen and a frame is displayed. See PR #3973 for details.
  ///
  /// Any changes in this area must be tested on multiple macOS versions. Under 10.15, `presentAsPictureInPicture` behaves
  /// asynchronously.
  override func viewDidLayout() {
    super.viewDidLayout()
    forceDraw("entered PiP")
    guard let window = view.window else {
      // Internal error, should not occur.
      Logger.log("VideoPIPViewController.viewDidLayout window is nil", level: .error)
      return
    }
    window.delegate = self
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
