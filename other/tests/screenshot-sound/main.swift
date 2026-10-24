var checks = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
  guard value() else { print("FAILED: \(description)"); exit(1) }
  checks += 1; print("PASS: \(description)")
}
func pump(_ predicate: () -> Bool) {
  let end = Date().addingTimeInterval(3)
  while !predicate() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
  check(predicate(), "asynchronous screenshot reaches its terminal state")
}
Preference.register()
defer { Preference.defaults.removePersistentDomain(forName: Preference.domain) }
check(Preference.bool(for: .screenshotPlaySound), "factory default enables screenshot sound")
Preference.set(false, for: .screenshotPlaySound)
Preference.defaults.synchronize()
check(!UserDefaults(suiteName: Preference.domain)!.bool(forKey: Preference.Key.screenshotPlaySound.rawValue),
      "the disabled choice survives a new defaults instance")
ScreenshotSound.play()
check(playedSounds.isEmpty, "disabled feedback never calls system playback")
Preference.defaults.removeObject(forKey: Preference.Key.screenshotPlaySound.rawValue)
check(Preference.bool(for: .screenshotPlaySound), "resetting the stored choice restores the enabled factory default")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: Utility.screenshotCacheURL, withIntermediateDirectories: true)
defer {
  try? FileManager.default.removeItem(at: directory)
  try? FileManager.default.removeItem(at: Utility.screenshotCacheURL)
}
func png(red: UInt8 = 255, green: UInt8 = 0) -> Data {
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  let pixels = bitmap.bitmapData!
  for index in 0..<4 {
    pixels[index * 4] = red; pixels[index * 4 + 1] = green
    pixels[index * 4 + 2] = 0; pixels[index * 4 + 3] = 255
  }
  return bitmap.representation(using: .png, properties: [:])!
}
func output(file: Bool, data: Data? = png()) -> URL {
  let url = (file ? directory : Utility.screenshotCacheURL).appendingPathComponent(UUID().uuidString + ".png")
  if let data { try! data.write(to: url) }
  return url
}
func preferences(file: Bool, clipboard: Bool, preview: Bool = true, sound: Bool = true) {
  Preference.set(file, for: .screenshotSaveToFile)
  Preference.set(clipboard, for: .screenshotCopyToClipboard)
  Preference.set(preview, for: .screenshotShowPreview)
  Preference.set(sound, for: .screenshotPlaySound)
  Preference.set(false, for: .enableFFmpegImageDecoder)
}
func submit(_ player: CallbackFixture) -> UInt64 {
  check(player.screenshot(), "native screenshot request is accepted")
  return screenshotTestLastID(player.mpv.mpv)
}
func reply(_ player: CallbackFixture, _ id: UInt64, url: URL?, error: Int32 = 0) {
  let event = url.map { url in url.path.withCString { screenshotTestCreateReply(id, error, $0)! } }
    ?? screenshotTestCreateReply(id, error, nil)!
  // Exercise the actual event branch with memory that is destroyed before the
  // main-queue callback runs, just as a subsequent mpv_wait_event invalidates it.
  DispatchQueue.global().sync {
    player.mpv.handleScreenshotReply(UnsafePointer(event))
    screenshotTestDestroyReply(event)
  }
}
func complete(file: Bool, clipboard: Bool, preview: Bool = true, sound: Bool = true,
              decodable: Bool = true, copySucceeds: Bool = true,
              filenameProvided: Bool = true, fileFound: Bool = true, expected: Int) {
  preferences(file: file, clipboard: clipboard, preview: preview, sound: sound)
  let url = output(file: file, data: fileFound ? (decodable ? png() : Data("invalid image".utf8)) : nil)
  TestPasteboard.shared.writeSucceeds = copySucceeds
  let beforeSounds = playedSounds.count, beforeWrites = TestPasteboard.shared.writes.count
  let player = CallbackFixture()
  let id = submit(player)
  reply(player, id, url: filenameProvided ? url : nil)
  pump { player.mainWindow.active.isEmpty }
  check(playedSounds.count - beforeSounds == expected,
        "file=\(file), clipboard=\(clipboard), preview=\(preview), enabled=\(sound), decoded=\(decodable), copied=\(copySucceeds), filename=\(filenameProvided), found=\(fileFound): \(expected) sound")
  check(player.mainWindow.ended.count == 1, "each terminal screenshot ends its own feedback once")
  if file && fileFound { check(FileManager.default.fileExists(atPath: url.path), "feedback preserves the saved image") }
  if clipboard && decodable && filenameProvided && fileFound {
    check(TestPasteboard.shared.writes.count == beforeWrites + 1, "clipboard destination is attempted exactly once")
  }
  if !file && filenameProvided && fileFound { pump { !FileManager.default.fileExists(atPath: url.path) } }
}
for preview in [false, true] {
  complete(file: true, clipboard: false, preview: preview, expected: 1)
  complete(file: false, clipboard: true, preview: preview, expected: 1)
  complete(file: true, clipboard: true, preview: preview, expected: 1)
  complete(file: true, clipboard: true, preview: preview, sound: false, expected: 0)
}
complete(file: true, clipboard: false, decodable: false, expected: 1)
complete(file: false, clipboard: true, decodable: false, expected: 0)
complete(file: false, clipboard: true, copySucceeds: false, expected: 0)
complete(file: true, clipboard: true, copySucceeds: false, expected: 1)
complete(file: true, clipboard: true, filenameProvided: false, expected: 0)
complete(file: true, clipboard: true, fileFound: false, expected: 0)

preferences(file: false, clipboard: false)
let disabled = CallbackFixture()
check(!disabled.screenshot() && disabled.mainWindow.begun.isEmpty, "disabled screenshot destinations never arm feedback")
preferences(file: true, clipboard: false)
let noVideo = CallbackFixture(); noVideo.info.hasVideo = false
check(!noVideo.screenshot() && noVideo.mainWindow.begun.isEmpty, "missing video never arms screenshot feedback")
let stopped = CallbackFixture(); stopped.info.state = .shuttingDown
check(!stopped.screenshot() && screenshotTestSubmissions(stopped.mpv.mpv) == 0,
      "teardown cannot submit screenshot work to mpv")
let states: [PlayerState] = [.loading, .starting, .loaded, .playing, .paused, .stopping, .idle, .shuttingDown, .shutDown]
for state in states {
  let player = CallbackFixture(); player.info.state = state
  let soundsBefore = playedSounds.count, writesBefore = TestPasteboard.shared.writes.count
  check(player.screenshot() == state.loaded, "screenshot readiness matches actual \(state) state")
  check(screenshotTestSubmissions(player.mpv.mpv) == (state.loaded ? 1 : 0), "\(state) submits only a ready video")
  if state.loaded {
    player.cancelScreenshotRequests()
    check(player.mainWindow.active.isEmpty, "cancelling accepted \(state) request releases feedback")
  } else {
    for mapping in [KeyMapping(action: ["screenshot", "each-frame"], rawAction: "screenshot each-frame"),
                    KeyMapping(action: ["screenshot", "unexpected"], rawAction: "screenshot unexpected"),
                    KeyMapping(action: ["seek", "5"], rawAction: "seek 5")] {
      check(!player.screenshot(fromKeyBinding: mapping), "\(state) cannot bypass readiness with \(mapping.rawAction)")
    }
    check(player.mpv.rawCommands.isEmpty && player.mainWindow.begun.isEmpty,
          "\(state) rejects unsupported bindings before raw-command routing or feedback")
  }
  check(playedSounds.count == soundsBefore && TestPasteboard.shared.writes.count == writesBefore && player.osdCount == 0,
        "entry/cancel in \(state) publishes no stale sound, clipboard or OSD")
}

let immediateFailure = CallbackFixture()
screenshotTestSetStatus(immediateFailure.mpv.mpv, -12)
let alertsBeforeImmediate = Utility.alerts.count
check(!immediateFailure.screenshot() && immediateFailure.mainWindow.active.isEmpty
      && immediateFailure.mainWindow.ended.count == 1 && Utility.alerts.count == alertsBeforeImmediate + 1,
      "failed enqueue ends feedback immediately without waiting for a nonexistent reply")
let missingCore = CallbackFixture(); missingCore.mpv.mpv = nil
check(!missingCore.screenshot() && missingCore.mainWindow.active.isEmpty,
      "an unavailable core reports submission failure and releases feedback")
let failed = CallbackFixture(), failedID = submit(failed)
let failedSoundCount = playedSounds.count
reply(failed, failedID, url: nil, error: -12)
pump { failed.mainWindow.active.isEmpty }
check(playedSounds.count == failedSoundCount && failed.mainWindow.ended.count == 1,
      "asynchronous engine failure stays silent and terminates once")

preferences(file: true, clipboard: true)
TestPasteboard.shared.writeSucceeds = true
let simultaneous = CallbackFixture()
let firstID = submit(simultaneous), secondID = submit(simultaneous)
check(firstID != secondID && MPVController.UserData.isScreenshot(firstID)
      && !MPVController.UserData.isScreenshot(1_000_000), "request IDs are unique inside a dedicated command namespace")
let firstURL = output(file: true, data: png()), secondURL = output(file: true, data: png(red: 0, green: 255))
let previewsBefore = PreviewFixture.urls.count
reply(simultaneous, secondID, url: secondURL)
pump { simultaneous.mainWindow.ended.count == 1 }
check(simultaneous.mainWindow.active.count == 1 && PreviewFixture.urls.last! == secondURL,
      "an out-of-order reply uses its exact filename and cannot end another pending request")
reply(simultaneous, firstID, url: firstURL)
pump { simultaneous.mainWindow.active.isEmpty }
check(PreviewFixture.urls[previewsBefore] == secondURL && PreviewFixture.urls[previewsBefore + 1] == firstURL,
      "borrowed result filenames survive event destruction without directory-order guessing")
let once = playedSounds.count, endedOnce = simultaneous.mainWindow.ended.count
reply(simultaneous, firstID, url: firstURL)
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
check(playedSounds.count == once && simultaneous.mainWindow.ended.count == endedOnce,
      "duplicate replies cannot publish a screenshot or finish feedback twice")

preferences(file: true, clipboard: false, preview: false, sound: true)
let snapped = CallbackFixture(), snappedID = submit(snapped), snappedURL = output(file: true)
let beforeSnapSounds = playedSounds.count, beforeSnapWrites = TestPasteboard.shared.writes.count
let beforeSnapDecodes = DecodeObserver.shared.calls
preferences(file: false, clipboard: true, preview: true, sound: false)
reply(snapped, snappedID, url: snappedURL)
pump { snapped.mainWindow.active.isEmpty }
check(playedSounds.count == beforeSnapSounds + 1 && TestPasteboard.shared.writes.count == beforeSnapWrites
      && FileManager.default.fileExists(atPath: snappedURL.path), "destination and sound intent remain those of the accepted request")
check(DecodeObserver.shared.calls == beforeSnapDecodes, "file-only screenshots without previews never decode an unused image")

preferences(file: true, clipboard: false)
let fileReady = CallbackFixture(), fileReadyID = submit(fileReady), fileReadyURL = output(file: true)
let releaseFilePreview = DispatchSemaphore(value: 0)
DecodeObserver.shared.blockNext = releaseFilePreview
let beforeFileReadySound = playedSounds.count
reply(fileReady, fileReadyID, url: fileReadyURL)
var filePreviewStarted = false
pump {
  if !filePreviewStarted { filePreviewStarted = DecodeObserver.shared.started.wait(timeout: .now()) == .success }
  return filePreviewStarted && playedSounds.count == beforeFileReadySound + 1
}
check(fileReady.mainWindow.active.count == 1 && fileReady.osdCount == 0,
      "saved-file sound is immediate while an optional preview still decodes on its worker")
releaseFilePreview.signal()
pump { fileReady.mainWindow.active.isEmpty }
check(playedSounds.count == beforeFileReadySound + 1,
      "preview completion cannot repeat the already delivered saved-file sound")

for invalidation in ["cancel", "generation", "url", "stop", "shutdown"] {
  preferences(file: false, clipboard: true)
  let player = CallbackFixture(), id = submit(player), url = output(file: false)
  let beforeSounds = playedSounds.count, beforeWrites = TestPasteboard.shared.writes.count
  if invalidation == "generation" { player.info.trackSelectionGeneration += 1 }
  else if invalidation == "url" { player.info.currentURL = URL(fileURLWithPath: "/replacement.mkv") }
  else {
    player.cancelScreenshotRequests()
    if invalidation == "stop" { player.info.state = .stopping }
    if invalidation == "shutdown" { player.info.state = .shuttingDown }
    check(player.mainWindow.active.isEmpty, "\(invalidation) immediately releases feedback before its reply")
  }
  reply(player, id, url: url)
  pump { player.mainWindow.active.isEmpty && !FileManager.default.fileExists(atPath: url.path) }
  check(playedSounds.count == beforeSounds && TestPasteboard.shared.writes.count == beforeWrites && player.osdCount == 0,
        "\(invalidation) rejects stale publication and cleans only its exact cache output")
}

preferences(file: false, clipboard: true)
let duringDecode = CallbackFixture(), duringID = submit(duringDecode), duringURL = output(file: false)
let releaseDecode = DispatchSemaphore(value: 0)
DecodeObserver.shared.blockNext = releaseDecode
let beforeDecodeSounds = playedSounds.count, beforeDecodeWrites = TestPasteboard.shared.writes.count
reply(duringDecode, duringID, url: duringURL)
var decoderStarted = false
pump {
  if !decoderStarted { decoderStarted = DecodeObserver.shared.started.wait(timeout: .now()) == .success }
  return decoderStarted
}
duringDecode.cancelScreenshotRequests(close: true)
check(duringDecode.mainWindow.active.isEmpty, "shutdown can invalidate feedback while the worker decoder is still busy")
releaseDecode.signal()
pump { !FileManager.default.fileExists(atPath: duringURL.path) }
check(playedSounds.count == beforeDecodeSounds && TestPasteboard.shared.writes.count == beforeDecodeWrites && duringDecode.osdCount == 0,
      "a decoded image cannot publish after its request was invalidated")

preferences(file: false, clipboard: true)
let outsideCache = CallbackFixture(), outsideID = submit(outsideCache), outsideURL = output(file: true)
reply(outsideCache, outsideID, url: outsideURL)
pump { outsideCache.mainWindow.active.isEmpty }
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
check(FileManager.default.fileExists(atPath: outsideURL.path), "clipboard cleanup cannot remove an unexpected non-cache destination")
check(!DecodeObserver.shared.usedMain, "all native image decoding runs outside main")
check(!playedSounds.isEmpty && Set(playedSounds).count == 1,
      "all screenshot requests reuse one valid native system sound object")
var id = playedSounds[0], isUI: UInt32 = 0
var size = UInt32(MemoryLayout<UInt32>.size)
let status = AudioServicesGetProperty(kAudioServicesPropertyIsUISound, UInt32(MemoryLayout<SystemSoundID>.size),
                                      &id, &size, &isUI)
check(status == noErr && isUI == 1, "native sound respects the macOS sound-effects policy")
print("Screenshot sound/lifecycle: \(checks) checks passed; production request/reply/decode paths, personal defaults and clipboard untouched.")
