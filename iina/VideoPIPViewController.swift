//
//  VideoPIPViewController.swift
//  iina
//
//  Created by low-batt on 3/29/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Cocoa

class VideoPIPViewController: PIPViewController {

  /// Force a draw, if needed.
  ///
  /// If the image is changing there is no need to force a draw. However if playback is paused, or if playback is in progress but the video
  /// track is an album art still image then drawing is required.
  private func forceDraw() {
    guard let controller = delegate as? MainWindowController, controller.player.info.isPaused
            || controller.player.info.currentTrack(.video)?.isAlbumart ?? false else { return }
    controller.videoView.videoLayer.draw(forced: true)
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
    forceDraw()
  }

  /// Force a draw after exiting PiP.
  ///
  /// If playback is paused then after exiting PiP mode the main window will sometimes be black. Force a draw to ensure this does not
  /// happen and a frame is displayed. See issue #4268 and PR #4286 for details.
  override func viewDidDisappear() {
    super.viewDidDisappear()
    forceDraw()
  }
}
