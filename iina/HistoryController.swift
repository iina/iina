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

  /// Cached copy of the playback history stored in the history file.
  ///
  /// This is accessed by both the main thread and a background thread and must be referenced under a lock.
  @Atomic var history: [PlaybackHistory] = []

  /// Number of tasks currently in the queue.
  @Atomic var tasksOutstanding = 0

  private let plistURL: URL
  private let queue = DispatchQueue(label: "IINAHistoryController", qos: .background)

  init(plistFileURL: URL) {
    self.plistURL = plistFileURL
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
      guard let history = object as? [PlaybackHistory] else {
        // Secure coding should ensure that this never occurs.
        log("Unable to convert object read from playback history file to [PlaybackHistory]", level: .error)
        return
      }
      self.history = history
      log("Read \(history.count) playback history entries")
    } catch {
      log("Failed to read playback history file \(plistURL.path): \(error)", level: .error)
    }
  }

  private func save() {
    do {
      try $history.withLock { history in
        log("Saving \(history.count) playback history entries")
        let data = try NSKeyedArchiver.archivedData(withRootObject: history, requiringSecureCoding: true)
        try data.write(to: plistURL, options: [.atomic])
        log("Saved \(history.count) playback history entries")
      }
      NotificationCenter.default.post(Notification(name: .iinaHistoryUpdated))
    } catch {
      log("Failed to save playback history to file \(plistURL.path): \(error)", level: .error)
    }
  }

  /// Add an entry to playback history.
  /// - Note: The entry is added asynchronously by a background thread.
  /// - Parameters:
  ///   - url: URL of the media being played.
  ///   - duration: Total duration of the media.
  func add(_ url: URL, duration: Double) {
    guard Preference.bool(for: .recordPlaybackHistory) else { return }
    $tasksOutstanding.withLock { $0 += 1 }
    queue.async { [self] in
      $history.withLock { history in
        if let existingItem = history.first(where: { $0.mpvMd5 == url.path.md5 }),
           let index = history.firstIndex(of: existingItem) {
          history.remove(at: index)
        }
        history.insert(PlaybackHistory(url: url, duration: duration), at: 0)
      }
      save()
      $tasksOutstanding.withLock { tasksOutstanding in
        tasksOutstanding -= 1
        if tasksOutstanding != 0 {
          // The history controller must be able to finish saving playback history before IINA
          // terminates or history will be lost. If termination times out before saving of playback
          // history has finished then history will be lost. If that happens then the qos of the
          // history batch queue will need to be raised to allow the history controller to keep up
          // with requests to save history.
          log("History tasks outstanding: \(tasksOutstanding)")
        }
      }
      NotificationCenter.default.post(Notification(name: .iinaHistoryTaskFinished))
    }
  }

  func remove(_ entries: [PlaybackHistory]) {
    $history.withLock { history in
      log("Removing \(entries.count) playback history entries")
      history = history.filter { !entries.contains($0) }
    }
    save()
  }

  private func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.history)
  }
}

extension Logger.Sub {
  static let history = Logger.makeSubsystem("history")
}
