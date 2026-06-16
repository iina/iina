//
//  PlaylistFileMonitor.swift
//  iina
//

import Darwin
import Foundation

final class PlaylistFileMonitor {

  private let queue: DispatchQueue
  private let handler: () -> Void
  private var sources: [String: DispatchSourceFileSystemObject] = [:]
  private var pendingHandler: DispatchWorkItem?

  init(queue: DispatchQueue = DispatchQueue(label: "IINAPlaylistFileMonitor", qos: .utility),
       handler: @escaping () -> Void) {
    self.queue = queue
    self.handler = handler
  }

  func update(paths: [String]) {
    queue.async { [weak self] in
      guard let self else { return }
      let folders = self.parentFolders(for: paths)
      self.removeSources(excluding: folders)
      self.addSources(for: folders)
    }
  }

  func stop() {
    queue.async { [weak self] in
      self?.removeAllSources()
    }
  }

  private func parentFolders(for paths: [String]) -> Set<String> {
    Set(paths.compactMap { path in
      let folder = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
      guard FileManager.default.fileExists(atPath: folder) else { return nil }
      return folder
    })
  }

  private func addSources(for folders: Set<String>) {
    for folder in folders where sources[folder] == nil {
      let fileDescriptor = open(folder, O_EVTONLY)
      guard fileDescriptor >= 0 else { continue }

      let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor,
                                                             eventMask: [.write, .delete, .rename, .revoke],
                                                             queue: queue)
      source.setEventHandler { [weak self] in
        self?.scheduleHandler()
      }
      source.setCancelHandler {
        _ = close(fileDescriptor)
      }
      sources[folder] = source
      source.resume()
    }
  }

  private func removeSources(excluding folders: Set<String>) {
    let removedFolders = sources.keys.filter { !folders.contains($0) }
    for folder in removedFolders {
      sources.removeValue(forKey: folder)?.cancel()
    }
    if sources.isEmpty {
      pendingHandler?.cancel()
      pendingHandler = nil
    }
  }

  private func removeAllSources() {
    sources.values.forEach { $0.cancel() }
    sources.removeAll()
    pendingHandler?.cancel()
    pendingHandler = nil
  }

  private func scheduleHandler() {
    pendingHandler?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      DispatchQueue.main.async {
        self.handler()
      }
    }
    pendingHandler = workItem
    queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: workItem)
  }
}
