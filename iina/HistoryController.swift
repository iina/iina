//
//  HistoryController.swift
//  iina
//
//  Created by lhc on 25/4/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class HistoryController: NSObject {

  static let shared = HistoryController(plistFileURL: Utility.playbackHistoryURL)

  var plistURL: URL
  var history: [PlaybackHistory]

  init(plistFileURL: URL) {
    self.plistURL = plistFileURL
    self.history = []
    super.init()
    read()
  }

  private func read() {
    history = (NSKeyedUnarchiver.unarchiveObject(withFile: plistURL.path) as? [PlaybackHistory]) ?? []
  }

  func save() {
    let result = NSKeyedArchiver.archiveRootObject(history, toFile: plistURL.path)
    if !result {
      Utility.log("Cannot save playback history!")
    }
  }

  func add(_ url: URL) {
    if let existingItem = (history.filter { $0.mpvMd5 == url.path.md5 }).first, let index = history.index(of: existingItem) {
      history.remove(at: index)
    }
    history.insert(PlaybackHistory(url: url), at: 0)
    save()
  }

  func remove(_ entry: PlaybackHistory) {
    history = history.filter { $0 != entry }
    save()
  }

}
