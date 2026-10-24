import Cocoa

enum Constants {
  enum FilterName { static let crop = "crop", flip = "flip", mirror = "mirror" }
}
enum MPVProperty { static let vf = "vf", videoOutParams = "video-out-params" }
enum MPVOption {
  enum Video {
    static let videoZoom = "zoom", videoPanX = "pan-x", videoPanY = "pan-y"
    static let panscan = "panscan", videoRotate = "rotate", videoAspectOverride = "aspect"
  }
}
struct MPVFilter { var label: String?; var params: [String: String]? }
// PRODUCTION_GEOMETRY
final class Engine {
  var size = NSSize(width: 2350, height: 1595)
  var filters = [MPVFilter(label: Constants.FilterName.crop)]
  var graph = ""
  var options: [String: Double] = [:]
  func getDouble(_ name: String) -> Double { options[name] ?? (name.hasPrefix("video-scale-") ? 1 : 0) }
  func getInt(_ name: String) -> Int { Int(name.hasSuffix("/w") ? size.width : size.height) }
  func getFilters(_ name: String) -> [MPVFilter] { filters }
  func getString(_ name: String) -> String? { name == "lavfi-complex" ? graph : name == "video-unscaled" ? "no" : "" }
}
final class Window {
  var isPlayerCropTransitionInProgress = false
  var accepts = true, preparations = 0, cancellations = 0
  var pending: (() -> Void)?
  func prepareCropChange(_ apply: @escaping () -> Void, selection: NSRect, displaySize: NSSize, filterRect: NSRect) -> Bool {
    preparations += 1
    if accepts { pending = apply; isPlayerCropTransitionInProgress = true }
    return accepts
  }
  func cancelCropExitTransition() { cancellations += 1; pending = nil; isPlayerCropTransitionInProgress = false }
}
final class Player {
  func preservingOSDFeedbackOrigin<T>(_ action: @escaping () -> T) -> () -> T { action }
  enum Notice { case iinaTrackSettingsChanged }
  var settingsUpdates = 0
  func postNotification(_ notice: Notice) { settingsUpdates += 1 }
  struct Info {
    var cropFilter: MPVFilter? = MPVFilter(label: "crop", params: ["w": "2350", "h": "1595", "x": "120", "y": "200"])
    var unsureCrop = "Custom"
    var flipFilter: MPVFilter?, mirrorFilter: MPVFilter?
  }
  var rotation = 0
  var ownedTrackGraph: String?
  var info = Info(), mpv = Engine(), mainWindow: Window? = Window()
  var mutations = 0, succeeds = true
  func interactiveVideoGeometry(uncropped: Bool) -> CropVideoGeometry {
    let size = uncropped ? NSSize(width: 3840, height: 2160) : mpv.size
    return CropVideoGeometry(sourceSize: size, displaySize: size, rotation: rotation)
  }
  func setCrop(fromFilter filter: MPVFilter) -> Bool {
    mutations += 1
    if succeeds { info.cropFilter = filter }
    return succeeds
  }
  func removeCropFilter() { mutations += 1; info.cropFilter = nil; info.unsureCrop = "None" }
  func change(_ size: NSSize?, description: String = "4:3") {
    applyCropChange(size.map { MPVFilter(label: "crop", params: ["w": String(Int($0.width)), "h": String(Int($0.height))]) }, description: description, outputSize: size)
  }
  // PRODUCTION_APPLY
}
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS:", message)
}
for preset in [false, true] {
  let p = Player()
  p.change(preset ? NSSize(width: 2880, height: 2160) : nil)
  check(p.mutations == 0 && p.mainWindow!.preparations == 1,
        "Custom to \(preset ? "preset" : "None") defers canonical mutation until the live source motion completes")
  p.mainWindow!.pending!()
  check(p.mutations == 1 && p.info.unsureCrop == (preset ? "4:3" : "None"),
        "motion completion applies the requested crop once")
  check(p.settingsUpdates == 1, "crop selection observers see the committed description")
}
let equal = Player()
equal.change(equal.mpv.size)
check(equal.mutations == 1 && equal.mainWindow!.preparations == 0,
      "same-size crop replacement cannot wait for a nonexistent dimension event")
for extra in ["scale", "lavfi"] {
  let p = Player(); p.mpv.filters.append(MPVFilter(label: extra)); p.change(nil)
  check(p.mutations == 1 && p.mainWindow!.preparations == 0,
        "an external \(extra) filter retains its existing readiness path")
}
let graph = Player(); graph.mpv.graph = "[vid1]scale=640:360[vo]"; graph.change(nil)
check(graph.mutations == 1 && graph.mainWindow!.preparations == 0,
      "a complex output graph cannot leave a dimensional bridge waiting")
let audioGraph = Player()
audioGraph.mpv.graph = "[aid1][aid2]amix[ao]"
audioGraph.ownedTrackGraph = audioGraph.mpv.graph
audioGraph.change(nil)
check(audioGraph.mutations == 0 && audioGraph.mainWindow!.preparations == 1,
      "the owned audio-only mixer cannot bypass smooth video crop transitions")
for label in ["flip", "mirror"] {
  let p = Player(); p.mpv.filters.append(MPVFilter(label: label)); p.change(nil)
  check(p.mutations == 0 && p.mainWindow!.preparations == 1,
        "dimension-preserving owned \(label) allows the crop transition")
}
let ordinary = Player(); ordinary.info.unsureCrop = "16:10"; ordinary.change(nil)
check(ordinary.mutations == 0 && ordinary.mainWindow!.preparations == 1,
      "ordinary preset transitions capture before changing the displayed source region")
let uncropped = Player(); uncropped.info.cropFilter = nil; uncropped.info.unsureCrop = "None"
uncropped.mpv.size = NSSize(width: 3840, height: 2160)
uncropped.change(NSSize(width: 2880, height: 2160))
check(uncropped.mutations == 0 && uncropped.mainWindow!.preparations == 1,
      "None to a preset keeps the native source while planning its target")
let unsupported = Player(); unsupported.mainWindow!.accepts = false; unsupported.change(nil)
check(unsupported.mutations == 1, "declining animation still applies the requested crop")
let superseded = Player()
superseded.mainWindow!.isPlayerCropTransitionInProgress = true
superseded.info.unsureCrop = "4:3"; superseded.change(nil)
check(superseded.mutations == 0 && superseded.mainWindow!.preparations == 1,
      "a rapid request supersedes an active player crop transition")
let immediate = Player(); immediate.mainWindow!.isPlayerCropTransitionInProgress = true
immediate.change(immediate.mpv.size)
check(immediate.mainWindow!.preparations == 1 && immediate.mutations == 0,
      "a request matching temporary full-source dimensions still queues behind the active handoff")
let failed = Player(); failed.succeeds = false
failed.change(NSSize(width: 2880, height: 2160)); failed.mainWindow!.pending!()
check(failed.info.unsureCrop == "Custom", "failed filter changes cannot overwrite the existing description")
let viewport = NSRect(x: 0, y: 0, width: 800, height: 450)
let geometry = Player()
for rotation in [0, 90, 180, 270] {
  geometry.rotation = rotation
  let frame = geometry.cropTransitionFrame(in: viewport)!
  let source = geometry.interactiveVideoGeometry(uncropped: true)
  let expected = source.selectionRect(forFilterRect: NSRect(x: 120, y: 200, width: 2350, height: 1595))
  check(abs(frame.selection.minX * source.selectionSize.width - expected.minX) < 0.000001 &&
        abs(frame.selection.minY * source.selectionSize.height - expected.minY) < 0.000001 &&
        abs(frame.selection.width * source.selectionSize.width - expected.width) < 0.000001 &&
        abs(frame.selection.height * source.selectionSize.height - expected.height) < 0.000001,
        "\(rotation)-degree source landmarks are mapped into the displayed crop coordinate system")
}
geometry.info.cropFilter = nil
check(geometry.cropTransitionFrame(in: viewport)!.selection == NSRect(x: 0, y: 0, width: 1, height: 1),
      "None always describes the complete original source, including rotated media")
for option in [MPVOption.Video.videoZoom, MPVOption.Video.videoPanX, MPVOption.Video.videoPanY,
               MPVOption.Video.panscan, MPVOption.Video.videoRotate, MPVOption.Video.videoAspectOverride] {
  let p = Player(); p.mpv.options[option] = 1
  check(p.cropTransitionFrame(in: viewport) == nil,
        "independent \(option) geometry keeps the blend fallback instead of misplacing source pixels")
}
for label in ["flip", "mirror"] {
  let p = Player()
  if label == "flip" { p.info.flipFilter = MPVFilter(label: label) }
  else { p.info.mirrorFilter = MPVFilter(label: label) }
  check(p.cropTransitionFrame(in: viewport) == nil, "\(label) retains a coordinated blend")
}
let invalid = Player(); invalid.info.cropFilter!.params!["x"] = "4000"
check(invalid.cropTransitionFrame(in: viewport) == nil, "invalid source extents cannot enter the geometry transform")
print("Completed \(checks) crop mutation routing checks using the production method.")
