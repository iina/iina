//
//  TimelineThumbnailBroker.swift
//  iina
//
//  Provides the player-scoped, read-only timeline thumbnail stream used by
//  JavaScript plugins. The broker owns no FFmpeg controls; PlayerCore feeds it
//  already decoded IINA thumbnails after validating the media session.
//

import Cocoa
import JavaScriptCore

struct TimelineThumbnailMediaIdentity: Equatable {
  struct VideoTrack: Equatable {
    let id: Int?
    let sourceID: Int?
    let codec: String?
    let externalFilename: String?
    let ffIndex: Int?
    let width: Int?
    let height: Int?
    let frameRate: Double?

    var dictionary: [String: Any] {
      [
        "id": id ?? NSNull(),
        "sourceId": sourceID ?? NSNull(),
        "codec": codec ?? NSNull(),
        "externalFilename": externalFilename ?? NSNull(),
        "ffIndex": ffIndex ?? NSNull(),
        "width": width ?? NSNull(),
        "height": height ?? NSNull(),
        "frameRate": frameRate ?? NSNull()
      ]
    }
  }

  let sessionID: String
  let url: String
  let fileSize: Int64
  let modificationDate: TimeInterval
  let fileID: UInt64?
  let videoTrack: VideoTrack?

  var key: Key {
    Key(url: url, fileSize: fileSize, modificationDate: modificationDate, fileID: fileID, videoTrack: videoTrack)
  }

  struct Key: Equatable {
    let url: String
    let fileSize: Int64
    let modificationDate: TimeInterval
    let fileID: UInt64?
    let videoTrack: VideoTrack?
  }

  var dictionary: [String: Any] {
    [
      "sessionId": sessionID,
      "url": url,
      "fileSize": fileSize,
      "modificationDate": modificationDate,
      "fileId": fileID ?? NSNull(),
      "videoTrack": videoTrack?.dictionary ?? NSNull()
    ]
  }

  static func make(url: URL, track: MPVTrack?, sessionID: String) -> TimelineThumbnailMediaIdentity? {
    guard url.isFileURL,
          let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let fileSize = attributes[.size] as? NSNumber,
          let modified = attributes[.modificationDate] as? Date else {
      return nil
    }
    let videoTrack = track.map {
      VideoTrack(
        id: $0.id,
        sourceID: $0.srcId,
        codec: $0.codec,
        externalFilename: $0.externalFilename,
        ffIndex: $0.ffIndex,
        width: $0.demuxW,
        height: $0.demuxH,
        frameRate: $0.demuxFps
      )
    }
    return TimelineThumbnailMediaIdentity(
      sessionID: sessionID,
      url: url.absoluteString,
      fileSize: fileSize.int64Value,
      modificationDate: modified.timeIntervalSince1970,
      fileID: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
      videoTrack: videoTrack
    )
  }
}

struct TimelineThumbnailEncoded: Equatable {
  let timestamp: Double
  let width: Int
  let height: Int
  let data: Data
  let mimeType = "image/jpeg"
}

struct TimelineThumbnailUpdate {
  enum State: String {
    case generating
    case partial
    case ready
    case invalidated
    case unavailable
    case failed
  }

  let state: State
  let progress: Double
  let media: TimelineThumbnailMediaIdentity?
  let thumbnails: [TimelineThumbnailEncoded]
  let reason: String?
}

final class TimelineThumbnailBroker {
  struct Session: Equatable {
    let token: String
    let identity: TimelineThumbnailMediaIdentity
    let cacheName: String?
  }

  typealias Listener = (TimelineThumbnailUpdate) -> Void

  static let maxThumbnailCount = 128
  static let maxBytesPerThumbnail = 256 * 1024
  static let maxBytesPerUpdate = 8 * 1024 * 1024

  private let queue = DispatchQueue(label: "com.iina.timeline-thumbnail-broker", qos: .utility)
  private var listeners: [String: Listener] = [:]
  private var currentUpdate: TimelineThumbnailUpdate?
  private var activeSession: Session?
  private var encodedThumbnails: [TimelineThumbnailEncoded] = []
  private var encodedBytes = 0

  func subscribe(_ listener: @escaping Listener) -> String {
    let id = UUID().uuidString
    queue.sync {
      listeners[id] = listener
      listener(currentUpdate ?? TimelineThumbnailUpdate(
        state: .unavailable,
        progress: 0,
        media: nil,
        thumbnails: [],
        reason: nil
      ))
    }
    return id
  }

  func unsubscribe(_ id: String) {
    _ = queue.sync {
      listeners.removeValue(forKey: id)
    }
  }

  @discardableResult
  func beginSession(_ identity: TimelineThumbnailMediaIdentity, cacheName: String?) -> Session {
    let session = Session(token: UUID().uuidString, identity: identity, cacheName: cacheName)
    queue.sync {
      activeSession = session
      encodedThumbnails.removeAll(keepingCapacity: true)
      encodedBytes = 0
      publishLocked(TimelineThumbnailUpdate(
        state: .generating,
        progress: 0,
        media: identity,
        thumbnails: [],
        reason: nil
      ))
    }
    return session
  }

  func publishPartial(_ thumbnails: [FFThumbnail], progress: Double, for session: Session) {
    queue.async {
      guard self.activeSession == session else { return }
      var totalBytes = self.encodedBytes
      let additions = self.encode(thumbnails, totalBytes: &totalBytes)
      self.encodedBytes = totalBytes
      self.encodedThumbnails.append(contentsOf: additions)
      self.publishLocked(TimelineThumbnailUpdate(
        state: .partial,
        progress: min(max(progress, 0), 1),
        media: session.identity,
        thumbnails: self.encodedThumbnails,
        reason: nil
      ))
    }
  }

  func publishReady(_ thumbnails: [FFThumbnail], for session: Session) {
    queue.async {
      guard self.activeSession == session else { return }
      self.encodedThumbnails.removeAll(keepingCapacity: true)
      self.encodedBytes = 0
      var totalBytes = 0
      let encoded = self.encode(thumbnails, totalBytes: &totalBytes)
      self.encodedBytes = totalBytes
      self.encodedThumbnails = encoded
      self.publishLocked(TimelineThumbnailUpdate(
        state: .ready,
        progress: 1,
        media: session.identity,
        thumbnails: self.encodedThumbnails,
        reason: nil
      ))
    }
  }

  func publishFailure(_ reason: String, for session: Session) {
    queue.async {
      guard self.activeSession == session else { return }
      self.publishLocked(TimelineThumbnailUpdate(
        state: .failed,
        progress: 0,
        media: session.identity,
        thumbnails: self.encodedThumbnails,
        reason: reason
      ))
    }
  }

  func invalidate(reason: String) {
    queue.sync {
      guard activeSession != nil || currentUpdate?.state == .generating || currentUpdate?.state == .partial || currentUpdate?.state == .ready else {
        return
      }
      let media = currentUpdate?.media
      activeSession = nil
      encodedThumbnails.removeAll(keepingCapacity: true)
      encodedBytes = 0
      publishLocked(TimelineThumbnailUpdate(
        state: .invalidated,
        progress: 0,
        media: media,
        thumbnails: [],
        reason: reason
      ))
    }
  }

  private func publishLocked(_ update: TimelineThumbnailUpdate) {
    currentUpdate = update
    let listeners = Array(self.listeners.values)
    listeners.forEach { $0(update) }
  }

  private func encode(_ thumbnails: [FFThumbnail], totalBytes: inout Int) -> [TimelineThumbnailEncoded] {
    var result: [TimelineThumbnailEncoded] = []
    result.reserveCapacity(min(thumbnails.count, Self.maxThumbnailCount))
    for thumbnail in thumbnails {
      guard result.count + encodedThumbnails.count < Self.maxThumbnailCount,
            let image = thumbnail.image,
            let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
            bitmap.pixelsWide > 0,
            bitmap.pixelsHigh > 0,
            bitmap.pixelsWide <= 4096,
            bitmap.pixelsHigh <= 4096,
            let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75]),
            data.count > 0,
            data.count <= Self.maxBytesPerThumbnail,
            totalBytes + data.count <= Self.maxBytesPerUpdate else {
        continue
      }
      result.append(TimelineThumbnailEncoded(
        timestamp: thumbnail.realTime,
        width: bitmap.pixelsWide,
        height: bitmap.pixelsHigh,
        data: data
      ))
      totalBytes += data.count
    }
    return result
  }
}

@objc protocol JavascriptTimelineThumbnailExportable: JSExport {
  func timestamp() -> Double
  func width() -> Int
  func height() -> Int
  func mimeType() -> String
  func data() -> JSValue?
}

@objc final class JavascriptTimelineThumbnail: NSObject, JavascriptTimelineThumbnailExportable {
  private let value: TimelineThumbnailEncoded
  private weak var context: JSContext?

  init(value: TimelineThumbnailEncoded, context: JSContext) {
    self.value = value
    self.context = context
  }

  func timestamp() -> Double { value.timestamp }
  func width() -> Int { value.width }
  func height() -> Int { value.height }
  func mimeType() -> String { value.mimeType }

  func data() -> JSValue? {
    guard let context else { return nil }
    return createUInt8Array(fromData: value.data, in: context)
  }
}
