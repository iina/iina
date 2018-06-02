//
//  FFmpegController.swift
//  iina
//
//  Created by Saagar Jha on 5/28/18.
//  Copyright © 2018 lhc. All rights reserved.
//

import CoreGraphics

struct FFmpegThumbnail {
  let image: NSImage
  let timestamp: Double
}

protocol FFmpegControllerDelegate {
  func didGenerateThumbnails(_ thumbnails: [FFmpegThumbnail]?, forFileAtPath path: String)
  func didUpdateThumbnails(_ thumbnails: [FFmpegThumbnail]?, forFileAtPath path: String, withProgress progress: Int)
}

class FFmpegController {
  private static let defaultThumbnailCount = 100
  private static let defaultThumbnailWidth = 240.0

  private static let thumbnailQueue = DispatchQueue(label: "com.colliderli.iina.FFMpegController")
  private var currentWorkItem: DispatchWorkItem!
  private var thumbnails = [FFmpegThumbnail]()
  private var timestamps = Set<Int64>()
  private var lastDelegateCallbackTime = CACurrentMediaTime()

  public var delegate: FFmpegControllerDelegate? = nil
  public var thumbnailCount: Int {
    return thumbnails.count
  }

  public func generateThumbnailsForFile(atPath path: String) {
    currentWorkItem?.cancel()
    currentWorkItem = DispatchWorkItem { [weak self] in
      guard let `self` = self else {
        return
      }
      `self`.delegate?.didGenerateThumbnails(`self`.synchronouslyGenerateThumbnailsForFile(atPath: path) ? `self`.thumbnails: nil, forFileAtPath: path)
    }
    FFmpegController.thumbnailQueue.async(execute: currentWorkItem)
  }

  private func synchronouslyGenerateThumbnailsForFile(atPath path: String) -> Bool {
    // DO NOT pass this into a function taking a UnsafePointer<AVFormatContext>,
    // except when you are releasing the resources associated with it. Use
    // &formatContext instead-otherwise formatContext will not be updated
    var useOnlyAsAHandle_formatContext: UnsafeMutablePointer<AVFormatContext>? = nil
    guard avformat_open_input(&useOnlyAsAHandle_formatContext, path, nil, nil) >= 0,
      var formatContext = useOnlyAsAHandle_formatContext else {
        return false
    }
    defer {
      avformat_close_input(&useOnlyAsAHandle_formatContext)
    }

    guard avformat_find_stream_info(formatContext, nil) >= 0 else {
      return false
    }

    guard let videoStreamIndex = (0..<Int(formatContext.pointee.nb_streams)).first(where: { index in
      formatContext.pointee.streams[index]?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO }),
      let videoStream = formatContext.pointee.streams[videoStreamIndex]?.pointee else {
        return false
    }

    guard av_q2d(videoStream.avg_frame_rate) >= 0 else {
      return false
    }

    guard let codec = avcodec_find_decoder(videoStream.codecpar.pointee.codec_id) else {
      return false
    }

    guard var codecContext = avcodec_alloc_context3(codec) else {
      return false
    }
    defer {
      var optionalCodecContext = Optional.some(codecContext)
      avcodec_free_context(&optionalCodecContext)
    }

    guard avcodec_parameters_to_context(codecContext, videoStream.codecpar) >= 0 else {
      return false
    }

    codecContext.pointee.time_base = videoStream.time_base

    guard avcodec_open2(codecContext, codec, nil) >= 0 else {
      return false
    }
    defer {
      avcodec_close(codecContext)
    }

    guard var frame = av_frame_alloc() else {
      return false
    }
    defer {
      var optionalFrame = Optional.some(frame)
      av_frame_free(&optionalFrame)
    }

    let thumbnailWidth = FFmpegController.defaultThumbnailWidth
    let thumbnailHeight = thumbnailWidth / (Double(codecContext.pointee.width) / Double(codecContext.pointee.height))

    guard var frameRGB = av_frame_alloc() else {
      return false
    }
    defer {
      var optionalFrameRGB = Optional.some(frameRGB)
      av_frame_free(&optionalFrameRGB)
    }

    frameRGB.pointee.width = Int32(thumbnailWidth)
    frameRGB.pointee.height = Int32(thumbnailHeight)
    frameRGB.pointee.format = AV_PIX_FMT_RGBA.rawValue

    let size = Int(av_image_get_buffer_size(AV_PIX_FMT_RGBA, Int32(thumbnailWidth), Int32(thumbnailHeight), 1))
    guard size >= 0 else {
      return false
    }

    guard let frameRGBBuffer = av_malloc(size)?.bindMemory(to: UInt8.self, capacity: size) else {
      return false
    }
    defer {
      av_free(frameRGBBuffer)
    }

    guard withUnsafeMutablePointer(to: &frameRGB.pointee.data, {
      let data = UnsafeMutableRawPointer($0).assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
      return withUnsafeMutablePointer(to: &frameRGB.pointee.linesize) {
        let linesize = UnsafeMutableRawPointer($0).assumingMemoryBound(to: Int32.self)
        // We convert to Int here because otherwise we'd have to annotate the
        // top level call to withUnsafeMutablePointer with a large tuple
        return Int(av_image_fill_arrays(data, linesize, frameRGBBuffer, AV_PIX_FMT_RGBA, frameRGB.pointee.width, frameRGB.pointee.height, 1))
      }
    }) >= 0 else {
      return false
    }

    let swsContext = sws_getContext(codecContext.pointee.width, codecContext.pointee.height, codecContext.pointee.pix_fmt, frameRGB.pointee.width, frameRGB.pointee.height, AV_PIX_FMT_RGBA, SWS_BILINEAR, nil, nil, nil)
    guard swsContext != nil else {
      return false
    }
    defer {
      sws_freeContext(swsContext)
    }

    let interval = Double(av_rescale_q(formatContext.pointee.duration, avTimeBaseQ, videoStream.time_base)) / Double(FFmpegController.defaultThumbnailCount)
    let timebase = av_q2d(videoStream.time_base)

    for index in 0...FFmpegController.defaultThumbnailCount {
      let seekPosition = Int64(interval * Double(index)) + videoStream.start_time
      avcodec_flush_buffers(codecContext)
      av_seek_frame(formatContext, Int32(videoStreamIndex), seekPosition, AVSEEK_FLAG_BACKWARD)

      var packet = AVPacket()
      readloop:
        while av_read_frame(formatContext, &packet) == 0 {
          defer {
            av_packet_unref(&packet)
          }

          if packet.stream_index == videoStreamIndex {
            if avcodec_send_packet(codecContext, &packet) != 0 {
              break
            }
          }

          switch avcodec_receive_frame(codecContext, &frame.pointee) {
          case averror(EAGAIN):
            continue readloop
          case .min..<0:
            break readloop
          default:
            break
          }

          if !timestamps.insert(frame.pointee.best_effort_timestamp).inserted {
            let currentTime = CACurrentMediaTime()
            if 1 < currentTime - lastDelegateCallbackTime {
              delegate?.didUpdateThumbnails(nil, forFileAtPath: path, withProgress: index)
              lastDelegateCallbackTime = currentTime
            }
          }

          guard withUnsafePointer(to: &frame.pointee.data, {
            let data = UnsafeRawPointer($0).assumingMemoryBound(to: UnsafePointer<UInt8>?.self)
            return withUnsafePointer(to: &frame.pointee.linesize) {
              let linesize = UnsafeRawPointer($0).assumingMemoryBound(to: Int32.self)
              return withUnsafeMutablePointer(to: &frameRGB.pointee.data) {
                let dataRGB = UnsafeMutableRawPointer($0).assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
                return withUnsafePointer(to: &frameRGB.pointee.linesize) {
                  let linesizeRGB = UnsafeRawPointer($0).assumingMemoryBound(to: Int32.self)
                  // We convert to Int here because otherwise we'd have to
                  // annotate the top level call to withUnsafePointer with a
                  // large tuple
                  return Int(sws_scale(swsContext, data, linesize, 0, codecContext.pointee.height, dataRGB, linesizeRGB))
                }
              }
            }
          }) > 0 else {
            return false
          }

          save(thumbnail: frameRGB.pointee, width: Int(frameRGB.pointee.width), height: Int(frameRGB.pointee.height), index: index, timestamp: Int(Double(frame.pointee.best_effort_timestamp) * timebase), forFileAtPath: path)
          break
      }
    }
    return true
  }

  func save(thumbnail: AVFrame, width: Int, height: Int, index: Int, timestamp: Int, forFileAtPath path: String) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let cgImage = CGContext(data: UnsafeMutableRawPointer(thumbnail.data.0), width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else {
      return
    }
    let image = NSImage(cgImage: cgImage, size: .zero)
    let thumbnail = FFmpegThumbnail(image: image, timestamp: Double(timestamp))
    thumbnails.append(thumbnail)
    let currentTime = CACurrentMediaTime()
    // Rate limit-only call the didUpdateThumbnails delegate method for every
    // ten thumbnails we generate, or if at least a second has gone by
    if thumbnails.count % 10 == 0 || 1 < currentTime - lastDelegateCallbackTime {
      delegate?.didUpdateThumbnails(thumbnails, forFileAtPath: path, withProgress: index)
      lastDelegateCallbackTime = currentTime
    }
  }

  static func videoDuration(forFileAtPath path: String) -> Double {
    // DO NOT pass this into a function taking a UnsafePointer<AVFormatContext>,
    // except when you are releasing the resources associated with it. Use
    // &formatContext instead-otherwise formatContext will not be updated
    var useOnlyAsAHandle_formatContext: UnsafeMutablePointer<AVFormatContext>? = nil
    guard avformat_open_input(&useOnlyAsAHandle_formatContext, path, nil, nil) >= 0,
      var formatContext = useOnlyAsAHandle_formatContext else {
        return -1
    }
    defer {
      avformat_close_input(&useOnlyAsAHandle_formatContext)
    }

    var duration = formatContext.pointee.duration;
    if duration <= 0 {
      guard avformat_find_stream_info(formatContext, nil) >= 0 else {
        return -1;
      }
      duration = formatContext.pointee.duration;
    }
    return Double(duration) / Double(AV_TIME_BASE)
  }
}
