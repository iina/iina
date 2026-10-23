import AppKit
import QuartzCore

let MPV_EVENT_NONE = 0, MPV_EVENT_SHUTDOWN = 1, MPV_EVENT_SEEK = 20, MPV_EVENT_PLAYBACK_RESTART = 21
struct NativeEvent { var event_id = MPV_EVENT_NONE }
final class NativeEvents {
  let lock = NSLock()
  var pending: [Int] = []
  let returned = UnsafeMutablePointer<NativeEvent>.allocate(capacity: 1)
  init() { returned.initialize(to: NativeEvent()) }
  deinit { returned.deinitialize(count: 1); returned.deallocate() }
  func append(_ event: Int) { lock.lock(); pending.append(event); lock.unlock() }
  func next() -> UnsafePointer<NativeEvent> {
    lock.lock()
    returned.pointee.event_id = pending.isEmpty ? MPV_EVENT_NONE : pending.removeFirst()
    lock.unlock()
    return UnsafePointer(returned)
  }
}
func mpv_wait_event(_ handle: OpaquePointer?, _ timeout: Double) -> UnsafePointer<NativeEvent>? {
  precondition(timeout == 0)
  guard let handle else { return nil }
  return Unmanaged<NativeEvents>.fromOpaque(UnsafeRawPointer(handle)).takeUnretainedValue().next()
}
enum Constants { enum String { static let videoTimePlaceholder = "--:--" } }
struct Time { var stringRepresentation = "00:42" }
func / (_ lhs: Time?, _ rhs: Time?) -> Double? { 0.25 }
enum Preference { enum Key { case alwaysFloatOnTop }; static func bool(for: Key) -> Bool { false } }
final class Video {
  var active = 0, idle = 0
  func displayActive() { active += 1 }
  func displayIdle() { idle += 1 }
  final class Layer { func update(force: Bool) { precondition(force) } }
  let videoLayer = Layer()
}
final class Window {
  let videoView = Video()
  var loaded = true
  final class LiveText { func clearAnalysis() {}; func requestAnalysis() {} }
  let liveText = LiveText()
  func setWindowFloatingOnTop(_ value: Bool) {}
}
enum OSDMessage { case seek(String, String, Double), pause, resume }
final class FeedbackOrigins {
  var resets = 0
  func reset() { resets += 1 }
}
final class Player {
  enum State { case paused, playing, stopped; var active: Bool { self != .stopped }; var loaded: Bool { active } }
  final class Info {
    var state = State.paused, trackSelectionGeneration = 1, isSeeking = false
    var videoPosition: Time? = Time(), videoDuration: Time? = Time()
  }
  enum Sync { case time, playButton }
  let info = Info()
  let osdFeedbackOrigins = FeedbackOrigins()
  var mainWindow: Window! = Window()
  lazy var mpv = Controller(self)
  var seekOSDs = 0, pauseOSDs = 0, resumeOSDs = 0, timeSyncs = 0, restarts = 0
  func sendOSD(_ message: OSDMessage) {
    dispatchPrecondition(condition: .onQueue(.main))
    switch message {
    case .seek: seekOSDs += 1
    case .pause: pauseOSDs += 1
    case .resume: resumeOSDs += 1
    }
  }
  func syncUI(_ value: Sync) { if value == .time { timeSyncs += 1 } }
  func syncUITime() {}
  func refreshSyncUITimer() {}
  func onVideoReconfig(outputIsReady: Bool) {}
  func trackListChanged() {}
  func vfChanged() {}
  func videoParamsChanged() {}
  func cancelScreenshotRequests(close: Bool = false) {}
  func playbackRestarted() { restarts += 1; finishPausedCropRefresh() }
  func beginCropRefresh() { beginPausedCropRefresh() }
  // PRODUCTION_PLAYER
}
final class Controller {
  unowned let player: Player
  let queue = DispatchQueue(label: "org.lyzmin41.test.geometry-seek-events")
  let events = NativeEvents()
  var mpv: OpaquePointer! { OpaquePointer(Unmanaged.passUnretained(events).toOpaque()) }
  var needRecordSeekTime = false, recordedSeekStartTime: Double = 0
  var recordedSeekTimeListener: ((Double) -> Void)?
  init(_ player: Player) { self.player = player }
  func handleEvent(_ event: UnsafePointer<NativeEvent>) {
    switch event.pointee.event_id {
    case MPV_EVENT_SEEK:
      // PRODUCTION_SEEK
    case MPV_EVENT_PLAYBACK_RESTART:
      // PRODUCTION_RESTART
    default: break
    }
  }
  // PRODUCTION_EVENT_DRAIN
}

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  guard value() else { fputs("FAILED: \(message)\n", stderr); exit(1) }
  checks += 1; print("PASS:", message)
}
func drain(_ player: Player) {
  var done = false
  player.mpv.afterPendingEvents { done = true }
  let deadline = Date().addingTimeInterval(2)
  while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
  check(done, "nonblocking controller drain reaches main")
}
func event(_ player: Player, _ kind: Int) { player.mpv.events.append(kind) }

for state in [Player.State.paused, .playing] {
  let player = Player(); player.info.state = state
  event(player, MPV_EVENT_SEEK); event(player, MPV_EVENT_PLAYBACK_RESTART)
  drain(player)
  check(player.seekOSDs == 0 && !player.shouldShowSeekOSD,
        "internal audio/filter refresh outside geometry has no progress OSD in \(state)")
  check(player.mainWindow.videoView.active == 1 && !player.info.isSeeking && player.restarts == 1,
        "unscoped internal refresh preserves native seek and restart handling")
  player.userInitiatedSeek()
  event(player, MPV_EVENT_SEEK); event(player, MPV_EVENT_PLAYBACK_RESTART)
  drain(player)
  check(player.seekOSDs == 1 && !player.shouldShowSeekOSD,
        "ordinary explicit seek shows progress and its restart consumes that intent")
  event(player, MPV_EVENT_SEEK); drain(player)
  check(player.seekOSDs == 1, "later internal refresh cannot reuse a completed explicit seek")
}

for state in [Player.State.paused, .playing] {
  let player = Player(); player.info.state = state
  let scope = player.beginVideoGeometryOSDRefresh()
  check(!player.shouldShowSeekOSD, "geometry scopes suppress unsolicited seek OSD in \(state)")
  event(player, MPV_EVENT_SEEK); event(player, MPV_EVENT_PLAYBACK_RESTART)
  player.endVideoGeometryOSDRefresh(scope)
  check(!player.shouldShowSeekOSD, "scope end waits for pending controller events without blocking main")
  drain(player)
  check(player.seekOSDs == 0, "already queued refresh SEEK cannot escape the native-ready boundary")
  check(player.mainWindow.videoView.active == 1 && !player.info.isSeeking && player.restarts == 1,
        "suppressed OSD preserves native seek/display/restart lifecycle")
  check(!player.shouldShowSeekOSD, "native-ready completion cannot grant unsolicited seek OSD")
  event(player, MPV_EVENT_SEEK); drain(player)
  check(player.seekOSDs == 0, "internal seeking remains silent after geometry ends")
  player.userInitiatedSeek()
  event(player, MPV_EVENT_SEEK); drain(player)
  check(player.seekOSDs == 1, "deliberate seeking outside geometry remains visible")
}
for before in [true, false] {
  let player = Player()
  if before { player.userInitiatedSeek() }
  let scope = player.beginVideoGeometryOSDRefresh()
  if !before { player.userInitiatedSeek() }
  event(player, MPV_EVENT_SEEK); event(player, MPV_EVENT_PLAYBACK_RESTART)
  drain(player)
  check(player.seekOSDs == 1, "explicit seek \(before ? "before" : "during") geometry retains its OSD")
  event(player, MPV_EVENT_SEEK); drain(player)
  check(player.seekOSDs == 1, "geometry permission cannot reuse an explicit intent consumed by restart")
  player.userInitiatedSeek()
  event(player, MPV_EVENT_SEEK); event(player, MPV_EVENT_PLAYBACK_RESTART); drain(player)
  check(player.seekOSDs == 2, "a new deliberate seek remains visible during the same geometry operation")
  player.endVideoGeometryOSDRefresh(scope); drain(player)
  let next = player.beginVideoGeometryOSDRefresh()
  check(!player.shouldShowSeekOSD, "completed user intent does not leak into a later geometry operation")
  player.endVideoGeometryOSDRefresh(next); drain(player)
}
let late = Player()
let lateScope = late.beginVideoGeometryOSDRefresh()
event(late, MPV_EVENT_SEEK); drain(late)
late.userInitiatedSeek()
event(late, MPV_EVENT_SEEK); drain(late)
check(late.seekOSDs == 1, "user seek following a suppressed refresh SEEK is visible")
late.endVideoGeometryOSDRefresh(lateScope); drain(late)

let overlap = Player()
let first = overlap.beginVideoGeometryOSDRefresh()
overlap.endVideoGeometryOSDRefresh(first)
let replacement = overlap.beginVideoGeometryOSDRefresh()
event(overlap, MPV_EVENT_SEEK); event(overlap, MPV_EVENT_PLAYBACK_RESTART)
drain(overlap)
check(!overlap.shouldShowSeekOSD && overlap.seekOSDs == 0,
      "old scope completion and playback restart cannot release a superseding geometry operation")
overlap.endVideoGeometryOSDRefresh(first); drain(overlap)
check(!overlap.shouldShowSeekOSD, "duplicate stale scope end is harmless")
overlap.endVideoGeometryOSDRefresh(replacement); drain(overlap)
check(!overlap.shouldShowSeekOSD, "ending the current scope cannot create explicit seek intent")

let pending = Player()
pending.userInitiatedSeek(); event(pending, MPV_EVENT_SEEK); drain(pending)
pending.userInitiatedSeek(); event(pending, MPV_EVENT_PLAYBACK_RESTART); drain(pending)
let pendingScope = pending.beginVideoGeometryOSDRefresh()
check(pending.shouldShowSeekOSD, "older restart cannot consume a newly pending explicit seek")
pending.endVideoGeometryOSDRefresh(pendingScope); drain(pending)
event(pending, MPV_EVENT_SEEK); event(pending, MPV_EVENT_PLAYBACK_RESTART); drain(pending)
check(pending.seekOSDs == 2 && !pending.shouldShowSeekOSD,
      "the preserved newer seek is presented and completed independently")

let carried = Player()
let carriedFirst = carried.beginVideoGeometryOSDRefresh()
carried.userInitiatedSeek()
let carriedNext = carried.beginVideoGeometryOSDRefresh()
event(carried, MPV_EVENT_SEEK); drain(carried)
carried.endVideoGeometryOSDRefresh(carriedFirst); drain(carried)
check(carried.shouldShowSeekOSD && carried.seekOSDs == 1,
      "superseding geometry carries same-media explicit seek permission")
event(carried, MPV_EVENT_PLAYBACK_RESTART); drain(carried)
check(!carried.shouldShowSeekOSD, "completed explicit seek is silent even while its geometry scope remains")
carried.endVideoGeometryOSDRefresh(carriedNext); drain(carried)

let failed = Player()
let failedToken = failed.userInitiatedSeek()
check(failed.shouldShowSeekOSD, "an explicit command arms current-media seek feedback")
failed.cancelUserInitiatedSeek(failedToken)
event(failed, MPV_EVENT_SEEK); event(failed, MPV_EVENT_PLAYBACK_RESTART); drain(failed)
check(failed.seekOSDs == 0 && !failed.shouldShowSeekOSD,
      "a rejected or canceled command cannot leave progress feedback armed")
let staleToken = failed.userInitiatedSeek()
let currentToken = failed.userInitiatedSeek()
failed.cancelUserInitiatedSeek(staleToken)
event(failed, MPV_EVENT_SEEK); drain(failed)
check(failed.seekOSDs == 1 && failed.shouldShowSeekOSD,
      "failure of an older command cannot cancel a newer pending seek")
failed.cancelUserInitiatedSeek(currentToken)
failed.cancelUserInitiatedSeek(currentToken)
event(failed, MPV_EVENT_PLAYBACK_RESTART); event(failed, MPV_EVENT_SEEK); drain(failed)
check(failed.seekOSDs == 1 && !failed.shouldShowSeekOSD,
      "canceling an already started intent is idempotent and prevents later internal feedback")

let inactive = Player()
inactive.userInitiatedSeek(); inactive.info.state = .stopped
check(!inactive.shouldShowSeekOSD, "inactive playback cannot publish stale deliberate seek feedback")
inactive.info.state = .playing; inactive.info.trackSelectionGeneration += 1
check(!inactive.shouldShowSeekOSD, "another media generation cannot inherit deliberate seek feedback")

let media = Player()
media.userInitiatedSeek(); let oldMedia = media.beginVideoGeometryOSDRefresh()
media.endVideoGeometryOSDRefresh(oldMedia)
media.info.trackSelectionGeneration += 1
let newMedia = media.beginVideoGeometryOSDRefresh()
drain(media)
check(!media.shouldShowSeekOSD, "old generation cannot grant permission or clear a new-media scope")
media.endVideoGeometryOSDRefresh(newMedia); drain(media)

let crop = Player()
crop.beginCropRefresh()
let cropScope = crop.beginVideoGeometryOSDRefresh()
crop.endVideoGeometryOSDRefresh(cropScope); drain(crop)
check(!crop.shouldShowSeekOSD, "geometry completion preserves the independent paused Crop guard")
crop.userInitiatedSeek()
check(crop.shouldShowSeekOSD, "real seek overrides the paused Crop guard")
event(crop, MPV_EVENT_SEEK); event(crop, MPV_EVENT_PLAYBACK_RESTART); drain(crop)
check(crop.seekOSDs == 1 && !crop.isRefreshingPausedCrop, "Crop restart still completes and presents deliberate seeking")
let priorCrop = Player()
priorCrop.userInitiatedSeek(); priorCrop.beginCropRefresh()
check(priorCrop.shouldShowSeekOSD, "paused Crop also preserves a deliberate seek already pending before mutation")

let resume = Player()
let resumeScope = resume.beginVideoGeometryOSDRefresh()
resume.pauseChanged(false)
check(resume.resumeOSDs == 1 && resume.info.state == .playing && !resume.shouldShowSeekOSD,
      "resume OSD and playback remain intact without treating resume as user seeking")
resume.pauseChanged(true)
check(resume.pauseOSDs == 1 && resume.info.state == .paused, "pause OSD remains intact during geometry")
resume.endVideoGeometryOSDRefresh(resumeScope); drain(resume)

for boundary in ["stop", "shutdown", "mpvHasShutdown", "fileStarted", "fileEnded"] {
  let player = Player()
  player.userInitiatedSeek(); let old = player.beginVideoGeometryOSDRefresh()
  player.endVideoGeometryOSDRefresh(old)
  switch boundary {
  case "stop": player.stop()
  case "shutdown": player.shutdown()
  case "mpvHasShutdown": player.mpvHasShutdown()
  case "fileStarted": player.fileStarted(path: "fixture")
  default: player.fileEnded(false)
  }
  let next = player.beginVideoGeometryOSDRefresh()
  drain(player)
  check(!player.shouldShowSeekOSD, "\(boundary) invalidates feedback scope and pending seek intent before late completion")
  check(player.osdFeedbackOrigins.resets == 1, "\(boundary) also resets property feedback provenance")
  player.endVideoGeometryOSDRefresh(next); drain(player)
}
print("Geometry seek OSD: \(checks) production-state/event/drain/lifecycle checks passed; no native player or UI opened.")
