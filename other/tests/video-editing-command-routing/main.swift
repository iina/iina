setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1
  print("PASS:", message)
}
func blocks(_ text: String, index: Int = 0) -> Bool {
  OSDCommandRouting.commands(in: text).contains { OSDCommandRouting.changesVideoGeometry($0, playlistIndex: index) }
}
let structural = [
  "cycle video", "cycle vid", "set video-rotate 90", "set_property video-aspect-override 4:3",
  "cycle-values !reverse video-aspect-override 4:3 16:9", "add video-zoom .1", "del video-crop",
  "multiply video-scale-x 2", "set options/video-pan-x .2", "set file-local-options/video-align-y .3",
  "set vf crop=900:500", "set vf/0 crop=900:500", "change-list vf append crop=900:500", "vf add crop=900:500",
  "vf-command crop w 800", "set lavfi-complex '[vid1]null[vo]'", "cycle edition",
  "video-add external.mkv", "video-remove 1", "video-reload 1", "playlist-next", "playlist_prev",
  "playlist-next-playlist", "playlist-prev-playlist", "playlist-play-index current", "playlist-remove current",
  "playlist-remove 0", "set playlist-pos 1", "set playlist-pos-1 2", "loadfile replacement.mkv",
  "loadlist replacement.m3u replace", "apply-profile geometry", "load-config-file geometry.conf",
  "set volume 42; set video-rotate 180", "no-osd raw async set video-crop 900x500",
  "set ${user-data/property} 90"
]
let safe = [
  "seek 5", "seek -1 exact", "cycle pause", "set pause yes", "set volume 42", "add volume 2",
  "cycle mute", "multiply speed 1.1", "frame-step", "frame-back-step", "no-osd raw seek 5",
  "set time-pos 1", "add chapter 1", "cycle audio", "cycle sub", "set sub-delay .1", "set brightness 2",
  "af add volume=1", "playlist-clear", "playlist-move 0 1", "playlist-shuffle", "playlist-unshuffle",
  "playlist-remove 1", "loadfile another.mkv append", "loadlist another.m3u append-play",
  "loadfile another.mkv insert-next", "loadfile another.mkv insert-next-play",
  "loadfile another.mkv insert-at 1", "loadlist another.m3u insert-at-play 1",
  "show-text 'vf add crop=20:20; set video-rotate 90'", "set volume 30 # ; set video-rotate 90"
]
for text in structural { check(blocks(text), "classifies structural command: \(text)") }
for text in safe { check(!blocks(text), "preserves unrelated command: \(text)") }
for prefix in ["no-osd", "osd-auto", "osd-bar", "osd-msg", "osd-msg-bar", "raw", "expand-properties",
               "repeatable", "nonrepeatable", "nonscalable", "async", "sync"] {
  check(blocks("\(prefix) set video-rotate 90"), "prefix cannot bypass editing policy: \(prefix)")
}
check(!blocks("playlist-remove 0", index: 1) && blocks("playlist-remove 1", index: 1), "playlist removal compares the current index")
check(!blocks("quit") && !blocks("stop"), "editor policy preserves explicit quit and stop commands")

for mode in [InteractiveModeController.Mode.crop, .delogo] {
  let main = MainWindowController()
  main.standardWindowButtons = [NSButton()]
  main.interactiveMode.enter(mode: mode, selectWholeVideoByDefault: true)
  main.videoViewContainer.layoutSubtreeIfNeeded()
  if mode == .crop {
    let crop = main.videoViewContainer.subviews.compactMap { $0 as? CropBoxView }.first!
    crop.setZoom(2)
  }
  check(main.interactiveMode.isActive, "native \(mode) editor is active")
  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .control], timestamp: 0,
    windowNumber: main.window!.windowNumber, context: nil, characters: "v", charactersIgnoringModifiers: "v",
    isARepeat: false, keyCode: 9)!
  check(main.interactiveMode.handleEditorEvent(event) === event, "modified keys reach the production dispatcher in \(mode)")
  let mask = main.videoView.layer!.mask, transform = main.videoView.layer!.transform
  for text in structural {
    let count = engine.commands.count
    check(!main.handleKeyBinding(KeyMapping(rawAction: text)) && engine.commands.count == count,
          "production dispatcher blocks \(text) during \(mode)")
  }
  for text in safe {
    let count = engine.commands.count
    _ = main.handleKeyBinding(KeyMapping(rawAction: text))
    check(engine.commands.count == count + 1, "production dispatcher preserves \(text) during \(mode)")
  }
  check(main.interactiveMode.isActive && main.videoView.layer!.mask === mask &&
        CATransform3DEqualToTransform(main.videoView.layer!.transform, transform) && !main.standardWindowButtons[0].isEnabled,
        "rejected commands preserve native \(mode) presentation and controls")
  let api = JavascriptAPIMpv(main.player)
  for property in ["vid", "video", "vf", "lavfi-complex", "video-crop", "options/video-rotate", "file-local-options/video-aspect-override"] {
    let count = engine.calls.count
    api.set(property, JSValue(int32: 90, in: api.context))
    check(engine.calls.count == count, "raw JavaScript property cannot bypass \(mode): \(property)")
  }
  let count = engine.commands.count
  api.command("set", ["video-rotate", "90"])
  check(engine.commands.count == count, "raw JavaScript command cannot bypass \(mode)")
  api.set("volume", JSValue(int32: 42, in: api.context))
  check(engine.calls.last == "set:volume", "safe JavaScript property remains writable during \(mode)")
  api.command("seek", ["5"])
  check(engine.commands.count == count + 1, "safe JavaScript command remains available during \(mode)")
  let menu = MainMenuActionHandler(main.player)
  let actions = [#selector(menu.menuChangeAspect(_:)), #selector(menu.menuChangeCrop(_:)), #selector(menu.menuChangeRotation(_:)),
    #selector(menu.menuToggleFlip(_:)), #selector(menu.menuToggleMirror(_:)), #selector(menu.menuToggleVideoFilterString(_:)),
    #selector(menu.menuCycleTrack(_:))]
  for action in actions {
    let item = NSMenuItem(title: "Video", action: action, keyEquivalent: "")
    check(!menu.validateMenuItem(item), "visible video action is disabled during \(mode): \(action)")
  }
  let audio = NSMenuItem(title: "Audio", action: #selector(menu.menuCycleTrack(_:)), keyEquivalent: ""); audio.tag = 1
  check(menu.validateMenuItem(audio), "audio track menu stays available during \(mode)")
  let filters = engine.calls.count
  menu.toggleFilter(MPVProperty.vf)
  check(engine.calls.count == filters, "direct saved video filter action refuses \(mode)")
  menu.toggleFilter(MPVProperty.af)
  check(engine.calls.last == "audioFilter", "saved audio filters remain available during \(mode)")
  main.interactiveMode.exit()
  let commandCount = engine.commands.count
  check(main.handleKeyBinding(KeyMapping(rawAction: "set video-rotate 90")) && engine.commands.count == commandCount + 1,
        "geometry commands work after \(mode) exits")
  if engine.library != nil { check(engine.property("video-rotate") == "90", "accepted post-editor command changes real libmpv") }
  main.window?.close()
}

do {
  let main = MainWindowController()
  main.isCropTransitionInProgress = true
  let count = engine.commands.count
  check(!main.handleKeyBinding(KeyMapping(rawAction: "set video-rotate 180")) && engine.commands.count == count,
        "transition retains geometry ownership after the editor view exits")
  main.isCropTransitionInProgress = false
  for text in ["", " ", "\n\t"] {
    check(!main.handleKeyBinding(KeyMapping(rawAction: text)), "empty mapping is harmless in both dispatch layers")
    check(!main.handleKeyBinding(KeyMapping(rawAction: text, isIINACommand: true)), "empty internal mapping is harmless in both dispatch layers")
  }
  let menu = MainMenuActionHandler(main.player)
  let custom = NSMenuItem(title: "Custom", action: #selector(menu.menuChangeCrop(_:)), keyEquivalent: "")
  custom.representedObject = "Custom"
  check(menu.validateMenuItem(custom), "Custom Crop is enabled in an eligible native window")
  main.pipStatus = .inPIP
  check(!menu.validateMenuItem(custom), "Custom Crop menu shares PiP ownership eligibility")
  main.pipStatus = .notInPIP
  main.player.isInMiniPlayer = true
  check(!menu.validateMenuItem(custom), "Custom Crop menu shares music-mode ownership eligibility")
  main.player.isInMiniPlayer = false
  main.window?.close()
}

do {
  let main = MainWindowController(), api = JavascriptAPIMpv(nil)
  func allRawMethods() {
    _ = api.getFlag("pause"); _ = api.getNumber("volume"); _ = api.getString("video-rotate"); _ = api.getNative("track-list")
    api.set("volume", JSValue(int32: 42, in: api.context)); api.command("ignore", [])
    api.addHook("on_load", 0, JSValue(newObjectIn: api.context))
  }
  let count = engine.calls.count
  allRawMethods()
  check(engine.calls.count == count, "all seven raw JavaScript methods refuse a missing player")
  api.player = main.player
  for state in [PlayerState.shuttingDown, .shutDown] {
    main.player.info.state = state
    let count = engine.calls.count
    allRawMethods()
    check(engine.calls.count == count, "all seven raw JavaScript methods refuse \(state)")
  }
  main.player.info.state = .idle
  engine.available = false
  let countWithoutHandle = engine.calls.count
  allRawMethods()
  check(engine.calls.count == countWithoutHandle, "all seven raw JavaScript methods refuse a missing native handle")
  engine.available = true
  let countWithHandle = engine.calls.count
  allRawMethods()
  check(engine.calls.count == countWithHandle + 7, "idle plugin initialization retains all seven raw methods with a live handle")
  main.window?.close()
}
print("Completed \(checks) production video-editing command, menu and JavaScript lifecycle checks (native engine: \(engine.library != nil)).")
