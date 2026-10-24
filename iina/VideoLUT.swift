import Foundation

/// Library operations affect managed copies, never the original imported files.
struct VideoLUTLibrary {
  static let filterLabel = "lyina_lut"

  struct Entry {
    let url: URL
    let graph: String
    var name: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL) {
      self.url = url
      graph = ProcessedVideoGraph.lutFilter(path: url.path)
    }
  }

  struct PreparedImport {
    fileprivate let name: String
    fileprivate let data: Data
  }

  let directory: URL

  func entries() throws -> [Entry] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let removed = try removedNames()
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
      .filter { !removed.contains($0.lastPathComponent) && $0.pathExtension.lowercased() == "cube" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
      .map { Entry(url: $0) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  func importFile(_ source: URL) throws -> Entry {
    try importPreparedFile(Self.prepareImport(source))
  }

  /// Safe off the library owner's queue; this phase performs no library mutation.
  static func prepareImport(_ source: URL) throws -> PreparedImport {
    let data = try Data(contentsOf: source)
    guard source.pathExtension.lowercased() == "cube", Self.isValidCube(data) else {
      throw NSError(domain: "VideoLUT", code: 1, userInfo: [NSLocalizedDescriptionKey:
        NSLocalizedString("lut.invalid_file", comment: "Invalid 3D LUT")])
    }
    return PreparedImport(name: source.deletingPathExtension().lastPathComponent, data: data)
  }

  /// Commit on the library owner's queue, serialized with removal and restore.
  func importPreparedFile(_ prepared: PreparedImport) throws -> Entry {
    let name = prepared.name
    let data = prepared.data
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var index = 1
    while true {
      let suffix = index == 1 ? "" : " \(index)"
      let destination = directory.appendingPathComponent(name + suffix).appendingPathExtension("cube")
      if !FileManager.default.fileExists(atPath: destination.path) {
        try data.write(to: destination, options: .atomic)
        try restoreToList(destination)
        Self.notifyChanged()
        return Entry(url: destination)
      }
      if try Data(contentsOf: destination) == data {
        try restoreToList(destination)
        Self.notifyChanged()
        return Entry(url: destination)
      }
      index += 1
    }
  }

  @discardableResult func remove(_ entry: Entry) throws -> URL? {
    guard try entries().contains(where: { $0.url.standardizedFileURL == entry.url.standardizedFileURL }) else {
      throw CocoaError(.fileNoSuchFile)
    }
    var trashedURL: NSURL?
    try FileManager.default.trashItem(at: entry.url, resultingItemURL: &trashedURL)
    Self.notifyChanged()
    return trashedURL as URL?
  }

  static func notifyChanged() {
    NotificationCenter.default.post(name: .iinaLUTLibraryChanged, object: nil)
  }

  private var removedIndex: URL { directory.appendingPathComponent(".removed.json") }

  private func removedNames() throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: removedIndex.path) else { return [] }
    return Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: removedIndex)))
  }

  private func saveRemovedNames(_ names: Set<String>) throws {
    try JSONEncoder().encode(names.sorted()).write(to: removedIndex, options: .atomic)
  }

  private func restoreToList(_ url: URL) throws {
    var removed = try removedNames()
    if removed.remove(url.lastPathComponent) != nil { try saveRemovedNames(removed) }
  }

  static func isValidCube(_ data: Data) -> Bool {
    guard let text = String(data: data, encoding: .utf8) else { return false }
    var size: Int?
    var rows = 0
    var valid = true
    var minimum = [0.0, 0.0, 0.0]
    var maximum = [1.0, 1.0, 1.0]
    text.enumerateLines { line, stop in
      let fields = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        .split(whereSeparator: { $0.isWhitespace })
      guard let first = fields.first else { return }
      switch first {
      case "TITLE": break
      case "LUT_3D_SIZE":
        if fields.count == 2, size == nil, rows == 0, let value = Int(fields[1]), (2...256).contains(value) {
          size = value
        } else { valid = false }
      case "DOMAIN_MIN", "DOMAIN_MAX":
        let values = fields.dropFirst().compactMap { Double($0) }
        if rows == 0, fields.count == 4, values.count == 3, values.allSatisfy(\.isFinite) {
          if first == "DOMAIN_MIN" { minimum = values } else { maximum = values }
        } else { valid = false }
      default:
        let values = fields.compactMap { Double($0) }
        if let size, fields.count == 3, values.count == 3, values.allSatisfy(\.isFinite), rows < size * size * size {
          rows += 1
        } else { valid = false }
      }
      if !valid { stop = true }
    }
    guard valid, let size else { return false }
    return rows == size * size * size && zip(minimum, maximum).allSatisfy { $0 < $1 }
  }
}

extension Notification.Name {
  static let iinaLUTLibraryChanged = Notification.Name("IINALUTLibraryChanged")
}
