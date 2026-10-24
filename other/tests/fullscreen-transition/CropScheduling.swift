import Foundation
// PRODUCTION_ATOMIC
final class Lock { let lock=NSLock();func withLock<T>(_ body:()throws->T) rethrows ->T {lock.lock();defer{lock.unlock()};return try body()} }
final class Scheduling {
 var isAsynchronous=false
 var isInFullscreenTransition=false
 var updates=0
 func update(force:Bool=false) {updates += 1}
 // PRODUCTION_SCHEDULING
}
var checks=0
func check(_ value:Bool,_ reason:String) {if !value{print("FAILED: "+reason);exit(1)};checks += 1}
let layer=Scheduling()
layer.isAnimatingWindowResize=true
check(layer.isAsynchronous,"ordinary native window resize retains automatic drawing")
layer.isInCropTransition=true
check(!layer.isAsynchronous,"crop preparation cannot leave a CA main-thread GL timer waiting on the native render context")
layer.isAnimatingWindowResize=true
check(!layer.isAsynchronous,"a crop-owned window step cannot reactivate the competing main-thread GL timer")
layer.inLiveResize=true
check(!layer.isAsynchronous,"manual resize during a crop handoff keeps the existing render-queue owner")
layer.isInCropTransition=false
check(layer.isAsynchronous,"interruption restores normal native resize scheduling")
let stable=Scheduling()
stable.isInCropTransition=true;stable.isInCropTransition=false
check(!stable.isAsynchronous,"ordinary playback remains driven by native frame updates")
print("Passed \(checks) crop render scheduling checks")
