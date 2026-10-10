// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import Foundation
import UniformTypeIdentifiers

struct SavedMediaReference: Codable {
    let address: URL
    let bookmark: Data?

    init(url: URL) throws {
        address = url
        bookmark = url.isFileURL ? try url.bookmarkData(options: .minimalBookmark,
                                                       includingResourceValuesForKeys: nil, relativeTo: nil) : nil
    }

    func resolve() throws -> URL {
        guard let bookmark else {
            guard !address.isFileURL, ["http", "https", "rtsp", "rtmp"].contains(address.scheme?.lowercased() ?? ""),
                  address.host != nil else { throw PlaybackToolError.unavailable("A saved playlist contains an invalid media address.") }
            return address
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else {
            throw PlaybackToolError.unavailable("Files access for “\(address.lastPathComponent)” has changed. Select its file or folder again and save the playlist.")
        }
        return url
    }
}

struct SavedPlaylist: Codable, Identifiable {
    let id: UUID
    let name: String
    let savedAt: Date
    let media: [SavedMediaReference]
    let folders: [SavedMediaReference]
}

struct RestoredPlaylist {
    let media: [URL]
    let folders: [URL]
}

/// Files coordination, folder enumeration and bookmark serialization stay off
/// the UI thread. Stored playlists reference media; they do not copy it.
final class PlaylistStore {
    private let queue = DispatchQueue(label: "dev.local.iinapad.playlists", qos: .userInitiated)
    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("IINA/Playlists", isDirectory: true)) {
        self.directory = directory
    }

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func list() async throws -> [SavedPlaylist] {
        try await perform { [self] in
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { try JSONDecoder().decode(SavedPlaylist.self, from: Data(contentsOf: $0)) }
                .sorted { $0.savedAt > $1.savedAt }
        }
    }

    func save(name: String, media: [URL], folders: [URL]) async throws -> SavedPlaylist {
        try await perform { [self] in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !media.isEmpty else {
                throw PlaybackToolError.unavailable("Give the playlist a name and add at least one file.")
            }
            let playlist = SavedPlaylist(id: UUID(), name: trimmed, savedAt: Date(),
                                         media: try media.map { try SavedMediaReference(url: $0) },
                                         folders: try folders.map { try SavedMediaReference(url: $0) })
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(playlist).write(to: directory.appendingPathComponent("\(playlist.id).json"), options: .atomic)
            return playlist
        }
    }

    func remove(_ id: UUID) async throws {
        try await perform { [self] in try FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json")) }
    }

    func restore(_ playlist: SavedPlaylist) async throws -> RestoredPlaylist {
        try await perform {
            RestoredPlaylist(media: try playlist.media.map { try $0.resolve() },
                             folders: try playlist.folders.map { try $0.resolve() })
        }
    }

    func mediaInFolder(_ folder: URL) async throws -> [URL] {
        try await perform {
            var coordinationError: NSError?
            var result: Result<[URL], Error>?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordinationError) { url in
                result = Result {
                    let extensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "ts", "mts", "m2ts", "mpg", "mpeg", "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "aiff", "alac"]
                    return try FileManager.default.contentsOfDirectory(at: url,
                        includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey], options: .skipsHiddenFiles)
                        .filter { file in
                            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
                            guard values.isDirectory != true else { return false }
                            return extensions.contains(file.pathExtension.lowercased()) ||
                                values.contentType?.conforms(to: .movie) == true || values.contentType?.conforms(to: .audio) == true
                        }
                        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw PlaybackToolError.unavailable("Files did not provide access to the selected folder.") }
            return try result.get()
        }
    }
}
