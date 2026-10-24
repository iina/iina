import Cocoa

final class Lock {
  let lock = NSLock()
  func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock(); defer { lock.unlock() }; return try body()
  }
}
// PRODUCTION_ATOMIC
class PriorityLock { func beforeLocking() {}; func afterLocked() {} }
class Base { var onDisplay: (() -> Void)?; func display() { onDisplay?() } }
enum HandoffTransaction {
  static var onPublish: (() -> Void)?
  static func begin() { CATransaction.begin() }
  static func setDisableActions(_ value: Bool) { CATransaction.setDisableActions(value) }
  static func commit() { CATransaction.commit() }
  static func flush() { onPublish?(); CATransaction.flush() }
}
class Video { var videoLayer: Layer! }
class Layer: Base {
 func deferCropDisplayUntilFrameTime() -> Bool { false }
 var cropSurface: CropSurfaceFixture?
 func requestCropDisplay(_ surface: CropSurfaceFixture) {}
  let displayLock = NSRecursiveLock()
  let mainThreadPriorityLock = PriorityLock()
  let mpvGLQueue = DispatchQueue(label: "fullscreen-test-render")
  var videoView: Video!
  @Atomic var fullscreenTransition = (generation: 0, active: false, finishing: false)
  @Atomic var fullscreenDisplayQueued = false
  @Atomic var lastRenderedPixelSize: CGSize? = nil
  var isInFullscreenTransition: Bool { fullscreenTransition.active }
  var bounds = CGRect(x: 0, y: 0, width: 800, height: 340)
  var contentsScale: CGFloat = 2
  var contentsGravity = CALayerContentsGravity.resizeAspectFill
  var isAsynchronous = false
  var isHostedInPIP = false
  @Atomic var isDrawingGeometryHandoff = false
  @Atomic var isInCropTransition = false
  @Atomic var isPreparingCropFrame = false
  @Atomic var skippedEmptyCropFrame = false
  @Atomic var isAnimatingWindowResize = false
  var inLiveResize = false
  var forceDraw = false
  var needsFlip = false
  override init() { super.init() }
  init(copy previousLayer: Layer) {
    super.init()
    videoView = previousLayer.videoView
    // PRODUCTION_COPY
  }
  // PRODUCTION_RENDER
}
var checks = 0
func check(_ value: Bool, _ reason: String) {
  if !value { print("FAILED: " + reason); exit(1) }; checks += 1
}
func drain(until complete: () -> Bool) {
  let deadline = Date().addingTimeInterval(3)
  while !complete() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
  check(complete(), "queued render completed")
}
let video = Video(), layer = Layer()
video.videoLayer = layer; layer.videoView = video
layer.fullscreenTransition = (generation: 1, active: true, finishing: false)
let held = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
var renders = 0
layer.onDisplay = { check(!Thread.isMainThread, "fullscreen GL work runs off main"); renders += 1 }
DispatchQueue.global().async {
  layer.displayLock.lock(); held.signal()
  _ = release.wait(timeout: .now() + 0.3)
  layer.displayLock.unlock()
}
check(held.wait(timeout: .now() + 3) == .success, "render lock held by background work")
let start = CFAbsoluteTimeGetCurrent()
layer.display()
check(CFAbsoluteTimeGetCurrent() - start < 0.1, "fullscreen main display must not wait for the GL lock")
release.signal()
drain { renders > 0 }

layer.fullscreenTransition = (generation: 1, active: false, finishing: false)
for isManualResize in [false, true] {
  layer.isAnimatingWindowResize = !isManualResize
  layer.inLiveResize = isManualResize
  let held = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
  let previousRenders = renders
  DispatchQueue.global().async {
    layer.displayLock.lock(); held.signal()
    _ = release.wait(timeout: .now() + 0.3)
    layer.displayLock.unlock()
  }
  check(held.wait(timeout: .now() + 3) == .success, "resize render lock held")
  let start = CFAbsoluteTimeGetCurrent()
  layer.display()
  check(CFAbsoluteTimeGetCurrent() - start < 0.1, "window resizing must not wait for the GL lock")
  release.signal()
  drain { renders > previousRenders }
}
layer.isAnimatingWindowResize = false
layer.inLiveResize = false
layer.fullscreenTransition = (generation: 1, active: true, finishing: false)
layer.onDisplay = nil
layer.endFullscreenTransition()
check(layer.contentsGravity == .resizeAspect, "full-bounds handoff keeps the fitted image")
layer.bounds.size = CGSize(width: 1800, height: 1090)
layer.lastRenderedPixelSize = CGSize(width: 1600, height: 680)
let copy = Layer(copy: layer)
copy.bounds.size = CGSize(width: 800, height: 340)
copy.completeFullscreenTransitionIfReady()
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
check(layer.fullscreenTransition.active, "old shadow dimensions cannot finish the owner's handoff")
layer.lastRenderedPixelSize = CGSize(width: 3600, height: 2180)
layer.completeFullscreenTransitionIfReady()
drain { !layer.fullscreenTransition.active }
check(layer.contentsGravity == .resizeAspect, "render completion cannot zoom an older letterboxed surface")
check(!copy.fullscreenTransition.active, "shadow copies share transition lifetime")

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 200, height: 100).fill()
NSColor.green.setFill()
NSRect(x: 0, y: 0, width: 10, height: 100).fill()
NSRect(x: 190, y: 0, width: 10, height: 100).fill()
NSGraphicsContext.restoreGraphicsState()
let visual = CALayer()
visual.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
visual.contents = bitmap.cgImage
visual.contentsGravity = layer.contentsGravity
let pixels = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
visual.render(in: pixels)
let rendered = NSBitmapImageRep(cgImage: pixels.makeImage()!)
for x in [2, 97] {
  let color = rendered.colorAt(x: x, y: 50)!.usingColorSpace(.deviceRGB)!
  check(color.greenComponent > 0.9 && color.redComponent < 0.1,
        "cached surface keeps both image edges through completion")
}

layer.fullscreenTransition = (generation: 7, active: true, finishing: true)
layer.completeFullscreenTransitionIfReady()
layer.beginFullscreenTransition()
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
check(layer.fullscreenTransition.active && !layer.fullscreenTransition.finishing,
      "completion from an older transition cannot finish a new one")
layer.endFullscreenTransition(cancelled: true)
check(!layer.fullscreenTransition.active, "close cancels the transition without waiting for another frame")
check(layer.contentsGravity == .resizeAspectFill, "cancellation restores normal contents placement")
let crop = Layer()
let cropVideo = Video(); crop.videoView = cropVideo; cropVideo.videoLayer = crop
crop.isAnimatingWindowResize = true
crop.isAsynchronous = true
var cropDraws = 0
crop.onDisplay = {
  check(Thread.isMainThread && crop.isDrawingGeometryHandoff && crop.forceDraw,
        "crop layout boundary forces its final native viewport on main")
  check(!crop.isAsynchronous, "the automatic GL timer cannot compete with the synchronous crop boundary")
  cropDraws += 1
}
crop.displayForCropHandoff()
check(cropDraws == 1 && !crop.isDrawingGeometryHandoff && crop.isAnimatingWindowResize,
      "synchronous crop handoff releases only its temporary draw permission")
let geometry = Layer(), geometryVideo = Video()
geometry.videoView = geometryVideo; geometryVideo.videoLayer = geometry
geometry.onDisplay = {}
geometry.withCropFrameUpdate {
  check(geometry.isPreparingCropFrame, "resized native draw waits while layout and projection change together")
  geometry.withCropFrameUpdate { check(geometry.isPreparingCropFrame, "nested layout cannot release an outer native update") }
  check(geometry.isPreparingCropFrame, "outer native update retains its draw gate")
}
check(!geometry.isPreparingCropFrame, "geometry update releases native drawing after projection is ready")
geometry.setCropFramePreparation(true)
geometry.withCropFrameUpdate {}
check(geometry.isPreparingCropFrame, "a layout update cannot release an unfinished filter handoff")
geometry.setCropFramePreparation(false)
check(!geometry.isPreparingCropFrame, "source readiness releases filter presentation")

let handoff = Layer(), handoffVideo = Video()
handoff.videoView = handoffVideo; handoffVideo.videoLayer = handoff
handoff.isInCropTransition = true
handoff.isAnimatingWindowResize = true
handoff.isPreparingCropFrame = true
var handoffEvents: [String] = []
func backgroundCanDraw(_ layer: Layer) -> Bool {
  let done = DispatchSemaphore(value: 0)
  var acquired = false
  DispatchQueue.global().async {
    acquired = layer.displayLock.try()
    if acquired { layer.displayLock.unlock() }
    done.signal()
  }
  check(done.wait(timeout: .now() + 1) == .success, "background lock probe completed")
  return acquired
}
handoff.onDisplay = {
  check(!handoff.isPreparingCropFrame && !handoff.isAsynchronous,
        "matching canonical frame draws synchronously after layout becomes complete")
  check(!backgroundCanDraw(handoff), "background rendering cannot overtake the matching handoff draw")
  handoffEvents.append("draw")
}
HandoffTransaction.onPublish = {
  check(!backgroundCanDraw(handoff), "the native render lock remains held until compositor publication")
  handoffEvents.append("publish")
}
handoff.withCropFrameHandoff {
  check(handoff.isPreparingCropFrame && !handoff.isAsynchronous,
        "layout changes cannot expose a texture under an incomplete native projection")
  check(!backgroundCanDraw(handoff), "native layout and render ownership begin together")
  handoffEvents.append("layout")
}
HandoffTransaction.onPublish = nil
check(handoffEvents == ["layout", "draw", "publish"],
      "crop handoff publishes matching layout and live texture before yielding render ownership")
check(backgroundCanDraw(handoff) && !handoff.isPreparingCropFrame && handoff.isInCropTransition,
      "live playback resumes after publication without releasing crop transition ownership")
print("Passed \(checks) fullscreen render ownership checks")

final class CropSurfaceFixture { var isCaptured = true }
