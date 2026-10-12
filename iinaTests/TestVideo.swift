//
//  TestVideo.swift
//  iinaTests
//
//  Writes short videos for tests that decode video.
//

import AVFoundation
import CoreVideo
import Foundation

enum TestVideo {

  /// The errors writing a test video can raise.
  enum WriteError: Error {
    case noPixelBufferPool
    case appendFailed(Error?)
    case writeFailed(Error?)
  }

  /// Write an H.264 video of the given number of frames, every frame a key frame, to a new file in the temporary directory.
  /// - Returns: The URL of the file written.
  static func write(frames: Int, framesPerSecond: Int32, width: Int = 64, height: Int = 48) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("iinaTests-\(UUID().uuidString).mp4")
    let writing = try Writing(url: url, frames: frames, framesPerSecond: framesPerSecond, width: width, height: height)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      writing.appendFrames { continuation.resume(with: $0) }
    }
    await writing.writer.finishWriting()
    guard writing.writer.status == .completed else { throw WriteError.writeFailed(writing.writer.error) }
    return url
  }

  /// The writing of one video.
  ///
  /// This is `@unchecked Sendable` because once writing has started its state is only used on the serial queue the writer input
  /// asks for frames on.
  private final class Writing: @unchecked Sendable {

    let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let pool: CVPixelBufferPool
    private let frames: Int
    private let framesPerSecond: Int32
    private var frame = 0
    private let queue = DispatchQueue(label: "iinaTests.TestVideo")

    init(url: URL, frames: Int, framesPerSecond: Int32, width: Int, height: Int) throws {
      writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
      input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 1],
      ])
      input.expectsMediaDataInRealTime = false
      adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
      writer.add(input)
      guard writer.startWriting() else { throw WriteError.writeFailed(writer.error) }
      writer.startSession(atSourceTime: .zero)
      guard let pool = adaptor.pixelBufferPool else { throw WriteError.noPixelBufferPool }
      self.pool = pool
      self.frames = frames
      self.framesPerSecond = framesPerSecond
    }

    /// Append every frame, then call `done` once.
    func appendFrames(done: @escaping @Sendable (Result<Void, Error>) -> Void) {
      input.requestMediaDataWhenReady(on: queue) { [self] in
        while input.isReadyForMoreMediaData && frame < frames {
          guard appendFrame() else {
            input.markAsFinished()
            done(.failure(WriteError.appendFailed(writer.error)))
            return
          }
          frame += 1
        }
        if frame == frames {
          input.markAsFinished()
          done(.success(()))
        }
      }
    }

    /// Append the current frame, a shade of grey that lightens from frame to frame.
    /// - Returns: Whether the frame was appended.
    private func appendFrame() -> Bool {
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
      guard let buffer, CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return false }
      if let base = CVPixelBufferGetBaseAddress(buffer) {
        let shade = Int32(frame * 255 / max(frames - 1, 1))
        memset(base, shade, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      return adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: framesPerSecond))
    }
  }
}
