import Cocoa
import OpenGL
import QuartzCore
struct RenderFlag { let rawValue: UInt64 }
let MPV_RENDER_FRAME_INFO_PRESENT = RenderFlag(rawValue: 1)
enum RenderParamType { case nextFrameInfo }
let MPV_RENDER_PARAM_NEXT_FRAME_INFO = RenderParamType.nextFrameInfo
struct mpv_render_frame_info { var flags: UInt64 = 0; var target_time: Int64 = 0 }
func mpv_get_time_ns(_ handle: Int) -> Int64 { 0 }
struct mpv_render_param { let type: RenderParamType; let data: UnsafeMutablePointer<mpv_render_frame_info> }
var pendingFrameFlags: UInt64 = 0
func mpv_render_context_update(_ context: Int) -> UInt64 { 1 }
func mpv_render_context_get_info(_ context: Int, _ param: mpv_render_param) -> Int32 { param.data.pointee.flags = pendingFrameFlags; return 0 }
class ReadLock { var value = false; func withReadLock<T>(_ body: (Bool) -> T) -> T { body(value) } }
class MPV { var mpv = 1; var mpvRenderContext: Int? = 1; var hasFrame = false; var polls = 0; func shouldRenderUpdateFrame() -> Bool { polls += 1; return hasFrame } }
class Player { let mpv = MPV() }
class Video { let player = Player(); let uninitialized = ReadLock() }
class GeometryLayer: CAOpenGLLayer {
 func deferCropDisplay(until: Int64, now: Int64) -> Bool { false }
 var cropSurface: CropSurfaceFixture?
 func requestCropDisplay(_ surface: CropSurfaceFixture) {}
 let videoView = Video()
 var inLiveResize = false
 var isAnimatingWindowResize = false
 var isDrawingGeometryHandoff = false
 var isInCropTransition = false
 var isHostedInPIP = false
 var isPreparingCropFrame = false
 var skippedEmptyCropFrame = false
 var isInFullscreenTransition = false
 var forceDraw = false
 var lastRenderedPixelSize: CGSize?
// PRODUCTION_GEOMETRY

}
let app = NSApplication.shared
let ctx = CGLContextObj(bitPattern: 1)!
let pf = OpaquePointer(bitPattern: 2)!
var checks = 0
func check(_ value: Bool, _ message: String) { if !value { print("FAILED: " + message); exit(1) }; checks += 1 }
for scale: CGFloat in [1, 2] {
 let layer = GeometryLayer()
 layer.bounds = CGRect(x: 0, y: 0, width: 900, height: 507)
 layer.contentsScale = scale
 func canDraw() -> Bool { layer.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil) }
 layer.forceDraw = true
 check(canDraw(), "first explicit frame needs a surface")
 layer.forceDraw = false
 layer.lastRenderedPixelSize = CGSize(width: 900 * scale, height: 507 * scale)
 check(!canDraw(), "same paused geometry does not render repeatedly")
 layer.bounds.size = CGSize(width: 328, height: 185)
 check(canDraw(), "paused PiP shrink must render without a new decoded frame")
 layer.lastRenderedPixelSize = CGSize(width: 328 * scale, height: 185 * scale)
 check(!canDraw(), "completed shrink does not repeat")
 layer.invalidatePIPDisplay()
 check(canDraw(), "new native surface at the same size must render")
 layer.lastRenderedPixelSize = CGSize(width: 328 * scale, height: 185 * scale)
 check(!canDraw(), "new surface does not render repeatedly")
 layer.bounds.size = CGSize(width: 900, height: 507)
 check(canDraw(), "paused flyback enlargement must render")
 layer.lastRenderedPixelSize = CGSize(width: 900 * scale, height: 507 * scale)
 layer.contentsScale = scale == 1 ? 2 : 1
 check(canDraw(), "Retina scale change must render")
 layer.lastRenderedPixelSize = CGSize(width: 900 * layer.contentsScale, height: 507 * layer.contentsScale)
 check(!canDraw(), "stable Retina geometry does not render repeatedly")
 layer.videoView.player.mpv.hasFrame = true
 check(canDraw(), "normal live playback still renders")
 layer.videoView.player.mpv.hasFrame = false
 layer.forceDraw = true
 check(canDraw(), "explicit handoff redraw still renders")
 layer.videoView.uninitialized.value = true
 check(!canDraw(), "teardown prevents forced render")
 layer.videoView.uninitialized.value = false
 layer.inLiveResize = true
 check(!canDraw(), "main-thread live resize still skips rendering")
 layer.inLiveResize = false
 layer.bounds.size = .zero
 check(!canDraw(), "empty surface never renders")
}
let crop = GeometryLayer()
crop.bounds = CGRect(x:0,y:0,width:800,height:450)
crop.isInCropTransition = true; crop.forceDraw = true
pendingFrameFlags = 0
check(!crop.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil),
      "crop reconfiguration cannot render mpv's empty dummy frame even with a forced draw")
pendingFrameFlags = 1
check(crop.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil),
      "the first real crop frame resumes the existing native surface")
crop.videoView.player.mpv.mpvRenderContext = nil
check(!crop.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil),
      "a missing render context cannot complete crop presentation")

final class CropSurfaceFixture { var isCaptured = true }

crop.videoView.player.mpv.mpvRenderContext = 1
crop.isPreparingCropFrame = true
pendingFrameFlags = 1
check(!crop.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil), "filter handoff cannot expose a frame before projection matches its source")

crop.isPreparingCropFrame = false
check(crop.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil), "ready source projection resumes native presentation")
let pipPaused = GeometryLayer()
pipPaused.isHostedInPIP = true
pipPaused.bounds = CGRect(x: 0, y: 0, width: 328, height: 185)
pendingFrameFlags = 0
check(pipPaused.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil), "paused PiP must redraw cached video into a fresh native surface without a queued frame")
pipPaused.lastRenderedPixelSize = CGSize(width: 328, height: 185)
check(!pipPaused.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil), "unchanged paused PiP does not spin")
pipPaused.forceDraw = true
check(pipPaused.canDraw(inCGLContext: ctx, pixelFormat: pf, forLayerTime: 0, displayTime: nil), "explicit paused PiP handoff can use the cached current frame")
print("Passed \(checks) production geometry render checks")
