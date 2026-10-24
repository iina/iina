let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message); checks += 1; print("PASS \(message)")
}
final class SpeedLayout: SidebarSliderView {
  override var titleKey: String { "Speed" }
  override var showsTitle: Bool { false }
  override var tickMarkLabels: [String] { ["0.25x", "1x", "4x", "16x"] }
  override func setup() { slider.minValue = 0; slider.maxValue = 24 }
}
// Use the production AudioDelay visibility overrides without its engine actions.
final class DelayLayout: SidebarSliderView {
  // AUDIO_VISIBILITY
  override var tickMarkLabels: [String] { ["-5s", "0s", "+5s"] }
}
let player = PlayerCore()
let host = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 200))
func attach(_ view: SidebarSliderView) {
  host.subviews.forEach { $0.removeFromSuperview() }
  host.addSubview(view)
  view.widthAnchor.constraint(equalToConstant: 320).isActive = true
  view.leadingAnchor.constraint(equalTo: host.leadingAnchor).isActive = true
  view.topAnchor.constraint(equalTo: host.topAnchor).isActive = true
  host.layoutSubtreeIfNeeded()
}
let speed = SpeedLayout(player: player)
attach(speed)
host.layoutSubtreeIfNeeded()
let baselineHeight = speed.fittingSize.height
let baselineSlider = speed.slider.frame
for value in [8.0, 8.4, 9, 8, 7.6, 8, 24, 0, 8] {
  speed.slider.doubleValue = value
  host.layoutSubtreeIfNeeded()
  check(speed.fittingSize.height == baselineHeight, "Speed card height stays fixed at slider value \(value)")
  check(speed.slider.frame == baselineSlider, "Speed slider stays under the pointer at \(value)")
}
let delay = DelayLayout(player: player)
attach(delay)
check(delay.subviews.allSatisfy { !($0 is NSButton) } && speed.subviews.allSatisfy { !($0 is NSButton) }, "Speed and Delay expose no inline Reset button")
check(abs(delay.input.frame.maxX - delay.bounds.maxX) < 0.01, "Delay value reaches the trailing edge without a reset gap")
check(delay.input is SidebarInputField && delay.input.isBezeled && delay.input.frame.size == NSSize(width: 50, height: 24), "the native field owns the full visible input bounds")
check(delay.input.focusRingType == .exterior && delay.input.superview === delay, "focus ring follows the complete field without an inset container")
check(delay.fittingSize.height > 0 && delay.slider.frame.width > 0, "Delay keeps a valid slider layout")
print("Sidebar slider layout checks passed: \(checks).")
