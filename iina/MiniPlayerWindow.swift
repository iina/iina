//
//  MiniPlayerWindow.swift
//  iina
//
//  Created by Matt Svoboda on 2023-06-15.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class MiniPlayerWindow: NSWindow {

  override func keyDown(with event: NSEvent) {
    /// Forward all key events which the window receives to its controller.
    /// This allows `ESC` & `TAB` key bindings to work, instead of getting swallowed by
    /// MacOS keyboard focus navigation (which we don't use).
    if let controller = windowController as? MiniPlayerWindowController {
      // Special case for playlist delete
      if controller.isPlaylistVisible {
        let key = KeyCodeHelper.mpvKeyCode(from: event)
        if key == "DEL" || key == "BS" {
          let deletedSomething = controller.player.mainWindow.playlistView.deleteSelectedRows()
          if deletedSomething {
            return
          }
        }
      }
      controller.keyDown(with: event)
    }
  }
}
