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
      var added = 0
      fileNames.forEach({ (path) in
        let ext = (path as NSString).pathExtension
        if !PlayerCore.shared.supportedSubtitleFormat.contains(ext) {
          PlayerCore.shared.addToPlaylist(path)
          added += 1
        }
      })
      if added == 0 {
        return false
      }
      NotificationCenter.default.post(Notification(name: Constants.Noti.playlistChanged))
      PlayerCore.shared.sendOSD(.addToPlaylist(added))
      return true
    } else {
      return false
    }
  }

}
