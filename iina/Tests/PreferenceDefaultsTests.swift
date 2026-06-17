//
//  PreferenceDefaultsTests.swift
//  iinaTests
//
//  Created for the ui-driven-mpv-options iteration (SPEC requirement 1 /
//  PLAN Phase 2).
//
//  Regression guard: locks every curated default baked into
//  `Preference.defaultPreference` from `mpv/mpv.conf` so future edits to
//  either file surface as a test failure rather than silent drift.
//
//  Only the rows marked ✓ in the SPEC coverage table are asserted here.
//  Rows marked **NEW** are added in Phase 3 and asserted by the same
//  suite after that phase.
//

import XCTest
import AppKit
@testable import IINA

final class PreferenceDefaultsTests: XCTestCase {

  /// The mpv.conf keys this suite covers. `setUp` clears any
  /// developer-persisted value for these keys so the registration domain
  /// (i.e. `Preference.defaultPreference`) is what `object(forKey:)`
  /// resolves to. `tearDown` restores the original values.
  private static let coveredKeys: [Preference.Key] = [
    // VideoAdvanced
    .hardwareDecoder, .iccForceContrast, .vdLavcDr,
    .scale, .cscale, .dscale, .scaleAntiring,
    .correctDownscaling, .linearDownscaling, .sigmoidUpscaling,
    .hdrComputePeak, .hdrPeakPercentile, .hdrContrastRecovery,
    .dither, .libplaceboOpts,
    // SPEC Phase 3 — NEW keys
    .vdLavcSoftwareFallback, .forceWindow, .savePositionOnQuit,
    .inputMediaKeys, .subAuto,
    // SPEC Phase 3 — legacy keys with baked curated defaults
    .initialWindowSizePosition, .maxVolume, .ytdlEnabled, .ytdlRawOptions,
    .subShadowSize, .subTextColorString,
    .screenshotFormat, .screenshotTemplate, .screenshotJpegQuality,
    .screenshotJpegSourceChroma, .screenshotPngCompression,
    .screenshotWebpLossless, .screenshotWebpQuality,
    .screenshotJxlDistance, .screenshotJxlEffort, .screenshotHighBitDepth,
    // Window / playback
    .border, .hidpiWindowScale, .autofitLarger, .cursorAutohide,
    .keepOpenOnFileEnd, .osc, .forceSeekable,
    // Audio
    .adLavcDownmix, .audioChannels, .audioFileAuto, .audioLanguage,
    .softVolume,
    // Subtitle
    .subLang, .subTextSize, .subFilePaths,
    // OSD
    .osdOnSeek, .osdBarH, .osdBarBorderSize, .osdBorderSize,
    .osdFontSize, .osdFractions, .osdPlayingMsg, .osdFont,
    .osdDuration, .osdPlayingMsgDuration,
    // Schema
    .prefVersion
  ]

  private var snapshot: [String: Any?] = [:]

  override func setUp() {
    super.setUp()
    let ud = UserDefaults.standard
    for key in Self.coveredKeys {
      // Capture the currently-resolved object (nil included) so tearDown
      // can restore the exact state.
      let resolved = ud.object(forKey: key.rawValue)
      snapshot[key.rawValue] = resolved
      // Clear the application-domain entry so the registration domain
      // (Preference.defaultPreference) is authoritative.
      ud.removeObject(forKey: key.rawValue)
    }
    // Register the production defaults. This mirrors
    // `AppDelegate.registerUserDefaultValues()` but is safe to call again.
    let defaultsMap = [String: Any](uniqueKeysWithValues:
                                    Preference.defaultPreference.map { ($0.0.rawValue, $0.1) })
    ud.register(defaults: defaultsMap)
  }

  override func tearDown() {
    let ud = UserDefaults.standard
    for (rawKey, original) in snapshot {
      if let value = original {
        ud.set(value, forKey: rawKey)
      } else {
        ud.removeObject(forKey: rawKey)
      }
    }
    snapshot.removeAll()
    super.tearDown()
  }

  // MARK: - Helpers

  private func raw(_ key: Preference.Key) -> Any? {
    UserDefaults.standard.object(forKey: key.rawValue)
  }

  /// NSNumber returned by UserDefaults can bridge to Int; assert equality
  /// robustly regardless of whether the registered literal was Int or
  /// NSNumber-tagged.
  private func assertInt(_ key: Preference.Key, _ expected: Int, _ message: String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    let rawValue = raw(key)
    let got: Int? = {
      if let i = rawValue as? Int { return i }
      if let n = rawValue as? NSNumber { return n.intValue }
      return nil
    }()
    XCTAssertNotNil(got,
                    "\(key.rawValue): expected Int \(expected), got non-number \(String(describing: rawValue)). \(message)",
                    file: file, line: line)
    XCTAssertEqual(got, expected,
                   "\(key.rawValue): expected \(expected), got \(String(describing: rawValue)). \(message)",
                   file: file, line: line)
  }

  private func assertFloat(_ key: Preference.Key, _ expected: Float,
                           file: StaticString = #filePath, line: UInt = #line) {
    let rawValue = raw(key)
    guard let num = rawValue as? NSNumber else {
      XCTFail("\(key.rawValue): expected Float \(expected), got non-number \(String(describing: rawValue)).",
              file: file, line: line)
      return
    }
    let got = num.floatValue
    XCTAssertEqual(got, expected, accuracy: 1e-5,
                   "\(key.rawValue): expected \(expected), got \(String(describing: rawValue)).",
                   file: file, line: line)
  }

  private func assertBool(_ key: Preference.Key, _ expected: Bool,
                          file: StaticString = #filePath, line: UInt = #line) {
    let num = raw(key) as? NSNumber
    XCTAssertEqual(num?.boolValue, expected,
                   "\(key.rawValue): expected \(expected), got \(String(describing: raw(key))).",
                   file: file, line: line)
  }

  private func assertString(_ key: Preference.Key, _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(raw(key) as? String, expected,
                   "\(key.rawValue): expected \"\(expected)\", got \(String(describing: raw(key))).",
                   file: file, line: line)
  }

  // MARK: - Schema

  /// SPEC ui-driven-mpv-options Phase 3: prefVersion bumped to 3.
  func testPrefVersionBumped() {
    assertInt(.prefVersion, 3)
  }

  // MARK: - Video / GPU / scale / colour / HDR (VideoAdvanced)

  /// hwdec=auto (already curated pre-Phase-2; asserted to lock it).
  func testHardwareDecoder() {
    assertInt(.hardwareDecoder, Preference.HardwareDecoderOption.auto.rawValue)
  }

  /// icc-force-contrast=1000
  func testIccForceContrast() {
    assertInt(.iccForceContrast, 1000)
  }

  /// vd-lavc-dr=yes
  func testVdLavcDr() {
    assertBool(.vdLavcDr, true)
  }

  /// scale=bilinear
  func testScale() {
    assertInt(.scale, Preference.ScaleOption.bilinear.rawValue)
  }

  /// cscale=bilinear
  func testCscale() {
    assertInt(.cscale, Preference.ScaleOption.bilinear.rawValue)
  }

  /// dscale=bilinear
  func testDscale() {
    assertInt(.dscale, Preference.ScaleOption.bilinear.rawValue)
  }

  /// scale-antiring=0.0
  func testScaleAntiring() {
    assertFloat(.scaleAntiring, 0.0)
  }

  /// correct-downscaling=no
  func testCorrectDownscaling() {
    assertBool(.correctDownscaling, false)
  }

  /// linear-downscaling=no
  func testLinearDownscaling() {
    assertBool(.linearDownscaling, false)
  }

  /// sigmoid-upscaling=no
  func testSigmoidUpscaling() {
    assertBool(.sigmoidUpscaling, false)
  }

  /// hdr-compute-peak=no
  func testHdrComputePeak() {
    assertBool(.hdrComputePeak, false)
  }

  /// hdr-peak-percentile=100
  func testHdrPeakPercentile() {
    assertFloat(.hdrPeakPercentile, 100)
  }

  /// hdr-contrast-recovery=0.0
  func testHdrContrastRecovery() {
    assertFloat(.hdrContrastRecovery, 0.0)
  }

  /// dither=no
  func testDither() {
    assertInt(.dither, Preference.DitherOption.no.rawValue)
  }

  /// libplacebo-opts=preset=fast
  func testLibplaceboOpts() {
    assertString(.libplaceboOpts, "preset=fast")
  }

  // MARK: - Window / playback

  /// border=no
  func testBorder() {
    assertBool(.border, false)
  }

  /// hidpi-window-scale=yes
  func testHidpiWindowScale() {
    assertBool(.hidpiWindowScale, true)
  }

  /// autofit-larger=100%x100%
  func testAutofitLarger() {
    assertString(.autofitLarger, "100%x100%")
  }

  /// cursor-autohide=1000
  func testCursorAutohide() {
    assertString(.cursorAutohide, "1000")
  }

  /// keep-open=yes (legacy key `keepOpenOnFileEnd`; SPEC guessed `keepOpen`).
  func testKeepOpen() {
    assertBool(.keepOpenOnFileEnd, true)
  }

  /// osc=no
  func testOsc() {
    assertInt(.osc, Preference.OscOption.no.rawValue)
  }

  /// force-seekable=yes
  func testForceSeekable() {
    assertBool(.forceSeekable, true)
  }

  // MARK: - Audio

  /// ad-lavc-downmix=yes
  func testAdLavcDownmix() {
    assertBool(.adLavcDownmix, true)
  }

  /// audio-channels=stereo
  func testAudioChannels() {
    assertInt(.audioChannels, Preference.AudioChannelsOption.stereo.rawValue)
  }

  /// audio-file-auto=fuzzy
  func testAudioFileAuto() {
    assertInt(.audioFileAuto, Preference.AudioFileAutoOption.fuzzy.rawValue)
  }

  /// alang=en,eng,zh,chi
  func testAudioLanguage() {
    assertString(.audioLanguage, "en,eng,zh,chi")
  }

  /// volume=80 (legacy key `softVolume`; SPEC guessed `volume`).
  func testVolume() {
    assertInt(.softVolume, 80)
  }

  // MARK: - Subtitle

  /// slang=chi,zh-CN,jpn,sc,chs (legacy key `subLang`; SPEC guessed `subtitleLanguage`).
  func testSubtitleLanguage() {
    assertString(.subLang, "chi,zh-CN,jpn,sc,chs")
  }

  /// sub-font-size=43 (legacy key `subTextSize`).
  func testSubTextSize() {
    assertFloat(.subTextSize, 43)
  }

  /// sub-file-paths=ass:srt:sub:subs:subtitles
  func testSubFilePaths() {
    assertString(.subFilePaths, "ass:srt:sub:subs:subtitles")
  }

  // MARK: - OSD

  /// osd-on-seek=msg-bar
  func testOsdOnSeek() {
    assertString(.osdOnSeek, "msg-bar")
  }

  /// osd-bar-h=2
  func testOsdBarH() {
    assertInt(.osdBarH, 2)
  }

  /// osd-bar-border-size=0.2
  func testOsdBarBorderSize() {
    assertFloat(.osdBarBorderSize, 0.2)
  }

  /// osd-border-size=0
  func testOsdBorderSize() {
    assertFloat(.osdBorderSize, 0.0)
  }

  /// osd-font-size=40
  func testOsdFontSize() {
    assertInt(.osdFontSize, 40)
  }

  /// osd-fractions=yes
  func testOsdFractions() {
    assertBool(.osdFractions, true)
  }

  /// osd-playing-msg="${filename}"
  func testOsdPlayingMsg() {
    assertString(.osdPlayingMsg, "${filename}")
  }

  /// osd-font="Microsoft Yahei"
  func testOsdFont() {
    assertString(.osdFont, "Microsoft Yahei")
  }

  /// osd-duration=2000
  func testOsdDuration() {
    assertInt(.osdDuration, 2000)
  }

  /// osd-playing-msg-duration=3000
  func testOsdPlayingMsgDuration() {
    assertInt(.osdPlayingMsgDuration, 3000)
  }

  // MARK: - SPEC Phase 3: NEW + legacy keys with baked curated defaults

  /// vd-lavc-software-fallback=60. SPEC:Phase-7 revert — Phase 3
  /// had this under `hwdecSoftwareFallback` assuming
  /// `hwdec-software-fallback` was the canonical mpv option name,
  /// but mpv 0.38.0 (the libmpv IINA ships) has
  /// `vd-lavc-software-fallback`. The user's mpv.conf line was never
  /// a typo. Curated default 60.
  func testVdLavcSoftwareFallback() {
    assertInt(.vdLavcSoftwareFallback, 60)
  }

  /// force-window=immediate (NEW key).
  func testForceWindow() {
    assertString(.forceWindow, "immediate")
  }

  /// geometry=50%:50% (legacy key `initialWindowSizePosition`;
  /// SPEC guessed `geometry`; verify-legacy pattern — already wired).
  func testGeometry() {
    assertString(.initialWindowSizePosition, "50%:50%")
  }

  /// save-position-on-quit=no (NEW key; decoupled from resumeLastPosition
  /// which still controls resume-playback).
  func testSavePositionOnQuit() {
    assertBool(.savePositionOnQuit, false)
  }

  /// input-media-keys=no (NEW key; replaces hard-force).
  func testInputMediaKeys() {
    assertBool(.inputMediaKeys, false)
  }

  /// ytdl=yes (legacy key `ytdlEnabled`; default already matched curated).
  func testYtdl() {
    assertBool(.ytdlEnabled, true)
  }

  /// ytdl-raw-options-append=cookies-from-browser=edge
  /// (legacy key `ytdlRawOptions`; SPEC guessed `ytdlRawOptionsAppend`).
  func testYtdlRawOptionsAppend() {
    assertString(.ytdlRawOptions, "cookies-from-browser=edge")
  }

  /// volume-max=200 (legacy key `maxVolume`; SPEC guessed `volumeMax`).
  func testVolumeMax() {
    assertInt(.maxVolume, 200)
  }

  /// sub-shadow-offset=0 (legacy key `subShadowSize`; verify-legacy pattern —
  /// IINA key named "size" but wired to mpv's sub-shadow-offset).
  func testSubShadowOffset() {
    assertFloat(.subShadowSize, 0)
  }

  /// sub-color=#F0FFFFFF (legacy key `subTextColorString`; verify-legacy
  /// pattern — IINA's subtitle text color IS mpv's sub-color).
  func testSubColor() {
    let expected = NSColor(srgbRed: 1, green: 1, blue: 1,
                           alpha: CGFloat(0xf0) / 255)
      .usingColorSpace(.deviceRGB)!.mpvColorString
    assertString(.subTextColorString, expected)
  }

  /// sub-auto=fuzzy (NEW key; replaces hard-force; distinct from
  /// IINA's own subAutoLoadIINA).
  func testSubAuto() {
    assertString(.subAuto, "fuzzy")
  }

  /// screenshot-format=png (legacy key `screenshotFormat`; already matched).
  func testScreenshotFormat() {
    assertInt(.screenshotFormat, Preference.ScreenshotFormat.png.rawValue)
  }

  /// screenshot-template=~~desktop/MPV-%P-N%n (legacy key `screenshotTemplate`).
  func testScreenshotTemplate() {
    assertString(.screenshotTemplate, "~~desktop/MPV-%P-N%n")
  }

  /// screenshot-jpeg-quality=100
  func testScreenshotJpegQuality() {
    assertInt(.screenshotJpegQuality, 100)
  }

  /// screenshot-jpeg-source-chroma=no
  func testScreenshotJpegSourceChroma() {
    assertBool(.screenshotJpegSourceChroma, false)
  }

  /// screenshot-png-compression=5
  func testScreenshotPngCompression() {
    assertInt(.screenshotPngCompression, 5)
  }

  /// screenshot-webp-lossless=yes
  func testScreenshotWebpLossless() {
    assertBool(.screenshotWebpLossless, true)
  }

  /// screenshot-webp-quality=100
  func testScreenshotWebpQuality() {
    assertInt(.screenshotWebpQuality, 100)
  }

  /// screenshot-jxl-distance=0
  func testScreenshotJxlDistance() {
    assertInt(.screenshotJxlDistance, 0)
  }

  /// screenshot-jxl-effort=5
  func testScreenshotJxlEffort() {
    assertInt(.screenshotJxlEffort, 5)
  }

  /// screenshot-high-bit-depth=yes
  func testScreenshotHighBitDepth() {
    assertBool(.screenshotHighBitDepth, true)
  }
}
