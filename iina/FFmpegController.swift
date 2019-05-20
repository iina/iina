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
  func didGenerateThumbnails(_ thumbnails: [FFmpegThumbnail], forFileAtPath path: String, succeeded: Bool)
  func didUpdateThumbnails(_ thumbnails: [FFmpegThumbnail]?, forFileAtPath path: String, withProgress progress: Int)
}

@objc(FFmpegController)
class FFmpegController: NSObject {

  private static let thumbnailQueue = DispatchQueue(label: "com.colliderli.iina.FFMpegController")
  private var currentWorkItem: DispatchWorkItem!
  private var thumbnails = [FFmpegThumbnail]()
  private var timestamps = Set<Int64>()
  private var lastDelegateCallbackTime = 0 as CFTimeInterval

  public var delegate: FFmpegControllerDelegate? = nil
  public var thumbnailCount: Int {
    return thumbnails.count
  }

  public func generateThumbnailsForFile(atPath path: String) {
    currentWorkItem?.cancel()
    timestamps.removeAll()
    thumbnails.removeAll()
    currentWorkItem = DispatchWorkItem { [weak self] in
      guard let `self` = self else {
        return
      }
      // Swift apparently cannot reason about our category methods, so force the
      // method call to occur through the Objective-C runtime.
      let succeeded = (`self` as AnyObject).synchronouslyGenerateThumbnailsForFile(atPath: path)
      `self`.delegate?.didGenerateThumbnails(`self`.thumbnails, forFileAtPath: path, succeeded: succeeded)
    }
    FFmpegController.thumbnailQueue.async(execute: currentWorkItem)
  }

  @objc func save(thumbnail: UnsafeMutableRawPointer?, width: Int, height: Int, index: Int, timestamp: Int, forFileAtPath path: String) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let cgImage = CGContext(data: thumbnail, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else {
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
}

// MARK: Bridge
extension FFmpegController {
  @objc func handleNewTimestamp(_ timestamp: Int64, progress: Int, forFileAtPath path: String) -> Bool {
    if timestamps.insert(timestamp).inserted {
      let currentTime = CACurrentMediaTime()
      if 1 < currentTime - lastDelegateCallbackTime {
        delegate?.didUpdateThumbnails(nil, forFileAtPath: path, withProgress: progress)
        lastDelegateCallbackTime = currentTime
      }
      return true
    }
    return false
  }
}
