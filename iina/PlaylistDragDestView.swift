//
//  PlaylistView.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class PlaylistDragDestView: NSView {

  override func awakeFromNib() {
    register(forDraggedTypes: [NSFilenamesPboardType])
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    return .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pb = sender.draggingPasteboard()
    guard let types = pb.types else { return false }
    if types.contains(NSFilenamesPboardType) {
      guard let fileNames = pb.propertyList(forType: NSFilenamesPboardType) as? [String] else { return false }
      fileNames.forEach({ (path) in
        PlayerCore.shared.addToPlaylist(path)
      })
      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
      if let wc = window?.windowController as? MainWindowController {
        wc.displayOSD(.addToPlaylist(fileNames.count))
      }
      return true
    } else {
      return false
    }
  }

}
