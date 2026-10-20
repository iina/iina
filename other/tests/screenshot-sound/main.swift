var checks = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
  precondition(value(), description)
  checks += 1
  print("PASS: \(description)")
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
defer { try? FileManager.default.removeItem(at: directory) }
let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let png = image.representation(using: .png, properties: [:])!

func complete(file: Bool, clipboard: Bool, preview: Bool = true, sound: Bool = true,
              decodable: Bool = true, copySucceeds: Bool = true,
              folderFound: Bool = true, fileFound: Bool = true, expected: Int) {
  let url = directory.appendingPathComponent(UUID().uuidString + ".png")
  try! (decodable ? png : Data("invalid image".utf8)).write(to: url)
  Utility.latestURL = fileFound ? url : nil
  TestPasteboard.shared.writeSucceeds = copySucceeds
  TestPasteboard.shared.writes = 0
  Preference.set(file, for: .screenshotSaveToFile)
  Preference.set(clipboard, for: .screenshotCopyToClipboard)
  Preference.set(preview, for: .screenshotShowPreview)
  Preference.set(sound, for: .screenshotPlaySound)
  let player = CallbackFixture()
  if !folderFound { player.mpv.folder = nil }
  let before = playedSounds.count
  player.screenshotCallback()
  check(playedSounds.count - before == expected,
        "file=\(file), clipboard=\(clipboard), preview=\(preview), enabled=\(sound), decoded=\(decodable), copied=\(copySucceeds), folder=\(folderFound), found=\(fileFound): \(expected) sound")
  RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  if file { check(FileManager.default.fileExists(atPath: url.path), "feedback preserves the saved image") }
  if clipboard && decodable && folderFound && fileFound {
    check(TestPasteboard.shared.writes == 1, "clipboard destination is attempted exactly once")
  }
}
for preview in [false, true] {
  complete(file: true, clipboard: false, preview: preview, expected: 1)
  complete(file: false, clipboard: true, preview: preview, expected: 1)
  complete(file: true, clipboard: true, preview: preview, expected: 1)
  complete(file: true, clipboard: true, preview: preview, sound: false, expected: 0)
}
complete(file: false, clipboard: false, expected: 0)
complete(file: true, clipboard: false, decodable: false, expected: 1)
complete(file: false, clipboard: true, decodable: false, expected: 0)
complete(file: false, clipboard: true, copySucceeds: false, expected: 0)
complete(file: true, clipboard: true, copySucceeds: false, expected: 1)
complete(file: true, clipboard: true, folderFound: false, expected: 0)
complete(file: true, clipboard: true, fileFound: false, expected: 0)
check(!playedSounds.isEmpty && Set(playedSounds).count == 1,
      "all screenshots reuse one valid native system sound object")
var id = playedSounds[0], isUI: UInt32 = 0
var size = UInt32(MemoryLayout<UInt32>.size)
let status = AudioServicesGetProperty(kAudioServicesPropertyIsUISound, UInt32(MemoryLayout<SystemSoundID>.size),
                                      &id, &size, &isUI)
check(status == noErr && isUI == 1, "native sound respects the macOS sound-effects policy")
print("Screenshot sound: \(checks) checks passed; playback intercepted, personal defaults and clipboard untouched.")
