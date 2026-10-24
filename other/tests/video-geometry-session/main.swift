setbuf(stdout, nil)
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message); checks += 1; print("PASS: \(message)")
}
let a = URL(fileURLWithPath: "/tmp/video-A.mkv"), b = URL(fileURLWithPath: "/tmp/video-B.mkv")
// A fresh player has no in-memory preset name when mpv restores watch-later vf.
for preset in ["4:3", "5:4", "16:10", "21:9"] {
  let writer = PlayerFixture()
  writer.setCrop(fromString: preset)
  let restored = PlayerFixture()
  restored.mpv.videoFilters = [writer.info.cropFilter!]
  restored.reloadSavedIINAfilters()
  check(restored.settingsUpdates == 1,
        "restoring a watch-later crop notifies an already-created sidebar")
  check(restored.info.unsureCrop == preset,
        "a fresh player recognizes the restored centered \(preset) preset")
  restored.reloadSavedIINAfilters()
  check(restored.settingsUpdates == 1, "unchanged filter reloads do not rebuild the sidebar")
  restored.mpv.videoFilters = []
  restored.reloadSavedIINAfilters()
  check(restored.info.unsureCrop == "None" && restored.settingsUpdates == 2,
        "restored crop removal publishes None once")
}
for (source, display, rotation) in [
  (NSSize(width: 3840, height: 2160), NSSize(width: 3840, height: 2160), 0),
  (NSSize(width: 720, height: 576), NSSize(width: 1024, height: 576), 0),
  (NSSize(width: 1920, height: 1080), NSSize(width: 1920, height: 1080), 90)
] {
  let writer = PlayerFixture()
  writer.geometry = CropVideoGeometry(sourceSize: source, displaySize: display, rotation: rotation)
  writer.setCrop(fromString: "4:3")
  let params = writer.info.cropFilter!.params!
  let restored = PlayerFixture()
  restored.geometry = writer.geometry
  restored.mpv.videoFilters = [MPVFilter(name: "crop", label: Constants.FilterName.crop,
    params: ["@0": params["w"]!, "@1": params["h"]!, "@2": params["x"]!, "@3": params["y"]!, "exact": "1"])]
  restored.reloadSavedIINAfilters()
  check(restored.info.unsureCrop == "4:3", "native watch-later parameter maps recognize rotated/anamorphic presets")
  restored.info.cropFilter = nil
  let shifted = MPVFilter.crop(w: Int(params["w"]!)!, h: Int(params["h"]!)!,
                               x: Int(params["x"]!)! + 1, y: Int(params["y"]!)!, exact: true)
  shifted.label = Constants.FilterName.crop
  restored.mpv.videoFilters = [shifted]
  restored.reloadSavedIINAfilters()
  check(restored.info.unsureCrop == "Custom", "a matching ratio at a different source position remains Custom")
}
let lateSource = PlayerFixture()
let centered = MPVFilter.crop(w: 960, h: 720, x: 160, y: 0, exact: true)
centered.label = Constants.FilterName.crop
lateSource.mpv.videoFilters = [centered]
lateSource.geometry = CropVideoGeometry(sourceSize: .zero, displaySize: .zero, rotation: 0)
lateSource.reloadSavedIINAfilters()
check(lateSource.info.unsureCrop == "Custom", "preloaded filters cannot invent a preset before source geometry exists")
lateSource.geometry = CropVideoGeometry(sourceSize: NSSize(width: 1280, height: 720),
                                      displaySize: NSSize(width: 1280, height: 720), rotation: 0)
lateSource.info.justStartedFile = true
lateSource.reloadSavedIINAfilters()
check(lateSource.info.unsureCrop == "4:3" && lateSource.settingsUpdates == 2,
      "playback restart publishes the recognized preset when source geometry becomes ready")
let committedCustom = PlayerFixture()
committedCustom.mpv.videoFilters = [centered]
committedCustom.info.cropFilter = centered
committedCustom.info.unsureCrop = "Custom"
committedCustom.reloadSavedIINAfilters()
check(committedCustom.info.unsureCrop == "Custom" && committedCustom.geometryReads == 0,
      "ordinary seek/restart preserves committed Custom without repolling source geometry")
check(Aspect(string:"0:1") == nil && Aspect(string:"1:0") == nil &&
      Aspect(string:String(repeating:"9",count:400)+":1") == nil,
      "invalid or overflowing proportions never create an unusable aspect object")
let p = PlayerFixture()
p.captureDefaults()
p.start(a)
p.mpv.options["video-aspect-override"] = "4:3"
p.mpv.options["video-rotate"] = "90"
p.mpv.options["video-zoom"] = "0.4"
p.info.unsureAspect = "4:3"; p.info.unsureCrop = "Custom"
let crop = MPVFilter.crop(w: 1000, h: 600, x: 100, y: 60); crop.label = Constants.FilterName.crop
p.info.cropFilter = crop
let unrelated = MPVFilter(rawString: "@plugin:negate")!
let unrelatedAfter = MPVFilter(rawString: "@after:hflip")!
p.mpv.videoFilters = [unrelated, crop, unrelatedAfter]
p.scopedTrackSettings.video[2] = VideoTrackProcessing(aspect: "16:9", rotation: 270)
p.scopedTrackSettings.setTarget(2, for: .videoGeometry)
p.info.videoTrackOrder = [2,1]; p.info.activeVideo = [2]
// A manual load updates currentURL before on_unload runs.
p.info.currentURL = b
p.save()
check(p.videoGeometrySession[a] != nil && p.videoGeometrySession[b] == nil,
      "early manual-open URL cannot save A's geometry under B")
p.start(b)
check(p.mpv.options["video-aspect-override"] == "-1" && p.info.rotation == 0,
      "unvisited B does not inherit A's aspect or rotation")
check(p.info.cropFilter == nil && p.info.unsureCrop == "None", "unvisited B has no stale crop")
check(p.mpv.videoFilters.contains { $0.label == "plugin" }, "unrelated plugin filters survive media geometry restoration")
check(p.scopedTrackSettings.video.isEmpty, "B does not inherit A's track profiles")
check(p.mpv.options["video-zoom"] == "0", "unvisited B resets A's video zoom")
p.save()
p.start(a)
check(p.info.unsureAspect == "4:3" && p.info.rotation == 90, "A restores its own aspect and rotation")
check(p.info.cropFilter?.isEqual(crop) == true && p.info.unsureCrop == "Custom", "A restores committed crop and its description")
check(p.mpv.videoFilters.map(\.label) == ["plugin",Constants.FilterName.crop,"after"],
      "restoration preserves crop order relative to unrelated filters")
check(p.mpv.options["video-zoom"] == "0.4", "A restores video zoom")
check(p.scopedTrackSettings.video[2]?.rotation == 270 && p.scopedTrackSettings.target(.videoColor) == 2,
      "A restores per-track settings and its shared editing target")
check(p.info.videoTrackOrder == [2,1] && p.refreshes.last == [2], "A restores selected video membership and order")
p.reloadSavedIINAfilters()
check(p.info.unsureCrop == "Custom", "playback restart does not erase the crop preset description")
for legacyDescription in ["None", ""] {
  p.info.unsureCrop = legacyDescription
  p.reloadSavedIINAfilters()
  check(p.info.unsureCrop == "Custom", "An actual crop normalizes legacy None/empty descriptions to Custom")
}
p.info.unsureCrop = "4:3"
p.reloadSavedIINAfilters()
check(p.info.unsureCrop == "4:3", "Reloading an unchanged named preset preserves its description")
p.info.cropFilter = nil
p.reloadSavedIINAfilters()
check(p.info.unsureCrop == "Custom", "An externally restored crop is identified as Custom")
// Reset/default is a meaningful state and must replace earlier saved edits.
p.mpv.options["video-aspect-override"] = "-1"; p.mpv.options["video-rotate"] = "0"
p.mpv.videoFilters = [unrelated]; p.info.unsureCrop = "None"
p.scopedTrackSettings.video = [:]; p.info.activeVideo = []
p.save(); p.start(b); p.save(); p.start(a)
check(p.info.unsureAspect == "Default" && p.info.cropFilter == nil && p.scopedTrackSettings.video.isEmpty,
      "Reset remains reset after A-B-A instead of resurrecting old edits")
check(p.refreshes.last == [], "explicit None video membership survives reopening")
// Cancel an editor before snapshotting the committed state.
p.mainWindow.interactiveMode.onExit = { p.mpv.videoFilters = [crop]; p.info.cropFilter = crop; p.info.unsureCrop = "Saved" }
p.save(); p.start(b); p.save(); p.start(a)
check(p.info.cropFilter?.isEqual(crop) == true, "leaving during crop editing saves the committed selection")
// Failed loads must not overwrite the saved state for a known item.
p.save(); let count = p.videoGeometrySession.count
p.start(a, loaded: false); p.mpv.videoFilters = []; p.save()
check(p.videoGeometrySession.count == count && p.videoGeometrySession[a]?.filters.isEmpty == false,
      "failed reopen cannot overwrite an earlier successful snapshot")
// UI references must follow the real filter list even after external commands.
p.info.flipFilter = MPVFilter.flip(); p.info.mirrorFilter = MPVFilter.mirror()
p.mpv.videoFilters = []; p.reloadSavedIINAfilters()
check(p.info.cropFilter == nil && p.info.flipFilter == nil && p.info.mirrorFilter == nil && p.info.unsureCrop == "None",
      "removed/watch-later filters cannot leave phantom crop/flip/mirror UI state")
check(MediaVideoGeometryState.aspectDescription(for: 16.0/9, preferred: "Default") == "16:9",
      "watch-later aspect is reflected accurately in the menu")
p.start(a); p.info.videoTracks = [.init(id: 1)]
p.videoGeometrySession[a]?.videoTarget = 2
p.restoreForTesting()
check(p.scopedTrackSettings.target(.videoGeometry) == 0 && p.scopedTrackSettings.video[2] == nil,
      "missing track IDs cannot restore profiles onto another source")
p.mpv.failWrites = true; p.start(b)
check(p.warnings > 0, "native restore failures are reported")
p.mpv.failWrites = false
// Source dimensions in file metadata must not determine presets after track switches.
for (source, display, rotation) in [
  (NSSize(width:1080,height:1920), NSSize(width:1080,height:1920), 0),
  (NSSize(width:720,height:576), NSSize(width:1024,height:576), 0),
  (NSSize(width:1920,height:1080), NSSize(width:1920,height:1080), 90)
] {
  p.geometry = CropVideoGeometry(sourceSize: source, displaySize: display, rotation: rotation)
  p.setCrop(fromString: "4:3")
  let filter = p.info.cropFilter!, rect = filter.params!
  let w = Double(rect["w"]!)!, h = Double(rect["h"]!)!
  check(w <= source.width && h <= source.height && w > 0 && h > 0,
        "crop preset stays inside the currently decoded rotated/anamorphic source")
  let selected = p.geometry.selectionRect(forFilterRect: NSRect(x:Double(rect["x"]!)!, y:Double(rect["y"]!)!, width:w,height:h))
  check(abs(selected.width/selected.height*p.geometry.pixelAspectRatio - 4.0/3) < 0.01,
        "crop preset uses display proportions rather than stale file pixels")
}
p.geometry = CropVideoGeometry(sourceSize:.zero,displaySize:.zero,rotation:0)
p.info.cropFilter = nil; p.setCrop(fromString:"16:9")
check(p.info.cropFilter == nil, "crop with no decoded video safely does nothing")
p.mpv.options["window-scale"] = "1"
for pending in 0..<3 {
  p.info.justStartedFile = pending == 0; p.info.justOpenedFile = pending == 1; p.info.state.loaded = pending != 2
  p.windowScaleChanged()
}
check(p.mainWindow.scales.isEmpty, "loading/watch-later window-scale notifications never resize a window")
p.info.justStartedFile = false; p.info.justOpenedFile = false; p.info.state.loaded = true
p.mainWindow.isCropTransitionInProgress = true
p.windowScaleChanged()
check(p.mainWindow.scales.isEmpty, "render-size notifications cannot compete with the crop transition's window geometry")
p.mainWindow.isCropTransitionInProgress = false
p.windowScaleChanged()
check(p.mainWindow.scales == [1], "explicit scale commands still reach the native resize action")
let stopped = PlayerFixture()
stopped.captureDefaults(); stopped.start(a)
stopped.mpv.options["panscan"] = "1"
stopped.mainWindow.videoAspectTransitionOriginalPanscan = 0.3
stopped.save()
check(stopped.videoGeometrySession[a]?.options["panscan"] == "0.3",
      "Stop during an animated transform never snapshots the temporary fill")
let cli = PlayerFixture()
cli.mpv.options["video-aspect-override"] = "16:9"
cli.start(a)
check(cli.info.unsureAspect == "16:9", "first-load defaults include CLI options applied after engine initialization")
cli.mpv.options["video-aspect-override"] = "4:3"; cli.save(); cli.start(b)
check(cli.info.unsureAspect == "16:9", "new media restores configured defaults without inheriting edits")
let configuredCrop = PlayerFixture()
configuredCrop.mpv.videoFilters = [crop]
configuredCrop.start(a)
check(configuredCrop.info.cropFilter != nil && configuredCrop.info.unsureCrop != "None",
      "a configured crop is never presented as None at the first load")
let blockedOutput = PlayerFixture()
blockedOutput.setFlip(true); blockedOutput.setMirror(true)
let committedFilters = blockedOutput.mpv.videoFilters.map(\.stringFormat)
blockedOutput.mainWindow.interactiveMode.isActive = true
let geometryReadsBeforeRejection = blockedOutput.geometryReads
for _ in 0..<3 {
  blockedOutput.setCrop(fromString: "4:3")
  blockedOutput.setCrop(fromString: "None")
  blockedOutput.setFlip(false); blockedOutput.setMirror(false)
}
check(blockedOutput.info.cropFilter == nil && blockedOutput.geometryReads == geometryReadsBeforeRejection &&
      blockedOutput.mpv.videoFilters.map(\.stringFormat) == committedFilters,
      "menu presets and flip/mirror shortcuts cannot alter active Crop output or source coordinates")
blockedOutput.mainWindow.interactiveMode.isActive = false
blockedOutput.setCrop(fromString: "4:3")
blockedOutput.setFlip(false); blockedOutput.setMirror(false)
check(blockedOutput.info.cropFilter != nil && blockedOutput.mpv.videoFilters.isEmpty,
      "preset Crop and flip/mirror changes remain available after editor release")
let stoppedOutput = PlayerFixture()
stoppedOutput.info.state.active = false
for _ in 0..<3 {
  stoppedOutput.setCrop(fromString: "4:3"); stoppedOutput.setCrop(fromString: "None")
  stoppedOutput.setFlip(true); stoppedOutput.setMirror(true)
}
check(stoppedOutput.info.cropFilter == nil && stoppedOutput.mpv.videoFilters.isEmpty && stoppedOutput.geometryReads == 0,
      "unavailable playback rejects output filters and Crop presets before reading the native geometry")
print("Completed \(checks) production video geometry session checks.")

extension PlayerFixture { func restoreForTesting() { restoreVideoTrackGeometryForCurrentMedia() } }
