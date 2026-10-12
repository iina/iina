//
//  CacheConfigurationTests.swift
//  iinaTests
//
//  Tests for the values IINA's cache settings give mpv's cache options.
//

import Testing
@testable import IINA

@Suite("Cache configuration")
struct CacheConfigurationTests {

  @Test("The cache option follows the \"Enable cache\" setting")
  func cacheFollowsSetting() {
    #expect(CacheConfiguration.cache(enabled: true) == "yes")
    #expect(CacheConfiguration.cache(enabled: false) == "no")
  }

  @Test("The demuxer-max-bytes option is the cache size setting in KiB", arguments: [0, 1, 153600])
  func demuxerMaxBytesInKibibytes(kibibytes: Int) {
    #expect(CacheConfiguration.demuxerMaxBytes(kibibytes: kibibytes) == "\(kibibytes)KiB")
  }
}
