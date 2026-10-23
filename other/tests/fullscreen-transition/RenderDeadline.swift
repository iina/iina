import Cocoa

final class Lock {
  let lock = NSLock()
  func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock(); defer { lock.unlock() }; return try body()
  }
}
// PRODUCTION_ATOMIC
@propertyWrapper final class ReadLocked<Value> {
  private let lock = NSRecursiveLock()
  var wrappedValue: Value
  var projectedValue: ReadLocked<Value> { self }
  init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
  func withReadLock<T>(_ body: (Value) -> T) -> T {
    lock.lock(); defer { lock.unlock() }; return body(wrappedValue)
  }
}
typealias CGLContextObj = Int
typealias CGLPixelFormatObj = Int
struct CVTimeStamp {}
struct RenderFlag { let rawValue: UInt64 }
let MPV_RENDER_FRAME_INFO_PRESENT = RenderFlag(rawValue: 1)
let MPV_RENDER_PARAM_NEXT_FRAME_INFO: Int32 = 11
struct mpv_render_frame_info {
  var flags: UInt64 = 0
  var target_time: Int64 = 0
}
struct mpv_render_param {
  let type: Int32
  let data: UnsafeMutableRawPointer
  init<T>(type: Int32, data: UnsafeMutablePointer<T>) {
    self.type = type; self.data = UnsafeMutableRawPointer(data)
  }
}
final class Engine {
  var frame = mpv_render_frame_info()
  var now: Int64 = 0
  var infoReads = 0
  var clockReads = 0
}
let engine = Engine()
func mpv_render_context_update(_ context: Int) -> UInt64 { 1 }
func mpv_render_context_get_info(_ context: Int, _ param: mpv_render_param) -> Int32 {
  precondition(param.type == MPV_RENDER_PARAM_NEXT_FRAME_INFO)
  engine.infoReads += 1
  param.data.assumingMemoryBound(to: mpv_render_frame_info.self).pointee = engine.frame
  return 0
}
func mpv_get_time_ns(_ client: Int) -> Int64 {
  precondition(client == 2, "the client handle, not the render context, owns the clock")
  engine.clockReads += 1
  return engine.now
}
final class MPV {
  var mpvRenderContext: Int? = 1
  var mpv = 2
  func shouldRenderUpdateFrame() -> Bool { true }
}
final class Player { let mpv = MPV() }
final class Video {
  @ReadLocked var isUninited = false
  let player = Player()
}
class PriorityLock { func beforeLocking() {}; func afterLocked() {} }
class Base {
  var onDisplay: (() -> Void)?
  func display() { onDisplay?() }
  func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
               forLayerTime time: CFTimeInterval, displayTime stamp: UnsafePointer<CVTimeStamp>?) -> Bool { true }
}
final class DeadlineLayer: Base {
  let videoView = Video()
  let mpvGLQueue = DispatchQueue(label: "crop-deadline-test")
  let displayLock = NSRecursiveLock()
  let mainThreadPriorityLock = PriorityLock()
  var inLiveResize = false
  var isAnimatingWindowResize = false
  var isInFullscreenTransition = false
  var isDrawingGeometryHandoff = false
  var isInCropTransition = true
  var isPreparingCropFrame = false
  var skippedEmptyCropFrame = false
  var isAsynchronous = false
  var isHostedInPIP = false
  var forceDraw = false
  var needsFlip = false
  var bounds = CGRect(x: 0, y: 0, width: 800, height: 450)
  var contentsScale: CGFloat = 2
  var lastRenderedPixelSize: CGSize?
  @Atomic var updates = 0
  var skippedRenders = 0
  var preflightChecks = 0
  func update(force: Bool = false) {
    $updates.withLock { $0 += 1 }
  }
  // Simulate a due/empty initial preflight followed by new native metadata
  // becoming visible only once AppKit calls the real production canDraw body.
  func deferCropDisplayUntilFrameTime() -> Bool { preflightChecks += 1; return false }
  func scheduleFullscreenDisplay() {}
  func completeFullscreenTransitionIfReady() {}
  // PRODUCTION_CROP_FRAME_STATE
  // PRODUCTION_DEADLINE_METHODS
}
var checks = 0
func check(_ value: Bool, _ reason: String) {
  if !value { print("FAILED: " + reason); exit(1) }; checks += 1
}
func pump(_ predicate: () -> Bool) {
  let limit = Date().addingTimeInterval(1)
  while !predicate() && Date() < limit { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
  check(predicate(), "scheduled native retry completes")
}
func canDraw(_ layer: DeadlineLayer) -> Bool {
  layer.canDraw(inCGLContext: 0, pixelFormat: 0, forLayerTime: 0, displayTime: nil)
}
func attempt(_ layer: DeadlineLayer) -> Bool {
  var allowed = false
  let done = DispatchSemaphore(value: 0)
  layer.onDisplay = {
    allowed = canDraw(layer)
    if allowed {
      layer.needsFlip = false
      layer.forceDraw = false
      layer.takeCropFrameHandlers().forEach { $0(true) }
    }
  }
  layer.needsFlip = true; layer.forceDraw = true
  layer.mpvGLQueue.async { layer.display(); done.signal() }
  check(done.wait(timeout: .now() + 1) == .success, "draw eligibility never blocks for future video time")
  return allowed
}

let layer = DeadlineLayer()
var replies: [Bool] = []
layer.afterNextCropFrame { replies.append($0) }
layer.updates = 0
engine.frame = .init(flags: 1, target_time: 40_000_000)
check(!attempt(layer) && layer.skippedEmptyCropFrame,
      "a newly queued future frame is rejected after the display preflight")
check(layer.preflightChecks == 1 && layer.skippedRenders == 0 && layer.needsFlip && layer.forceDraw,
      "a deferred frame remains queued instead of entering display's skip-render fallback")
check(replies.isEmpty && layer.updates == 0,
      "future native frames neither complete presentation waiters nor retry early")
pump { layer.updates == 1 }
engine.now = 50_000_000
check(attempt(layer) && !layer.skippedEmptyCropFrame,
      "the same native frame can draw after its nanosecond deadline")
check(replies == [true] && layer.skippedRenders == 0,
      "the due native draw completes its presentation waiter exactly once")

engine.frame = .init(flags: 0, target_time: 0)
let clockBeforeEmpty = engine.clockReads
check(!attempt(layer) && layer.skippedEmptyCropFrame && layer.skippedRenders == 0,
      "empty native metadata preserves the existing backing and skip-consumption gate")
check(engine.clockReads == clockBeforeEmpty, "an empty native queue does not inspect presentation time")

layer.isPreparingCropFrame = true
let infoBeforePreparing = engine.infoReads
check(!canDraw(layer) && engine.infoReads == infoBeforePreparing,
      "unfinished crop preparation stays gated before native metadata or deadlines")
layer.isPreparingCropFrame = false
engine.frame = .init(flags: 3, target_time: 0)
check(canDraw(layer), "a paused redraw with no presentation deadline remains immediate")

engine.frame = .init(flags: 1, target_time: 100_000_000)
layer.isAnimatingWindowResize = true
check(!canDraw(layer), "ordinary main-thread resize drawing remains disabled")
layer.isDrawingGeometryHandoff = true
let clockBeforeHandoff = engine.clockReads
check(canDraw(layer) && engine.clockReads == clockBeforeHandoff,
      "the synchronous geometry handoff retains native timing and cannot defer its required draw")
layer.isDrawingGeometryHandoff = false
layer.isAnimatingWindowResize = false

let cancelled = DeadlineLayer()
engine.frame = .init(flags: 1, target_time: 80_000_000)
engine.now = 50_000_000
check(!attempt(cancelled), "another future native frame schedules a retry")
cancelled.cancelCropFrameRequests()
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
check(cancelled.updates == 0, "cancelling crop invalidates a retry queued from canDraw")
print("Passed \(checks) crop presentation deadline checks")
