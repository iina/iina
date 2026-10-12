//
//  CacheConfiguration.swift
//  iina
//

import Foundation

/// The values IINA's cache settings give `mpv`'s cache options.
///
/// These are set when the `mpv` core is initialized and again when a setting changes. Nothing that runs when playback moves to
/// another entry sets them.
enum CacheConfiguration {

  /// The value of `mpv`'s `cache` option for the "Enable cache" setting.
  static func cache(enabled: Bool) -> String {
    return enabled ? "yes" : "no"
  }

  /// The value of `mpv`'s `demuxer-max-bytes` option for the cache size setting, which is in KiB.
  static func demuxerMaxBytes(kibibytes: Int) -> String {
    return "\(kibibytes)KiB"
  }
}
