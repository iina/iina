let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
setbuf(stdout, nil)
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  guard value() else { fputs("FAILED: \(message)\n", stderr); exit(1) }
  checks += 1
  print("PASS: \(message)")
}
let allTypes = (0...8).compactMap(Preference.ToolBarButton.init(rawValue:))
check(allTypes.count == 9, "all current toolbar roles are covered")

func symbolPixels(_ image: NSImage?) -> Data? {
  guard let image,
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 256, bitsPerPixel: 32),
        let context = NSGraphicsContext(bitmapImageRep: bitmap), let pixels = bitmap.bitmapData else { return nil }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: 64, height: 64).fill(using: .copy)
  image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  return Data(bytes: pixels, count: 64 * 256)
}
func expected(_ type: Preference.ToolBarButton, active: Bool) -> Data? {
  symbolPixels(active ? type.alternateImage() ?? type.image() : type.image())
}
func window() -> NSWindow {
  let result = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                        styleMask: .borderless, backing: .buffered, defer: false)
  result.isReleasedWhenClosed = false
  result.appearance = NSAppearance(named: .darkAqua)
  return result
}
func button(_ type: Preference.ToolBarButton, host: NSWindow, x: CGFloat = 20, compact: Bool = false) -> OSCToolbarButton {
  let result = OSCToolbarButton(frame: NSRect(x: x, y: 35, width: 24, height: 24))
  OSCToolbarButton.setStyle(of: result, buttonType: type, reducedWidth: compact)
  host.contentView!.addSubview(result)
  return result
}
func hover(_ button: NSButton, entered: Bool) {
  let type: NSEvent.EventType = entered ? .mouseEntered : .mouseExited
  let event = NSEvent.enterExitEvent(with: type, location: button.convert(.zero, to: nil),
    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: button.window?.windowNumber ?? 0,
    context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
  if entered { button.mouseEntered(with: event) } else { button.mouseExited(with: event) }
}
func press(_ button: NSButton, _ pressed: Bool) {
  button.cell!.highlight(pressed, withFrame: button.bounds, in: button)
}
func animations(_ button: NSButton) -> [CAAnimation] {
  (button.layer?.animationKeys() ?? []).compactMap { button.layer?.animation(forKey: $0) }
}
func checkOnlyFeedbackAnimations(_ button: NSButton, _ context: String) {
  let values = animations(button)
  check(values.allSatisfy { animation in
    guard let basic = animation as? CABasicAnimation else { return false }
    return ["opacity", "shadowOpacity"].contains(basic.keyPath ?? "")
  }, "\(context) animates only icon brightness/glow")
  check(values.allSatisfy { (0.07...0.14001).contains($0.duration) }, "\(context) stays within the short feedback duration")
}

for type in allTypes {
  let host = window()
  let control = button(type, host: host)
  check(!host.isVisible && !NSApp.isActive, "\(type) fixture does not show or activate a window")
  check(!control.isActive && symbolPixels(control.image) == expected(type, active: false), "\(type) starts with its existing configured symbol")
  check(control.imagePosition == .imageOnly && !control.isBordered && control.tag == type.rawValue,
        "\(type) retains its native icon/button contract")
  let dimensions = control.constraints.filter { $0.firstAttribute == .width || $0.firstAttribute == .height }
  check(dimensions.count == 2 && dimensions.allSatisfy { $0.constant == Preference.ToolBarButton.frameSize },
        "\(type) retains its original hit dimensions")
  let configuration = NSImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
  control.symbolConfiguration = configuration
  let configurationData = try! NSKeyedArchiver.archivedData(withRootObject: control.symbolConfiguration!, requiringSecureCoding: true)
  let frame = control.frame
  let normal = control.image
  let baseline = control.layer!.opacity
  let receiver = ActionReceiver()
  control.target = receiver; control.action = #selector(ActionReceiver.clicked(_:))
  press(control, true)
  check(!control.isActive && symbolPixels(control.image) == expected(type, active: true), "\(type) native highlight immediately chooses its existing pressed alternate")
  check(animations(control).isEmpty, "\(type) press has no replacement or delayed feedback animation")
  check(control.layer!.opacity >= baseline && receiver.calls == 0, "\(type) press brightens without committing an action")
  press(control, false)
  check(control.image === normal && !control.isActive && receiver.calls == 0, "\(type) cancelled press restores normal without an action")
  checkOnlyFeedbackAnimations(control, "\(type) release")
  control.layer!.removeAllAnimations()
  press(control, true)
  control.setActive(true)
  check(control.isActive && symbolPixels(control.image) == expected(type, active: true), "\(type) accepted state is synchronous during a native press")
  press(control, false)
  check(control.isActive && symbolPixels(control.image) == expected(type, active: true), "\(type) release preserves an accepted active change")
  control.setActive(false)
  check(!control.isActive && control.image === normal, "\(type) reset returns to its original symbol synchronously")
  let currentConfigurationData = try! NSKeyedArchiver.archivedData(withRootObject: control.symbolConfiguration!, requiringSecureCoding: true)
  check(control.frame == frame && currentConfigurationData == configurationData,
        "\(type) feedback preserves external scale and symbol configuration")
  check(control.layer!.affineTransform().isIdentity, "\(type) feedback does not resize the icon surface")
  host.close()
}

do {
  let host = window()
  let first = button(.settings, host: host)
  let second = button(.playlist, host: host, x: 90)
  first.layer!.removeAllAnimations(); second.layer!.removeAllAnimations()
  let idleOpacity = first.layer!.opacity, otherOpacity = second.layer!.opacity
  hover(first, entered: true)
  check(first.layer!.opacity > idleOpacity && first.layer!.shadowOpacity > 0, "hover brightens and glows the addressed icon")
  check(second.layer!.opacity == otherOpacity && second.layer!.shadowOpacity == 0 && animations(second).isEmpty,
        "hover does not affect an adjacent icon")
  let shadow = NSColor(cgColor: first.layer!.shadowColor!)!.usingColorSpace(.deviceRGB)!
  check(shadow.redComponent == 1 && shadow.greenComponent == 1 && shadow.blueComponent == 1,
        "hover uses a per-icon white glow")
  check(!animations(first).isEmpty && animations(first).allSatisfy { (0.10...0.14001).contains($0.duration) },
        "hover fade uses the requested short duration")
  checkOnlyFeedbackAnimations(first, "hover")
  press(first, true)
  check(animations(first).isEmpty, "native press cancels an in-flight hover fade immediately")
  press(first, false)
  hover(first, entered: false)
  check(first.layer!.opacity == idleOpacity && first.layer!.shadowOpacity == 0, "hover exit restores the idle feedback model")
  checkOnlyFeedbackAnimations(first, "hover exit")
  first.removeFromSuperview()
  check(animations(first).isEmpty && first.layer!.shadowOpacity == 0, "window detach cancels pending exit animations and glow")
  let rebuilt = button(.settings, host: host)
  check(!rebuilt.isActive && rebuilt.layer!.opacity == idleOpacity && rebuilt.layer!.shadowOpacity == 0 && animations(rebuilt).isEmpty,
        "rebuilt toolbar controls start without an old hover/press state")
  host.close()
}

for reduced in [false, true] {
  AccessibilityPreferences.motionReductionEnabled = reduced
  Preference.disabledAnimations = !reduced
  let host = window()
  let control = button(.pip, host: host)
  hover(control, entered: true); press(control, true); control.setActive(true); press(control, false); hover(control, entered: false)
  check(animations(control).isEmpty && control.isActive && symbolPixels(control.image) == expected(.pip, active: true),
        "\(reduced ? "Reduce Motion" : "Disable animations") applies hover, press and selected state immediately")
  host.close()
}
AccessibilityPreferences.motionReductionEnabled = false; Preference.disabledAnimations = false

do {
  let host = window()
  let control = button(.settings, host: host)
  control.setActive(true)
  let active = control.image, activeOpacity = control.layer!.opacity
  hover(control, entered: true); press(control, true)
  control.isEnabled = false
  check(control.isActive && control.image === active && control.layer!.opacity < activeOpacity && control.layer!.shadowOpacity == 0 && animations(control).isEmpty,
        "disabled active icon retains semantic selection while cancelling feedback")
  hover(control, entered: true); press(control, true)
  check(control.layer!.shadowOpacity == 0 && animations(control).isEmpty, "disabled icon ignores hover and native press")
  control.isEnabled = true
  check(control.isActive && control.image === active, "re-enabled icon preserves its selected glyph")
  hover(control, entered: true); press(control, true); control.isHidden = true
  check(control.isActive && control.image === active && control.layer!.shadowOpacity == 0 && animations(control).isEmpty,
        "hidden toolbar cancels native feedback without clearing selected state")
  control.isHidden = false
  control.removeFromSuperview()
  check(control.isActive && control.image === active && animations(control).isEmpty, "detached active icon retains selection without transient feedback")
  host.close()
}
do {
  let host = window()
  let control = button(.settings, host: host)
  let receiver = ActionReceiver()
  receiver.acceptSelection = true
  var callbackImage: Data?
  var callbackState = true
  receiver.onClick = { sender in callbackImage = symbolPixels(sender.image); callbackState = sender.isActive }
  control.target = receiver; control.action = #selector(ActionReceiver.clicked(_:))
  control.performClick(nil)
  check(callbackImage == expected(.settings, active: true) && !callbackState,
        "native action retains the pressed glyph before the handler accepts selection")
  check(receiver.calls == 1 && control.isActive, "native performClick dispatches once and commits selected state")
  control.performClick(nil)
  check(receiver.calls == 2 && !control.isActive, "second native action toggles once without a replacement dispatch")
  control.isEnabled = false
  control.performClick(nil)
  check(receiver.calls == 2 && !control.isActive, "disabled native dispatch cannot invoke an action")
  control.isEnabled = true
  receiver.acceptSelection = false
  control.performClick(nil)
  check(receiver.calls == 3 && !control.isActive && callbackImage == expected(.settings, active: true) && !callbackState,
        "a rejected native action holds pressed feedback without inventing selected state")
  check(symbolPixels(control.image) == expected(.settings, active: false), "rejected action returns to the original glyph after dispatch")
  host.close()
}

do {
  let firstHost = window(), secondHost = window()
  let first = ControllerFixture(), second = ControllerFixture()
  firstHost.contentView!.addSubview(first.oscToolbarView); secondHost.contentView!.addSubview(second.oscToolbarView)
  first.sidebars.visible = [.settings, .plugins]
  first.fsState = .fullscreen(legacy: false, priorWindowedFrame: .zero); first.pipStatus = .intermediate
  second.sidebars.visible = [.playlist]
  first.rebuild(allTypes); second.rebuild(allTypes)
  for type in allTypes {
    let firstExpected: Bool = [.settings, .plugins, .fullScreen, .pip].contains(type)
    let secondExpected = type == .playlist
    check(first.toolbarButton(type).isActive == firstExpected && second.toolbarButton(type).isActive == secondExpected,
          "\(type) reconstructs from each controller's own state")
  }
  let firstPip = first.toolbarButton(.pip).image
  second.notify(Notification(name: .iinaSidebarStatusChanged, object: first, userInfo: ["enable": true]))
  check(!second.toolbarButton(.pip).isActive && !second.toolbarButton(.settings).isActive && second.toolbarButton(.playlist).isActive,
        "foreign notification payload cannot overwrite another window's selected states")
  check(first.toolbarButton(.pip).image === firstPip, "refreshing another window leaves the originating icon untouched")
  first.sidebars.visible = []; first.fsState = .windowed; first.pipStatus = .notInPIP
  first.updateOSCToolbarButtonStates()
  check(allTypes.allSatisfy { !first.toolbarButton($0).isActive }, "closed modes and sidebars synchronously clear selection")
  first.pipStatus = .inPIP
  check(first.toolbarButton(.pip).isActive, "actual PiP property observer updates its own toolbar synchronously")
  first.pipStatus = .notInPIP
  first.fsState.startAnimatingToFullScreen(legacy: false, priorWindowedFrame: .zero)
  check(first.toolbarButton(.fullScreen).isActive, "actual fullscreen observer marks the transition target synchronously")
  first.fsState.finishAnimating(); first.fsState.startAnimatingToWindow()
  check(!first.toolbarButton(.fullScreen).isActive, "actual fullscreen observer clears the exiting transition target")
  first.player.info.state.active = false
  let writes = first.player.mpv.writes
  first.fsState = .fullscreen(legacy: false, priorWindowedFrame: .zero)
  check(first.toolbarButton(.fullScreen).isActive && first.player.mpv.writes == writes,
        "early toolbar refresh preserves the fullscreen observer's retiring-engine guard")
  Preference.liveTextEnabled = true
  first.updateOSCToolbarButtonStates(); second.updateOSCToolbarButtonStates()
  check(first.toolbarButton(.liveText).isActive && second.toolbarButton(.liveText).isActive,
        "shared Live Text preference is reflected independently in both controllers")
  let prior = first.toolbarButton(.liveText)
  hover(prior, entered: true); press(prior, true)
  first.rebuild(allTypes)
  check(first.toolbarButton(.liveText) !== prior && first.toolbarButton(.liveText).isActive &&
        first.toolbarButton(.liveText).layer!.shadowOpacity == 0 &&
        first.toolbarButton(.liveText).layer!.animation(forKey: "toolbarFeedback.shadowOpacity") == nil,
        "toolbar rebuild restores accepted Live Text selection without prior feedback")
  checkOnlyFeedbackAnimations(first.toolbarButton(.liveText), "reconstructed selection")
  Preference.liveTextEnabled = false; Preference.isLiveTextEnabled = false
  first.rebuild(allTypes)
  check(!first.oscToolbarView.views.contains { $0.tag == Preference.ToolBarButton.liveText.rawValue },
        "rebuild excludes unavailable Live Text without leaving a stale button")
  Preference.isLiveTextEnabled = true
  first.oscToolbarView = nil; first.updateOSCToolbarButtonStates()
  check(true, "early per-window state refresh tolerates an unloaded toolbar")
  firstHost.close(); secondHost.close()
}
print("\(checks) OSC toolbar feedback checks passed with native AppKit and production symbols")
