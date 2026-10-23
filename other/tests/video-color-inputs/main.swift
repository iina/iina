let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS: \(message)")
}
func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
let player = PlayerCore()
private let view = EqualizerView(player: player)
let inputs = descendants(view).compactMap { $0 as? NSTextField }.filter(\.isEditable).sorted { $0.tag < $1.tag }
let sliders = descendants(view).compactMap { $0 as? NSSlider }.sorted { $0.tag < $1.tag }
check(inputs.count == 5 && sliders.count == 5, "each color parameter has a slider and editable value")
check(inputs.map(\.integerValue) == [12, -8, 5, -2, 17], "initial values reflect the current engine settings")
func submit(_ index: Int, _ text: String) {
  inputs[index].stringValue = text
  _ = inputs[index].sendAction(inputs[index].action!, to: inputs[index].target)
}
submit(0, "24")
check(player.profiles[0]!.brightness == 24 && sliders[0].integerValue == 24, "typed integer updates Output and its slider")
sliders[1].integerValue = -33
_ = sliders[1].sendAction(sliders[1].action!, to: sliders[1].target)
check(inputs[1].integerValue == -33 && player.profiles[0]!.contrast == -33, "slider updates the number field and Output")
submit(2, "999")
submit(3, "-999")
check(player.profiles[0]!.saturation == 100 && player.profiles[0]!.gamma == -100 && inputs[2].integerValue == 100 && inputs[3].integerValue == -100, "out-of-range values clamp at the engine limits")
submit(4, "")
check(player.profiles[0]!.hue == 0 && inputs[4].integerValue == 0, "empty color input resets its parameter to zero")
let writesBeforeInvalid = player.writes.count
submit(4, "wrong")
check(player.writes.count == writesBeforeInvalid && inputs[4].integerValue == 0, "invalid nonempty input restores the current value without writing")
let output = player.profiles[0]!
player.scopedTrackSettings.id = 1; player.post(.iinaTrackSettingsChanged)
check(inputs[0].integerValue == -31 && sliders[0].integerValue == -31, "Configure refreshes both controls from the selected source")
submit(0, "42")
check(player.profiles[1]!.brightness == 42 && player.profiles[0]!.brightness == output.brightness, "source input preserves Output")
player.rejectNextWrite = true
submit(0, "55")
check(inputs[0].integerValue == 42 && sliders[0].integerValue == 42, "failed source processing restores the displayed values")
player.mainWindow.interactiveMode.isActive = true; player.post(.iinaTrackSettingsChanged)
check(inputs.allSatisfy { !$0.isEnabled } && sliders.allSatisfy { !$0.isEnabled }, "interactive crop disables both editing paths")
let writesBeforeCrop = player.writes.count
submit(0, "10")
check(player.writes.count == writesBeforeCrop && inputs[0].integerValue == 42, "stale input actions cannot edit during crop")
player.mainWindow.interactiveMode.isActive = false; player.post(.iinaTrackSettingsChanged)
let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
host.addSubview(view)
view.leadingAnchor.constraint(equalTo: host.leadingAnchor).isActive = true
view.topAnchor.constraint(equalTo: host.topAnchor).isActive = true
let width = view.widthAnchor.constraint(equalToConstant: 320); width.isActive = true
for size in [320.0, 400.0] {
  width.constant = size; host.layoutSubtreeIfNeeded()
  check(sliders.allSatisfy { $0.frame.width > 80 } && inputs.allSatisfy { abs($0.frame.width - 50) < 0.1 && $0.isBezeled }, "slider and native fixed-width fields fit sidebar width \(size)")
}
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false; window.contentView = host
window.makeFirstResponder(inputs[0])
if let editor = inputs[0].currentEditor() {
  editor.string = "63"
  window.makeFirstResponder(inputs[1])
  check(player.profiles[1]!.brightness == 63 && sliders[0].integerValue == 63, "native focus loss commits the typed value")
  window.makeFirstResponder(inputs[0])
  inputs[0].currentEditor()?.string = ""
  window.makeFirstResponder(inputs[1])
  check(player.profiles[1]!.brightness == 0 && inputs[0].integerValue == 0, "empty formatted color input resets on native focus loss")
  window.makeFirstResponder(inputs[0])
  inputs[0].currentEditor()?.string = "77"
  player.profiles[1]!.brightness = 0; player.post(.iinaTrackSettingsChanged)
  window.makeFirstResponder(inputs[1])
  check(player.profiles[1]!.brightness == 0 && inputs[0].integerValue == 0, "Reset replaces an unfinished edit instead of restoring it later")
} else { preconditionFailure("native field editor unavailable") }
window.close()
print("Completed \(checks) production color value input checks.")
