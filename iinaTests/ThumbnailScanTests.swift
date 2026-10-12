//
//  ThumbnailScanTests.swift
//  iinaTests
//
//  Tests for cancelling the scan of a file for thumbnails.
//

import Foundation
import Testing
@testable import IINA

/// A thumbnail generator that records the checkpoints its scan reaches and can cancel thumbnail generation at one of them.
final class CheckpointRecordingController: FFmpegController, FFmpegControllerDelegate {

  /// Where thumbnail generation is cancelled.
  struct Cancellation {
    /// The checkpoint at which generation is cancelled.
    var checkpoint: FFThumbnailScanCheckpoint
    /// Which time the scan reaches the checkpoint when generation is cancelled, counting from 1.
    var occurrence = 1
    /// Whether the check at the checkpoint lets the scan go on, as when cancellation arrives just after the check.
    var passesCheck = false
  }

  /// What a scan did.
  struct Result {
    /// The checkpoints the scan reached, in order.
    var checkpoints: [FFThumbnailScanCheckpoint]
    /// The thumbnails the delegate was told were generated, or `nil` when the delegate was not told.
    var thumbnails: [FFThumbnail]?
    /// Whether the delegate was told generation succeeded.
    var succeeded: Bool?
  }

  private let lock = NSLock()
  private var cancellation: Cancellation?
  private var checkpoints: [FFThumbnailScanCheckpoint] = []
  private var generated: (thumbnails: [FFThumbnail], succeeded: Bool)?
  private var continuation: CheckedContinuation<Result, Never>?

  /// Scan the file with the given URL for thumbnails, cancelling generation as given.
  func scan(_ url: URL, cancelling cancellation: Cancellation? = nil) async -> Result {
    self.cancellation = cancellation
    delegate = self
    return await withCheckedContinuation { continuation in
      lock.withLock { self.continuation = continuation }
      generateThumbnail(forFile: url.path, thumbWidth: 32)
    }
  }

  override func isScanCancelled(_ operation: Operation, at checkpoint: FFThumbnailScanCheckpoint) -> Bool {
    let occurrence = lock.withLock {
      checkpoints.append(checkpoint)
      return checkpoints.filter { $0 == checkpoint }.count
    }
    var passes = false
    if let cancellation, cancellation.checkpoint == checkpoint, cancellation.occurrence == occurrence {
      cancelThumbnailGeneration()
      passes = cancellation.passesCheck
    }
    let cancelled = !passes && super.isScanCancelled(operation, at: checkpoint)
    // A scan stopped at its start or at its finish ends there without telling the delegate.
    if cancelled && (checkpoint == .start || checkpoint == .finish) {
      finish()
    }
    return cancelled
  }

  func didUpdate(_ thumbnails: [FFThumbnail]?, forFile filename: String, withProgress progress: Int) {}

  func didGenerate(_ thumbnails: [FFThumbnail], forFile filename: String, succeeded: Bool) {
    lock.withLock { generated = (thumbnails, succeeded) }
    finish()
  }

  private func finish() {
    let (continuation, result) = lock.withLock {
      defer { self.continuation = nil }
      return (self.continuation, Result(checkpoints: checkpoints, thumbnails: generated?.thumbnails,
                                        succeeded: generated?.succeeded))
    }
    continuation?.resume(returning: result)
  }
}

@Suite("Cancelling a thumbnail scan", .timeLimit(.minutes(1)))
struct ThumbnailScanTests {

  /// The number of intervals the scanned file is divided into; the scan visits one more preview point than this.
  static let thumbnailCount = 4

  /// Scan a two-second video for thumbnails, cancelling generation as given.
  func scan(cancelling cancellation: CheckpointRecordingController.Cancellation? = nil) async throws
    -> CheckpointRecordingController.Result {
    let url = try await TestVideo.write(frames: 20, framesPerSecond: 10)
    defer { try? FileManager.default.removeItem(at: url) }
    let controller = CheckpointRecordingController()
    controller.thumbnailCount = Self.thumbnailCount
    return await controller.scan(url, cancelling: cancellation)
  }

  @Test("A scan that is not cancelled visits every preview point and tells the delegate")
  func uncancelledScanCompletes() async throws {
    let result = try await scan()
    #expect(result.succeeded == true)
    #expect(result.thumbnails?.count == Self.thumbnailCount + 1)
    #expect(result.checkpoints.first == .start)
    #expect(result.checkpoints.last == .finish)
    #expect(result.checkpoints.filter { $0 == .seek }.count == Self.thumbnailCount + 1)
    #expect(result.checkpoints.filter { $0 == .seekEnd }.count == Self.thumbnailCount + 1)
    #expect(!result.checkpoints.contains(.open))
  }

  @Test("A scan cancelled before it starts reads nothing and does not tell the delegate")
  func cancelledBeforeStart() async throws {
    let result = try await scan(cancelling: .init(checkpoint: .start))
    #expect(result.checkpoints == [.start])
    #expect(result.thumbnails == nil)
  }

  @Test("Cancelling while the file is opened interrupts opening it")
  func cancelledWhileOpening() async throws {
    let result = try await scan(cancelling: .init(checkpoint: .start, passesCheck: true))
    #expect(result.checkpoints == [.start, .open, .finish])
    #expect(result.thumbnails == nil)
  }

  @Test("A scan cancelled once the streams of the file are read stops there")
  func cancelledAfterStreamInfo() async throws {
    let result = try await scan(cancelling: .init(checkpoint: .streamInfo))
    #expect(result.checkpoints == [.start, .streamInfo, .finish])
    #expect(result.thumbnails == nil)
  }

  @Test("A scan cancelled before a seek does not seek", arguments: [1, 3])
  func cancelledBeforeSeek(occurrence: Int) async throws {
    let result = try await scan(cancelling: .init(checkpoint: .seek, occurrence: occurrence))
    let seeks = result.checkpoints.filter { $0 == .seek }.count
    #expect(seeks == occurrence)
    #expect(result.checkpoints.suffix(2) == [.seek, .finish])
    #expect(result.thumbnails == nil)
  }

  @Test("A scan cancelled after a seek decodes no frame there", arguments: [1, 3])
  func cancelledAfterSeek(occurrence: Int) async throws {
    let result = try await scan(cancelling: .init(checkpoint: .seekEnd, occurrence: occurrence))
    #expect(result.checkpoints.filter { $0 == .seekEnd }.count == occurrence)
    #expect(result.checkpoints.suffix(2) == [.seekEnd, .finish])
    #expect(result.thumbnails == nil)
  }

  @Test("A scan cancelled before decoding a frame decodes no further frame", arguments: [1, 3])
  func cancelledBeforeDecode(occurrence: Int) async throws {
    let result = try await scan(cancelling: .init(checkpoint: .decode, occurrence: occurrence))
    #expect(result.checkpoints.filter { $0 == .decode }.count == occurrence)
    // The scan leaves the preview point it was decoding and stops before seeking to the next one.
    #expect(result.checkpoints.suffix(3) == [.decode, .seek, .finish])
    #expect(result.thumbnails == nil)
  }

  @Test("A scan cancelled after it visited every preview point does not tell the delegate")
  func cancelledAtFinish() async throws {
    let result = try await scan(cancelling: .init(checkpoint: .finish))
    #expect(result.checkpoints.filter { $0 == .seek }.count == Self.thumbnailCount + 1)
    #expect(result.checkpoints.last == .finish)
    #expect(result.thumbnails == nil)
  }
}
