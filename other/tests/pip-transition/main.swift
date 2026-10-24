let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var count=0
func check(_ value: @autoclosure () -> Bool, _ name: String) {
 precondition(value(),name);count += 1
}
for behavior in [Preference.WindowBehaviorWhenPip.hide,.minimize,.doNothing] {
 for fullscreen in [false,true] {
  for paused in [false,true] {
   Preference.behavior=behavior
   let c=MainWindowController();let w=c.window as! Window
   c.fsState.isFullscreen=fullscreen
   w.simulatedFullscreen=fullscreen
   c.player.info.state=paused ? .paused : .playing
   w.alphaValue=0.85
   c.enterPIP()
   check(c.pipStatus == .inPIP,"entered"); check(c.videoView.videoLayer.isHostedInPIP,"native transaction owned")
   check(c.pipVideo.view === c.videoView || c.videoView.superview === c.pipVideo.view,"same live surface")
   check(c.pip.playing == !paused,"playback preserved")
   c.enterPIP();check(c.pip.presented == 1,"duplicate entry suppressed")
   check(c.isWindowHidden == (behavior == .hide && !fullscreen),"hide policy")
   check(w.minimized == (behavior == .minimize && !fullscreen),"minimize policy")
   check(c.pipOverlayView.isHidden == (behavior == .hide && !fullscreen),"placeholder only in retained player")
   if c.isWindowHidden { check(w.orderOutAnimations.last == NSWindow.AnimationBehavior.none,"hide has no fade"); check(w.animationBehavior == .default,"source animation restored") }
   let hidden=c.isWindowHidden
   c.exitPIP()
   check(c.pipStatus == .intermediate,"returning")
   check(c.pip.dismissed == 1,"one native dismissal")
   check(c.pip.replacementWindow === w,"return window")
   check(c.pip.replacementRect == c.videoViewContainer.convert(c.videoViewContainer.bounds,to:nil),"video destination")
   if hidden {
    check(w.alphaValue == 0,"destination concealed")
    check(c.oscFloatingView.isHidden,"OSC hidden during return")
    c.showUI();check(c.oscFloatingView.isHidden,"tracking cannot reveal early")
   }
   c.enterPIP();check(c.pip.presented == 1,"entry blocked during return")
   c.pipWillClose(c.pip);check(c.pipReturnWindowAlpha == (hidden ? 0.85 : nil),"duplicate closure does not overwrite alpha")
   c.pipDidClose(c.pip)
   check(c.pipStatus == .notInPIP,"returned"); check(!c.videoView.videoLayer.isHostedInPIP,"native transaction released")
   check(c.videoView.superview === c.videoViewContainer,"live surface reattached")
   check(abs(w.alphaValue-0.85) < 0.001,"opacity restored")
   check(c.pipReturnWindowAlpha == nil,"return flag cleared")
   if hidden {
    check(!c.oscFloatingView.isHidden,"OSC revealed")
    check(c.titleBarView.revealCalls.contains { $0.0 && $0.1 },"header uses normal animation")
   }
  }
 }
}
PiP.modern = true
for behavior in [Preference.WindowBehaviorWhenPip.hide,.minimize,.doNothing] {
 Preference.behavior=behavior
 let c=MainWindowController();let w=c.window as! Window
 let expected=w.convertToScreen(c.videoViewContainer.convert(c.videoViewContainer.bounds,to:nil))
 c.videoView.beforeHandoff = { check(w.testVisible, "entry drawn before hiding source") }
 c.enterPIP()
 check(w.testVisible && !w.minimized,"source remains until preparation")
 check(c.videoView.superview === c.videoViewContainer,"live playback remains in source during native preparation")
 check(!c.videoView.videoLayer.isHostedInPIP,"source keeps normal rendering ownership during preparation")
 check(c.operationFeedbackRequests.count == 1,"preparation owns delayed feedback")
 let callback=c.pip.completion!
 c.videoViewContainer.frame.size = NSSize(width: 640,height: 360)
 callback()
 check(c.videoView.superview === c.pipVideo.view,"same live view transfers only when native host is ready")
 check(c.videoView.videoLayer.isHostedInPIP,"native ownership begins with transfer")
 check(c.operationFeedbackRequests.isEmpty,"ready handoff completes its feedback")
 check(c.isWindowHidden == (behavior == .hide),"prepared hide policy")
 check(w.minimized == (behavior == .minimize),"prepared minimize policy")
 if behavior == .hide {
  check(c.pip.window.contentRect(forFrameRect:c.pip.window.frame) == expected,"native launch uses source video geometry")
 }
 c.pip.window.setContentSize(NSSize(width: 328, height: 185))
 check(c.pipVideo.view.bounds.size == NSSize(width: 328, height: 185),"staged container follows the actual native host")
 check(c.videoView.frame == c.pipVideo.view.bounds,"live video fits its receiving container after native resize")
 check(c.pip.window.frontCalls == 0,"no forced local host presentation")
 check(c.pip.window.animationBehavior == .default,"host animation restored")
 let draws=c.videoView.handoffs
 check(draws == 1, "one preparation draw")
 let frame=c.pip.window.frame
 callback();check(c.videoView.handoffs == draws,"duplicate preparation does not draw")
 c.videoView.beforeHandoff = {
  check(c.videoView.superview === c.videoViewContainer,"return layout owns live view before draw")
  if behavior == .hide { check(w.alphaValue == 0,"return drawn before reveal") }
 }
 callback();check(c.pip.window.frame == frame,"duplicate callback ignored")
 c.exitPIP();c.pipDidClose(c.pip)
 check(c.videoView.handoffs == draws + 1,"one final return draw")
 c.videoView.beforeHandoff = nil
 callback();check(w.testVisible,"late callback cannot hide restored source")
 c.enterPIP()
 callback();check(w.testVisible,"previous presentation callback cannot hide new source")
 c.pip.completion?()
 c.exitPIP();c.pipDidClose(c.pip)
}
Preference.behavior = .hide
let cancelled=MainWindowController();let sourceWindow=cancelled.window as! Window
cancelled.enterPIP();let stale=cancelled.pip.completion!
cancelled.exitPIP();stale()
check(cancelled.operationFeedbackRequests.isEmpty,"cancelled preparation releases feedback")
check(sourceWindow.testVisible,"return before preparation cannot hide source")
cancelled.pipDidClose(cancelled.pip)
let feedbackOwner = MainWindowController()
let capture = feedbackOwner.beginOperationFeedback()
let sharedToken = feedbackOwner.operationFeedbackToken
let lut = feedbackOwner.beginOperationFeedback()
check(feedbackOwner.operationFeedbackRequests.count == 2,"overlap keeps independent request ownership")
check(feedbackOwner.operationFeedbackToken == sharedToken,"overlap keeps the original feedback clock")
check(feedbackOwner.operationFeedbackView?.hitTest(.zero) == nil,"generic feedback never intercepts controls")
feedbackOwner.endOperationFeedback(capture)
check(feedbackOwner.operationFeedbackToken == sharedToken,"first completion cannot hide pending import")
feedbackOwner.endOperationFeedback(lut)
check(feedbackOwner.operationFeedbackToken == nil,"last completion releases shared feedback")
let replacement = feedbackOwner.beginOperationFeedback()
let replacementToken = feedbackOwner.operationFeedbackToken
feedbackOwner.endOperationFeedback(capture)
check(feedbackOwner.operationFeedbackToken == replacementToken,"stale completion cannot hide a replacement")
feedbackOwner.closeFeedback()
check(feedbackOwner.operationFeedbackView == nil && feedbackOwner.operationFeedbackRequests.isEmpty,"window closure invalidates feedback")
feedbackOwner.endOperationFeedback(replacement)
check(feedbackOwner.operationFeedbackToken == nil,"late completion after closure stays cancelled")
let nativeCancelled = MainWindowController()
nativeCancelled.enterPIP()
let nativeStale = nativeCancelled.pip.completion!
nativeCancelled.pipWillClose(nativeCancelled.pip)
check(nativeCancelled.operationFeedbackRequests.isEmpty,"native close before readiness releases feedback")
nativeStale()
nativeCancelled.pipDidClose(nativeCancelled.pip)
let overlap = MainWindowController()
let captureInPlayer = overlap.beginOperationFeedback()
let overlapClock = overlap.operationFeedbackToken
overlap.enterPIP(); overlap.pip.completion?()
check(overlap.operationFeedbackView?.superview === overlap.videoView,"pending screenshot feedback follows live video into PiP")
check(overlap.operationFeedbackToken == overlapClock,"transfer preserves pending feedback clock")
overlap.exitPIP(); overlap.pipDidClose(overlap.pip)
check(overlap.operationFeedbackView?.superview === overlap.videoViewContainer,"pending feedback follows return")
overlap.endOperationFeedback(captureInPlayer)
// The editor owns the native layer's projection and an uncommitted source.
// PiP must release that ownership before its first handoff, on both APIs.
for modern in [false, true] {
 for editor in ["crop", "delogo"] {
  PiP.modern = modern
  let c = MainWindowController()
  c.videoView.wantsLayer = true
  let mask = CALayer()
  c.videoView.layer!.mask = mask
  c.videoView.layer!.transform = CATransform3DMakeScale(0.7, 0.7, 1)
  c.standardWindowButtons[0].isEnabled = false
  c.interactiveMode.isActive = true
  c.interactiveMode.onExit = {
   check(c.videoView.superview === c.videoViewContainer, "\(editor) exits in its original container")
   c.videoView.layer!.mask = nil
   c.videoView.layer!.transform = CATransform3DIdentity
   c.standardWindowButtons[0].isEnabled = true
  }
  c.videoView.beforeHandoff = {
   check(!c.interactiveMode.isActive, "\(editor) releases ownership before PiP draws")
   check(c.videoView.layer!.mask == nil && CATransform3DIsIdentity(c.videoView.layer!.transform), "PiP receives the restored player projection")
   check(c.standardWindowButtons[0].isEnabled, "editor controls are restored before PiP")
  }
  c.enterPIP()
  c.pip.completion?()
  check(c.interactiveMode.exitCalls == 1, "PiP exits \(editor) exactly once")
  c.enterPIP()
  check(c.interactiveMode.exitCalls == 1, "duplicate PiP entry cannot exit the editor again")
  c.videoView.beforeHandoff = nil
  c.interactiveMode.onExit = nil
  c.exitPIP(); c.pipDidClose(c.pip)
 }
}
for modern in [false, true] {
 PiP.modern = modern
 let c = MainWindowController()
 c.isCropTransitionInProgress = true
 var commits = 0
 c.onCancelCropTransition = {
  check(c.videoView.superview === c.videoViewContainer, "pending crop commits before reparenting")
  commits += 1
 }
 c.videoView.beforeHandoff = {
  check(!c.isCropTransitionInProgress && commits == 1, "PiP releases a Custom Crop exit transition before drawing")
 }
 c.enterPIP(); c.pip.completion?()
 c.videoView.beforeHandoff = nil
 c.onCancelCropTransition = nil
 c.exitPIP(); c.pipDidClose(c.pip)
}
print("Native PiP production-method checks passed: \(count)")
