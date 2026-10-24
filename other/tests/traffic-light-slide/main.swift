let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                      backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let header = HeaderHarness()
window.contentView!.addSubview(header)
header.headerHeightConstraint = header.heightAnchor.constraint(equalToConstant: 40)
let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
  .map { window.standardWindowButton($0)! }
let hosts = buttons.map { $0.superview! }
let frames = buttons.map { $0.frame }
var checks = 0
var failures = 0
func check(_ condition: Bool, _ message: String) {
  checks += 1
  if !condition { failures += 1; print("FAIL: \(message)") }
}
header.trackWindowButtons()
header.reveal(false, animated: false)
for button in buttons {
  check(button.alphaValue < 0.001, "hidden native button stays invisible")
  check(abs(button.layer!.transform.m42) == 40, "hidden button is positioned above the header")
}
NSAnimationContext.runAnimationGroup { context in
  context.duration = 0.25
  context.timingFunction = CAMediaTimingFunction(name: .easeOut)
  header.reveal(true, animated: true)
}
for (index, button) in buttons.enumerated() {
  let slide = button.layer!.animation(forKey: "headerSlide") as? CABasicAnimation
  check(button.alphaValue == 1, "button is visible throughout the reveal, without a delayed alpha switch")
  check(slide?.duration == 0.25, "native button shares the header duration")
  check(abs((slide?.fromValue as? NSValue)?.caTransform3DValue.m42 ?? 0) == 40,
        "reveal begins offscreen")
  check((slide?.toValue as? NSValue)?.caTransform3DValue.m42 == 0, "reveal ends at its native position")
  check(button.superview === hosts[index] && button.frame == frames[index], "AppKit host and native frame are retained")
}
header.trackWindowButtons()
check(buttons.allSatisfy { $0.layer?.animation(forKey: "headerSlide") != nil }, "layout refresh does not cancel the slide")
NSAnimationContext.runAnimationGroup { context in
  context.duration = 0.25
  header.reveal(false, animated: true)
}
check(buttons.allSatisfy { $0.alphaValue == 1 }, "hide slides the buttons away instead of immediately removing them")
header.finishHiding()
check(buttons.allSatisfy { $0.alphaValue < 0.001 }, "hide completion suppresses invisible native widgets")
AccessibilityPreferences.motionReductionEnabled = true
NSAnimationContext.runAnimationGroup { context in
  context.duration = 0
  header.reveal(true, animated: true)
}
check(buttons.allSatisfy { $0.layer?.animation(forKey: "headerSlide") == nil && $0.layer?.transform.m42 == 0 },
      "Reduce Motion uses opacity without displacement")
header.restoreWindowButtons()
check(buttons.enumerated().allSatisfy { $0.element.superview === hosts[$0.offset] && $0.element.frame == frames[$0.offset]
  && $0.element.alphaValue == 1 && CATransform3DIsIdentity($0.element.layer!.transform) },
      "fullscreen restoration returns every native button to its original state")
print("Completed \(checks) native traffic-light checks with \(failures) failures.")
exit(failures == 0 ? 0 : 1)
