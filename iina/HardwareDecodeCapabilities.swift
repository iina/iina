//
//  HardwareDecodeCapabilities.swift
//  iina
//
//  Created by low-batt on 5/23/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation
import VideoToolbox

/// Cache containing information about the hardware decoding capabilities of this Mac.
///
/// It is desirable to cache this information because the [Video Toolbox](https://developer.apple.com/documentation/videotoolbox)
/// method  [VTIsHardwareDecodeSupported](https://developer.apple.com/documentation/videotoolbox/vtishardwaredecodesupported(_:))
/// is long running and should not be called on the main thread. Instead another thread is used and the information is cached for when
/// code that is running on the main thread needs it.
class HardwareDecodeCapabilities {
  /// The `HardwareDecodeCapabilities` singleton object.
  static let shared = HardwareDecodeCapabilities()

  /// The hardware decoding capabilities of this Mac will be checked for the codecs in this list.
  private let codecs = [
    kCMVideoCodecType_AppleProRes422,
    kCMVideoCodecType_AppleProRes422HQ,
    kCMVideoCodecType_AppleProRes422LT,
    kCMVideoCodecType_AppleProRes422Proxy,
    kCMVideoCodecType_AppleProRes4444,
    kCMVideoCodecType_AppleProRes4444XQ,
    kCMVideoCodecType_AppleProResRAW,
    kCMVideoCodecType_AppleProResRAWHQ,
    kCMVideoCodecType_AV1,
    kCMVideoCodecType_VP9]

  private var initialization: DispatchWorkItem?
  private var isInitialized = false

  /// Cache containing a map from video codec to whether hardware decoding is supported.
  private var supported: [CMVideoCodecType: Bool] = [:]

  /// Check the hardware decoding capabilities of this Mac and cache the results.
  ///
  /// As checking the capabilities takes a long time it is performed asynchronously. See `isHardwareDecodeSupported` for details.
  /// - Important: This method **must** be called before `isSupported` is called and only be called **once**.
  func checkCapabilities() {
    guard initialization == nil else {
      // Internal error. This method must only be called once.
      Logger.fatal("HardwareDecodeCapabilities is already initialized")
    }
    initialization = DispatchWorkItem() { [self] in
      for codec in codecs {
        supported[codec] = isHardwareDecodeSupported(codec)
      }
    }
    DispatchQueue.global(qos: .userInitiated).async { self.initialization!.perform() }
  }

  /// Whether this Mac supports hardware decoding for the given video codec.
  /// - Parameter codecType: The video codec as a
  ///     [CMVideoCodecType](https://developer.apple.com/documentation/coremedia/cmvideocodectype).
  /// - Returns: `true` if hardware decoding is supported;,`false` otherwise.
  func isSupported(_ codecType: CMVideoCodecType) -> Bool {
    if !isInitialized {
      guard let initialization = initialization else {
        // Internal error. The cache must be initialized before calling this method.
        Logger.fatal("HardwareDecodeCapabilities.checkCapabilities has not been called")
      }
      initialization.wait()
      isInitialized = true
    }
    guard let supported = supported[codecType] else {
      // Internal error. This codec must not be in the list of codecs above.
      Logger.fatal("HardwareDecodeCapabilities is missing support for codec \(codecType)")
    }
    return supported
  }

  /// Whether this Mac supports hardware decoding for the given video codec.
  /// - Parameter codecType: The video codec as a
  ///     [CMVideoCodecType](https://developer.apple.com/documentation/coremedia/cmvideocodectype).
  /// - Returns: true` if hardware decoding is supported;,`false` otherwise.
  /// - Important: This method calls
  ///     [VTIsHardwareDecodeSupported](https://developer.apple.com/documentation/videotoolbox/vtishardwaredecodesupported(_:)),
  ///     which if called on the main thread will cause Xcode to report: "This method should not be called on the main thread as it may
  ///     lead to UI unresponsiveness". Use a different thread to call this method. Do not call `isHardwareDecodeSupported`
  ///     from the main thread.
  private func isHardwareDecodeSupported(_ codecType: CMVideoCodecType) -> Bool {
    if #available(macOS 11.0, *) {
      VTRegisterSupplementalVideoDecoderIfAvailable(codecType)
    }
    if #available(macOS 10.13, *) {
      return VTIsHardwareDecodeSupported(codecType)
    }
    guard codecType != kCMVideoCodecType_AV1, codecType != kCMVideoCodecType_VP9 else {
      // Neither of these codecs are supported in older versions of macOS.
      return false
    }
    // Unable to determine. For how this information is used by IINA the safe answer is true.
    return true
  }

  private init() {}
}
