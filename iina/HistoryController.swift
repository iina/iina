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
    NotificationCenter.default.post(Notification(name: .HistoryUpdated))
  }

  func add(_ url: URL, duration: Double) {
    guard Preference.bool(for: .recordPlaybackHistory) else { return }
    if let existingItem = history.first(where: { $0.mpvMd5 == url.path.md5 }), let index = history.index(of: existingItem) {
      history.remove(at: index)
    }
    history.insert(PlaybackHistory(url: url, duration: duration), at: 0)
    save()
  }

  func remove(_ entry: PlaybackHistory) {
    history = history.filter { $0 != entry }
    save()
  }

  func removeAll() {
    history.removeAll()
    save()
  }

}
