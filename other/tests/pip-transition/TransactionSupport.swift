import Foundation
class Base { func display() {} }
class PriorityLock { func beforeLocking() {}; func afterLocked() {} }
enum CATransaction {
 static var flushes = 0; static var begins = 0; static var commits = 0
 static func begin() { begins += 1 }; static func commit() { commits += 1 }; static func flush() { flushes += 1 }
}
class Layer: Base {
 func deferCropDisplayUntilFrameTime() -> Bool { false }
 var cropSurface: CropSurfaceFixture?
 func requestCropDisplay(_ surface: CropSurfaceFixture) {}
 let displayLock = NSRecursiveLock(); let mainThreadPriorityLock = PriorityLock()
 var needsFlip = false; var isHostedInPIP = false
 var isDrawingGeometryHandoff = false
 var skippedEmptyCropFrame = false
 var isInFullscreenTransition = false
 var inLiveResize = false, isAnimatingWindowResize = false
 func scheduleFullscreenDisplay() { preconditionFailure("PiP must keep its main-thread surface transaction") }
 func completeFullscreenTransitionIfReady() {}
// PRODUCTION_DISPLAY

}
var checks = 0
func check(_ value: Bool, _ message: String) { if !value { print("FAILED: " + message); exit(1) }; checks += 1 }
for hosted in [false, true] {
 let layer = Layer(); layer.isHostedInPIP = hosted
 CATransaction.flushes = 0; CATransaction.begins = 0; CATransaction.commits = 0
 layer.display()
 check(CATransaction.flushes == (hosted ? 0 : 1), "native main-thread fence must remain unflushed")
 check(CATransaction.begins == 0 && CATransaction.commits == 0, "main-thread transaction remains owned by AppKit")
 CATransaction.flushes = 0
 let done = DispatchSemaphore(value: 0)
 DispatchQueue.global().async { layer.display(); done.signal() }
 check(done.wait(timeout: .now() + 3) == .success, "background display completed")
 check(CATransaction.flushes == 1, "background display still flushes")
 check(CATransaction.begins == 1 && CATransaction.commits == 1, "background explicit transaction preserved")
}
print("Passed \(checks) production transaction checks")

final class CropSurfaceFixture { var isCaptured = true }
