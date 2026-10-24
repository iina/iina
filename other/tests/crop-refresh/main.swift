import AppKit
import QuartzCore
enum AppRestartSession {
  static func seekStarted(_ player: Player) {}
  static func playbackRestarted(_ player: Player) {}
}

final class MPVFilter { var label: String? }
enum Constants { enum FilterName { static let crop = "crop" }; enum String { static let videoTimePlaceholder = "--:--" } }
struct Time { var second = 42.0; var stringRepresentation: String { "00:42" } }
func / (a: Time?, b: Time?) -> Double? { 0.25 }
enum MPVProperty { static let dwidth = "dw", dheight = "dh", coreIdle = "idle" }
final class Engine {
  var busy = false, succeeds = true, reads = 0
  func getInt(_ name: String) -> Int {
    precondition(!busy, "UI synchronously queried the rebuilding engine")
    reads += 1;return name == "dw" ? 640 : 480
  }
  func getFlag(_ name: String) -> Bool { false }
  func afterPendingEvents(_ completion: @escaping () -> Void) { DispatchQueue.main.async(execute: completion) }
  var seeks = 0
  enum Command { case seek }
  func command(_ command: Command, args: [String]) { precondition(args == ["0", "relative+exact"]); seeks += 1 }
}
final class Video { var active = 0;func displayActive() { active += 1 };let videoLayer = Layer() }
final class Layer { var updates = 0;func update(force: Bool) { precondition(force);updates += 1 } }
final class LiveText { func clearAnalysis() {};func requestAnalysis() {} }
final class Window {
  let videoView = Video(), liveText = LiveText()
  var ready = 0, sizes = 0
  func finishCropExitTransition(outputIsReady: Bool) { if outputIsReady { ready += 1 } }
  func finishVideoAspectTransition() {}
  func geometryVideoOutputDidChange(outputIsReady: Bool = false) {}
  func prepareVideoTransformWindowReference() {}
}
enum NowPlayingInfoManager { static let shared = Manager();struct Manager { func updateInfo() {} } }
final class FeedbackOrigins { func reset() {} }
final class Player {
  enum State { case paused, playing, stopped;var active: Bool { self != .stopped };var loaded: Bool { active } }
  final class Info {
    var state = State.paused, trackSelectionGeneration = 1
    var cropFilter: MPVFilter?, unsureCrop = "None", rotation = 0
    var displayWidth: Int? = 1920, displayHeight: Int? = 1080
    var isSeeking = false, justStartedFile = false, justOpenedFile = false, disableOSDForFileLoading = false
    var videoPosition: Time? = Time(), videoDuration: Time? = Time()
  }
  enum Notification { case iinaVFChanged, iinaVideoParamsChanged }
  enum Sync { case time }
  enum OSD { case seek(String,String,Double) }
  let info = Info(), mpv = Engine()
  let osdFeedbackOrigins = FeedbackOrigins()
  var mainWindow: Window! = Window()
  var syncs = 0, osds = 0, filterNotifications = 0, paramsNotifications = 0, trackUpdates = 0
  func log(_ s: String) {}
  func addVideoFilter(_ f: MPVFilter) -> Bool { mpv.busy = mpv.succeeds;return mpv.succeeds }
  func removeVideoFilter(_ f: MPVFilter) -> Bool { mpv.busy = mpv.succeeds;return mpv.succeeds }
  func syncUI(_ sync: Sync) { precondition(!mpv.busy,"premature time query");syncs += 1 }
  func sendOSD(_ message: OSD) { osds += 1 }
  func reloadSavedIINAfilters() {}
  func trackListChanged() { trackUpdates += 1 }
  func notifyWindowVideoSizeChanged() { mainWindow.sizes += 1 }
  func postNotification(_ n: Notification) { if n == .iinaVFChanged { filterNotifications += 1 } else { paramsNotifications += 1 } }
  // PRODUCTION_REFRESH
}
final class Controller {
  let player: Player
  var needRecordSeekTime = false, recordedSeekStartTime: Double = 0
  init(_ player: Player) { self.player = player }
  func receiveSeek() {
    // PRODUCTION_SEEK
  }
}
var checks = 0
func check(_ x: @autoclosure () -> Bool, _ message: String) { precondition(x(),message);checks += 1;print("PASS:",message) }
func drain() { var done=false;DispatchQueue.main.async {done=true};while !done { RunLoop.current.run(until:Date().addingTimeInterval(0.001)) } }
let p=Player(), controller: Controller
controller=Controller(p)
_ = p.setCrop(fromFilter: MPVFilter())
controller.receiveSeek();drain()
check(p.isRefreshingPausedCrop && p.osds == 0 && p.syncs == 0,"internal paused crop refresh neither seeks visibly nor polls the busy engine")
for _ in 0..<20 { p.onVideoReconfig();p.vfChanged();p.videoParamsChanged() }
check(p.mpv.reads == 0 && p.mainWindow.sizes == 0,"early repeated reconfiguration cannot query or resize before the ready frame")
check(p.filterNotifications == 0 && p.paramsNotifications == 0,"filter/sidebar refreshes wait for the same completion boundary")
p.mpv.busy=false;p.playbackRestarted()
check(!p.isRefreshingPausedCrop && p.mpv.reads == 2 && p.mainWindow.sizes == 1,"one post-restart geometry refresh replaces repeated premature reads")
check(p.filterNotifications == 1 && p.paramsNotifications == 1,"deferred notifications are delivered once")
controller.receiveSeek();drain();check(p.osds == 0,"an internal seek stays silent after the crop completes")
p.userInitiatedSeek();controller.receiveSeek();drain();check(p.osds == 1,"ordinary explicit seeking keeps its time OSD after the crop completes")
p.seekOSDDidRestart()
p.removeCropFilter();controller.receiveSeek();drain();check(p.osds == 1,"removing a paused crop also suppresses its internal seek OSD")
p.mpv.busy=false;p.playbackRestarted()
p.mpv.succeeds=false
check(!p.setCrop(fromFilter:MPVFilter()) && !p.isRefreshingPausedCrop,"failed filter mutation cannot leave seek suppression armed")
p.mpv.succeeds=true;_ = p.setCrop(fromFilter:MPVFilter());p.info.trackSelectionGeneration += 1
check(!p.isRefreshingPausedCrop && !p.shouldShowSeekOSD,"a new media generation inherits neither crop suppression nor deliberate seek intent")
p.mpv.busy=false;p.playbackRestarted()
p.info.state = .playing;_ = p.setCrop(fromFilter:MPVFilter())
check(!p.isRefreshingPausedCrop && !p.shouldShowSeekOSD,"playing crops keep their existing video-output readiness path without unsolicited progress OSD")
p.mpv.busy=false;p.info.state = .paused;_ = p.setCrop(fromFilter:MPVFilter());p.userInitiatedSeek()
check(p.shouldShowSeekOSD,"explicit user seeking overrides internal-refresh OSD suppression")
p.mpv.busy=false;controller.receiveSeek();drain();check(p.osds == 2,"an explicit seek during refresh is still presented")
p.seekOSDDidRestart();p.playbackRestarted();p.removeCropFilter();p.info.state = .stopped;p.mpv.busy=false;p.playbackRestarted()
check(!p.isRefreshingPausedCrop,"stopped playback cannot retain a crop refresh")
let native = Player()
native.info.state = .playing
native.requestNativeCropFrame()
check(native.mpv.seeks == 0 && native.mainWindow.videoView.videoLayer.updates == 1, "a playing native handoff requests a draw without seeking or pausing")
native.info.state = .paused
native.requestNativeCropFrame()
check(native.mpv.seeks == 0 && !native.isRefreshingPausedCrop && native.mainWindow.videoView.videoLayer.updates == 2, "a paused native handoff redraws the existing refresh without decoding the same PTS again")
native.info.state = .stopped
native.requestNativeCropFrame()
check(native.mpv.seeks == 0 && native.mainWindow.videoView.videoLayer.updates == 2, "a stopped native handoff cannot queue video work")
print("Completed \(checks) production crop refresh checks.")
