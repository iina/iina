import Foundation

/// Filesystem work only. Folder boundaries retain Finder's order; files within each folder use natural order.
enum FolderVideoScanner {
  static func normalizedPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  static func scan(_ inputs: [URL], videoExtensions: Set<String>) -> [String] {
    let manager = FileManager.default
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .fileSizeKey]
    var seen = Set<String>()
    var result: [String] = []
    func validVideo(_ url: URL) -> Bool {
      guard videoExtensions.contains(url.pathExtension.lowercased()),
            let values = try? url.resourceValues(forKeys: keys),
            values.isRegularFile == true, values.isHidden != true,
            (values.fileSize ?? 0) > 0, manager.isReadableFile(atPath: url.path) else { return false }
      return true
    }
    for input in inputs {
      guard let values = try? input.resourceValues(forKeys: keys), values.isHidden != true else { continue }
      var files: [URL] = []
      if values.isDirectory == true {
        if let enumerator = manager.enumerator(at: input, includingPropertiesForKeys: Array(keys),
                                               options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                               errorHandler: { _, _ in true }) {
          for case let file as URL in enumerator where validVideo(file) { files.append(file) }
        }
        files.sort {
          let comparison = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
          return comparison == .orderedSame ? $0.path < $1.path : comparison == .orderedAscending
        }
      } else if validVideo(input) {
        files = [input]
      }
      for file in files {
        let path = normalizedPath(file)
        if seen.insert(path).inserted { result.append(path) }
      }
    }
    return result
  }
}

/// Main-thread coordinator. Consecutive drops are completed in order, with small append batches.
final class FolderPlaylistImporter {
  private unowned let player: PlayerCore
  private let queue = DispatchQueue(label: "IINA.FolderVideoScanner", qos: .utility)
  private var pending: [[URL]] = []
  private var running = false
  private var generation = 0

  init(player: PlayerCore) { self.player = player }

  func cancel() {
    generation += 1
    pending.removeAll()
    running = false
  }

  func enqueue(_ urls: [URL]) {
    pending.append(urls)
    startNext()
  }

  private func startNext() {
    guard !running, !pending.isEmpty else { return }
    guard player.info.state.active else { cancel(); return }
    running = true
    let inputs = pending.removeFirst()
    let ticket = generation
    let extensions = Set(Utility.supportedFileExt[.video]!)
    queue.async { [weak self] in
      let paths = FolderVideoScanner.scan(inputs, videoExtensions: extensions)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == ticket else { return }
        guard self.player.info.state.active else { self.cancel(); return }
        self.player.getPlaylist()
        let existing = self.player.info.playlist.filter { !$0.isNetworkResource }.map { $0.filename }
        // Resolving existing paths may touch network volumes too; keep it off the UI thread.
        self.queue.async { [weak self] in
          let seen = Set(existing.map { FolderVideoScanner.normalizedPath(URL(fileURLWithPath: $0)) })
          let additions = paths.filter { !seen.contains($0) }
          DispatchQueue.main.async { [weak self] in
            self?.append(additions, offset: 0, added: 0, ticket: ticket)
          }
        }
      }
    }
  }

  private func append(_ paths: [String], offset: Int, added: Int, ticket: Int) {
    guard generation == ticket else { return }
    guard player.info.state.active else { cancel(); return }
    let end = min(offset + 32, paths.count)
    // Recheck the current list: another drop or the user may have appended files during the scan.
    player.getPlaylist()
    let existing = Set(player.info.playlist.map { $0.filename })
    let batch = paths[offset..<end].filter { !existing.contains($0) && FileManager.default.fileExists(atPath: $0) }
    if !batch.isEmpty { player.addToPlaylist(paths: batch) }
    let count = added + batch.count
    if end < paths.count {
      DispatchQueue.main.async { [weak self] in
        self?.append(paths, offset: end, added: count, ticket: ticket)
      }
    } else {
      player.sendOSD(.addToPlaylist(count))
      running = false
      startNext()
    }
  }
}
