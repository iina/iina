let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message)
  checks += 1
  print("PASS \(message)")
}
let player = PlayerCore()
let popup = VideoLUTPopUp(player: player)
func finishImports() {
  var finished = false
  DispatchQueue.main.async {
    VideoLUTPopUp.importQueue.async { DispatchQueue.main.async { finished = true } }
  }
  let deadline = Date().addingTimeInterval(5)
  while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
  precondition(finished, "import queue did not finish")
}
func choose(tag: Int) {
  popup.selectItem(withTag: tag)
  _ = NSApp.sendAction(popup.action!, to: popup.target, from: popup)
  finishImports()
}
func choose(path: String) {
  popup.select(popup.itemArray.first { $0.tag == 1 && ($0.representedObject as? String) == path })
  _ = NSApp.sendAction(popup.action!, to: popup.target, from: popup)
}
check(popup.itemArray.first?.tag == -2 && popup.item(at: 1)?.tag == -1
      && popup.item(at: 2)?.isSeparatorItem == true && popup.item(at: 3)?.tag == 0,
      "Delete, Import and neutral None lead the menu in order")
check(popup.itemArray.first?.isEnabled == false && popup.selectedTag() == 0,
      "None keeps removal disabled in an empty library")
let fixtures = Utility.appSupportDirUrl.deletingLastPathComponent().appendingPathComponent("fixtures")
try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
func fixtureCube(inverted: Bool) -> Data {
  var text = "LUT_3D_SIZE 2\n"
  for b in 0...1 { for g in 0...1 { for r in 0...1 {
    text += inverted ? "\(1-r) \(1-g) \(1-b)\n" : "\(r) \(g) \(b)\n"
  } } }
  return Data(text.utf8)
}
let fixture = fixtures.appendingPathComponent("Цвет-" + UUID().uuidString + ".cube")
try fixtureCube(inverted: true).write(to: fixture)
Utility.nextFile = fixture
choose(tag: -1)
let selected = popup.selectedItem?.representedObject as! String
check(popup.titleOfSelectedItem == fixture.deletingPathExtension().lastPathComponent, "import callback selects the Unicode LUT name")
check(FileManager.default.fileExists(atPath: selected) && selected != fixture.path, "popup applies its managed imported copy")
check(player.mpv.filters.count == 1 && player.mpv.filters[0].label == VideoLUTLibrary.filterLabel, "popup applies the output LUT")
check(Utility.alerts.isEmpty, "successful import produces no error")
check(popup.itemArray.first?.isEnabled == true, "a managed active LUT enables removal")
Utility.confirmation = .alertSecondButtonReturn
choose(tag: -2)
check((popup.selectedItem?.representedObject as? String) == selected && player.mpv.filters.count == 1
      && (try! VideoLUTLibrary(directory: Utility.appSupportDirUrl.appendingPathComponent("LUTs")).entries()).count == 1,
      "canceling removal preserves the active LUT and library")
Utility.nextFile = nil
choose(tag: -1)
check((popup.selectedItem?.representedObject as? String) == selected, "cancel import preserves the active selection")
let unrelated = MPVFilter(label: "other", paramString: "graph=%4%null")
player.mpv.filters.append(unrelated)
choose(tag: 0)
check(player.mpv.filters.map(\.label) == ["other"], "None removes only the owned LUT")
check(popup.itemArray.first?.isEnabled == false, "None disables removal even with saved LUTs")
choose(path: selected)
check(player.mpv.filters.count == 2, "an imported LUT is reusable")
let identity = fixtures.appendingPathComponent("Identity.cube")
try fixtureCube(inverted: false).write(to: identity)
Utility.nextFile = identity
player.failNextFilter = true
choose(tag: -1)
check((popup.selectedItem?.representedObject as? String) == selected && player.mpv.filters.count == 2,
      "failed application restores filters and popup selection")
check(Utility.alerts.last == "lut_apply_failed", "failed application reports an error")
player.scopedTrackSettings.setTarget(1, for: .videoColor)
popup.menuNeedsUpdate(popup.menu!)
check(popup.selectedTag() == 0, "an untouched source has its own neutral LUT setting")
choose(path: selected)
check(player.scopedTrackSettings.video[1]?.lutPath == selected && player.mpv.filters.count == 2,
      "a source LUT preserves the independent output LUT")
choose(tag: 0)
check(player.scopedTrackSettings.video[1]?.lutPath == nil && player.mpv.filters.count == 2,
      "source None leaves output processing unchanged")
let invalid = Utility.appSupportDirUrl.appendingPathComponent("invalid.cube")
try Data("LUT_3D_SIZE 2\n0 0 0\n".utf8).write(to: invalid)
Utility.nextFile = invalid
choose(tag: -1)
check(Utility.alerts.last == "lut_import_failed" && player.scopedTrackSettings.video[1]?.lutPath == nil,
      "malformed imports preserve the current source setting")
player.mainWindow.interactiveMode.isActive = true
popup.menuNeedsUpdate(popup.menu!)
check(!popup.isEnabled, "interactive crop disables LUT changes")
player.mainWindow.interactiveMode.isActive = false
player.scopedTrackSettings.setTarget(0, for: .videoColor)
popup.menuNeedsUpdate(popup.menu!)
choose(path: selected)
let second = PlayerCore()
second.scopedTrackSettings.video[1] = VideoTrackProcessing()
second.scopedTrackSettings.video[1]?.lutPath = selected
second.scopedTrackSettings.video[1]?.brightness = 27
second.scopedTrackSettings.video[2] = VideoTrackProcessing()
second.scopedTrackSettings.video[2]?.lutPath = "unrelated.cube"
second.mpv.filters = player.mpv.filters
let removalLibrary = VideoLUTLibrary(directory: Utility.appSupportDirUrl.appendingPathComponent("LUTs"))
func removeCurrent() {
  popup.menuNeedsUpdate(popup.menu!)
  Utility.confirmation = .alertFirstButtonReturn
  choose(tag: -2)
}
let idle = PlayerCore()
idle.info.state = .idle
idle.mpv.filters = player.mpv.filters
idle.scopedTrackSettings.video[1] = second.scopedTrackSettings.video[1]
idle.failNextRefresh = true
let stopped = PlayerCore()
stopped.info.state = .shuttingDown
stopped.mpv.filters = player.mpv.filters
let dormant = PlayerCore()
let dormantURL = URL(fileURLWithPath: "/saved-A.mkv")
var dormantSnapshot = MediaVideoGeometryState()
dormantSnapshot.video[3] = VideoTrackProcessing(rotation: 90, brightness: 42, lutPath: selected)
dormant.videoGeometrySession[dormantURL] = dormantSnapshot
second.mainWindow.interactiveMode.isActive = true
removeCurrent()
check(FileManager.default.fileExists(atPath: selected) && Utility.alerts.last == "lut_remove_crop",
      "an affected crop editor prevents removal")
second.scopedCropPreview = .init()
second.scopedCropPreview?.masterVF = "@lyina_lut:lavfi=graph=hidden-preview"
let saved = second.scopedTrackSettings.video.removeValue(forKey: 1)
second.mpv.filters = [unrelated]
removeCurrent()
check(FileManager.default.fileExists(atPath: selected) && Utility.alerts.last == "lut_remove_crop",
      "a temporarily hidden crop-preview Output LUT prevents removal")
second.scopedCropPreview = nil
second.scopedTrackSettings.video[1] = saved
second.mpv.filters = player.mpv.filters
second.mainWindow.interactiveMode.isActive = false
second.failNextRefresh = true
removeCurrent()
check(FileManager.default.fileExists(atPath: selected) && player.mpv.filters.count == 2 && second.scopedTrackSettings.video[1]?.lutPath == selected,
      "engine failure restores earlier players and retains the library copy")
second.failRemoval = true
removeCurrent()
check(FileManager.default.fileExists(atPath: selected) && second.scopedTrackSettings.video[1]?.lutPath == selected,
      "output-filter removal failure restores individual profiles")
second.failRemoval = false
let removedIndex = Utility.appSupportDirUrl.appendingPathComponent("LUTs/.removed.json")
second.onRefresh = { try! FileManager.default.createDirectory(at: removedIndex, withIntermediateDirectories: false) }
removeCurrent()
check(second.scopedTrackSettings.video[1]?.lutPath == selected && player.mpv.filters.count == 2
      && FileManager.default.fileExists(atPath: selected) && Utility.alerts.last == "lut_remove_failed",
      "registry write/read failure restores processing and leaves all LUT files intact")
try FileManager.default.removeItem(at: removedIndex)
let missing = URL(fileURLWithPath: selected)
let temporary = missing.appendingPathExtension("away")
second.onRefresh = { try! FileManager.default.moveItem(at: missing, to: temporary) }
removeCurrent()
check(second.scopedTrackSettings.video[1]?.lutPath == selected && player.mpv.filters.count == 2
      && Utility.alerts.last == "lut_remove_failed", "filesystem failure rolls back detached players")
check(dormant.videoGeometrySession[dormantURL]?.video[3]?.lutPath == selected,
      "filesystem failure also restores references belonging only to dormant sessions")
try FileManager.default.moveItem(at: temporary, to: missing)
popup.menuNeedsUpdate(popup.menu!)
removeCurrent()
check(!FileManager.default.fileExists(atPath: selected) && FileManager.default.fileExists(atPath: fixture.path),
      "confirmed deletion removes the managed copy and preserves the original")
let trashFolder = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                            appropriateFor: fixture, create: false)
let trashed = trashFolder.appendingPathComponent(URL(fileURLWithPath: selected).lastPathComponent)
check(try! Data(contentsOf: trashed) == Data(contentsOf: fixture), "confirmed deletion moves the actual LUT bytes to Trash")
try FileManager.default.moveItem(at: trashed, to: fixtures.appendingPathComponent("Recovered library copy.cube"))
check(player.mpv.filters.map(\.label) == ["other"] && second.mpv.filters.map(\.label) == ["other"],
      "confirmed removal disables matching Output LUTs in every player")
check(second.scopedTrackSettings.video[1]?.lutPath == nil && second.scopedTrackSettings.video[1]?.brightness == 27
      && second.scopedTrackSettings.video[2]?.lutPath == "unrelated.cube",
      "confirmed removal clears inactive source references without changing color or other LUTs")
check(dormant.videoGeometrySession[dormantURL]?.video[3]?.lutPath == nil
      && dormant.videoGeometrySession[dormantURL]?.video[3]?.brightness == 42
      && dormant.videoGeometrySession[dormantURL]?.video[3]?.rotation == 90,
      "confirmed removal detaches dormant sessions while preserving their other adjustments")
check(idle.mpv.filters.map(\.label) == ["other"] && idle.scopedTrackSettings.video[1]?.lutPath == nil
      && idle.failNextRefresh && stopped.mpv.filters.count == 2,
      "idle users are cleared without graph refresh and shutdown players remain untouched")
check(popup.selectedTag() == 0 && !popup.itemArray.contains(where: { ($0.representedObject as? String) == selected }),
      "removed LUT disappears while the neutral selection stays available")
do {
  try VideoLUTLibrary(directory: Utility.appSupportDirUrl.appendingPathComponent("LUTs"))
    .remove(.init(url: fixture))
  preconditionFailure("external file removal must fail")
} catch { check(FileManager.default.fileExists(atPath: fixture.path), "library removal rejects original/outside files") }
check(!(try! VideoLUTLibrary(directory: Utility.appSupportDirUrl.appendingPathComponent("LUTs")).entries()).contains { $0.url.path == selected },
      "removed entry stays hidden after library rediscovery")
Utility.nextFile = fixture
choose(tag: -1)
check((popup.selectedItem?.representedObject as? String) == selected && FileManager.default.fileExists(atPath: selected),
      "reimport restores the same managed LUT and applies it again")

func delayedImport(_ source: URL, beforeRelease: () -> Void) {
  let gate = DispatchSemaphore(value: 0)
  VideoLUTPopUp.importQueue.async { gate.wait() }
  Utility.nextFile = source
  popup.selectItem(withTag: -1)
  _ = NSApp.sendAction(popup.action!, to: popup.target, from: popup)
  var responded = false
  DispatchQueue.main.async { responded = true }
  RunLoop.current.run(until: Date().addingTimeInterval(0.03))
  check(responded, "the main queue responds while import preparation is waiting")
  beforeRelease()
  gate.signal()
  finishImports()
}
delayedImport(identity) {
  popup.selectItem(withTag: 0)
  _ = NSApp.sendAction(popup.action!, to: popup.target, from: popup)
}
check(!player.mpv.filters.contains { $0.label == VideoLUTLibrary.filterLabel },
      "a pending import never overwrites a newer None choice")
check((try! removalLibrary.entries()).contains { $0.name == "Identity" },
      "a completed pending import still adds its managed copy to the library")
let originalMedia = player.info.currentURL
delayedImport(fixture) { player.info.currentURL = URL(fileURLWithPath: "/another.mkv") }
check(!player.mpv.filters.contains { $0.label == VideoLUTLibrary.filterLabel },
      "import completion cannot apply to another media file")
player.info.currentURL = originalMedia
delayedImport(fixture) { player.info.trackSelectionGeneration += 1 }
check(!player.mpv.filters.contains { $0.label == VideoLUTLibrary.filterLabel },
      "reloading the same URL invalidates the old import context")
delayedImport(fixture) { player.scopedTrackSettings.setTarget(2, for: .videoColor) }
check(player.scopedTrackSettings.video[2]?.lutPath == nil && !player.mpv.filters.contains { $0.label == VideoLUTLibrary.filterLabel },
      "import completion preserves a newly chosen settings target")
player.scopedTrackSettings.setTarget(0, for: .videoColor)
popup.menuNeedsUpdate(popup.menu!)
choose(path: selected)
delayedImport(identity) {
  player.mpv.filters.removeAll { $0.label == VideoLUTLibrary.filterLabel }
}
check(!player.mpv.filters.contains { $0.label == VideoLUTLibrary.filterLabel },
      "a programmatic LUT reset also wins over an earlier import")
let unmanagedGraph = ProcessedVideoGraph.lutFilter(path: "/external-programmatic.cube")
delayedImport(identity) {
  player.mpv.filters.append(MPVFilter(label: VideoLUTLibrary.filterLabel,
                                    paramString: "graph=%\(unmanagedGraph.utf8.count)%\(unmanagedGraph)"))
}
check(player.mpv.filters.first { $0.label == VideoLUTLibrary.filterLabel }?.params?["graph"] == unmanagedGraph,
      "a newer programmatic LUT outside the library also wins over an earlier import")
player.mpv.filters.removeAll { $0.label == VideoLUTLibrary.filterLabel }
var readsAtShutdown = 0
delayedImport(fixture) {
  player.info.state = .shuttingDown
  readsAtShutdown = player.mpv.reads
}
check(!player.mpv.filters.contains { $0.label == VideoLUTLibrary.filterLabel },
      "import completion does not write to a shutting-down player")
check(player.mpv.reads == readsAtShutdown, "import completion never reads the engine during shutdown")
player.info.state = .loaded
let neutralItem = popup.itemArray.first { $0.tag == 0 }!
let discovered = removalLibrary.directory.appendingPathComponent("Finder look.cube")
try fixtureCube(inverted: false).write(to: discovered)
player.postNotification(.iinaTrackSettingsChanged)
check(popup.itemArray.first { $0.tag == 0 } === neutralItem,
      "settings notifications reuse an unchanged native menu")
popup.menuNeedsUpdate(popup.menu!)
check(popup.itemArray.contains { ($0.representedObject as? String) == discovered.path },
      "opening the menu discovers LUT files added in Finder")
try FileManager.default.removeItem(at: discovered)
popup.menuNeedsUpdate(popup.menu!)
check(!popup.itemArray.contains { ($0.representedObject as? String) == discovered.path },
      "opening the menu also discovers files removed in Finder")
player.scopedTrackSettings.video[1] = VideoTrackProcessing(lutPath: selected)
player.scopedTrackSettings.setTarget(1, for: .videoColor)
player.postNotification(.iinaTrackSettingsChanged)
check((popup.selectedItem?.representedObject as? String) == selected,
      "cached menus still follow the current source target and its LUT")
player.scopedTrackSettings.setTarget(0, for: .videoColor)
player.postNotification(.iinaVFChanged)
check(popup.selectedTag() == 0, "filter notifications restore the independent Master selection")
let alertsBefore = Utility.alerts.count
delayedImport(invalid) {
  popup.selectItem(withTag: 0)
  _ = NSApp.sendAction(popup.action!, to: popup.target, from: popup)
}
check(Utility.alerts.count == alertsBefore,
      "a superseded invalid import does not interrupt the newer choice with an alert")
print("Production popup action checks passed: \(checks).")
