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
  var queue = DispatchQueue(label: "IINAHistoryController", qos: .background)

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
      Logger.log("Cannot save playback history!", level: .error)
    }
    NotificationCenter.default.post(Notification(name: .iinaHistoryUpdated))
  }

  func add(_ url: URL, duration: Double) {
    guard Preference.bool(for: .recordPlaybackHistory) else { return }
    if let existingItem = history.first(where: { $0.mpvMd5 == url.path.md5 }), let index = history.firstIndex(of: existingItem) {
      history.remove(at: index)
    }
    history.insert(PlaybackHistory(url: url, duration: duration), at: 0)
    save()
  }

  func remove(_ entries: [PlaybackHistory]) {
    history = history.filter { !entries.contains($0) }
    save()
  }

  func removeAll() {
    history.removeAll()
    save()
  }

}
