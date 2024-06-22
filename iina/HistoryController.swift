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
    // Avoid logging a scary error if the file does not exist.
    guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
    do {
      let data = try Data(contentsOf: plistURL)
      let object = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, PlaybackHistory.self],
                                                          from: data)
      history = object as? [PlaybackHistory] ?? []
    } catch {
      Logger.log("Failed to read playback history file \(plistURL.path): \(error)", level: .error)
    }
  }

  func save() {
    do {
      let data = try NSKeyedArchiver.archivedData(withRootObject: history, requiringSecureCoding: true)
      try data.write(to: plistURL)
      NotificationCenter.default.post(Notification(name: .iinaHistoryUpdated))
    } catch {
      Logger.log("Failed to save playback history to file \(plistURL.path): \(error)", level: .error)
    }
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
