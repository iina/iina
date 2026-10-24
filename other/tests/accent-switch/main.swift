import Cocoa
import SwiftUI

// A deterministic custom RGB fixture; no system or personal defaults are changed.
enum AppAccentColor {
  static let color = NSColor(srgbRed: 0.88, green: 0.27, blue: 0.09, alpha: 1)
}

final class BoundValue: NSObject {
  @objc dynamic var enabled = false { didSet { writes += 1 } }
  var writes = 0
}
final class Target: NSObject {
  var actions = 0
  var observedStates: [Int] = []
  var reverts = false
  @objc func changed(_ sender: AccentSwitch) {
    actions += 1
    observedStates.append(sender.state.rawValue)
    if reverts { sender.state = .off }
  }
}

let app = NSApplication.shared
let previousApplication = NSWorkspace.shared.frontmostApplication
app.setActivationPolicy(.regular)
let control = AccentSwitch()
control.controlSize = .regular
control.setAccessibilityLabel("Test accent switch")
let target = Target()
control.target = target
control.action = #selector(Target.changed(_:))
let boundValue = BoundValue()
control.bind(.value, to: boundValue, withKeyPath: "enabled")
let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 80))
control.translatesAutoresizingMaskIntoConstraints = false
container.addSubview(control)
NSLayoutConstraint.activate([
  control.centerXAnchor.constraint(equalTo: container.centerXAnchor),
  control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
])
let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 180, height: 80),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = container
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
var failures: [String] = []
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !value() { failures.append(message) }
}
func capture(_ name: String) -> Int {
  container.layoutSubtreeIfNeeded()
  container.display()
  let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
  container.cacheDisplay(in: container.bounds, to: bitmap)
  if CommandLine.arguments.count > 1 {
    let path = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png")
    try! bitmap.representation(using: .png, properties: [:])!.write(to: path)
  }
  var tintedPixels = 0
  for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
      guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
      if color.alphaComponent > 0.5, color.redComponent > 0.6,
         color.greenComponent < 0.6, color.blueComponent < 0.35 { tintedPixels += 1 }
    }
  }
  print("\(name): state=\(control.state.rawValue) bound=\(boundValue.enabled) tintedPixels=\(tintedPixels) size=\(control.intrinsicContentSize)")
  return tintedPixels
}
func clickHostedSwitch() {
  let location = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
  let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                             timestamp: ProcessInfo.processInfo.systemUptime + 0.05,
                             windowNumber: window.windowNumber, context: nil, eventNumber: 2,
                             clickCount: 1, pressure: 0)!
  app.postEvent(up, atStart: true)
  window.sendEvent(down)
}
var steps: [() -> Void] = [
  {
    check(app.isActive && window.isKeyWindow, "Probe must render active controls")
    check(control.state == .off, "Initial bound value is off")
    check(control.accessibilityRole() == .checkBox, "AX checkbox role")
    check(control.accessibilitySubrole() == .switch, "AX switch subrole")
    check(control.accessibilityChildren()?.isEmpty != false, "No duplicate AX child switch")
    check(control.accessibilityLabel() == "Test accent switch", "AX label is retained")
    let initialWrites = boundValue.writes
    control.performClick(nil)
    check(boundValue.writes == initialWrites + 1, "Click writes the binding once")
    check(control.state == .on && boundValue.enabled, "performClick writes state and value binding")
    check(target.actions == 1 && target.observedStates == [1], "performClick invokes target once, with new state")
  },
  {
    check(capture("perform-click-on") > 100, "performClick updates hosted custom tint")
    boundValue.enabled = false
    check(control.state == .off, "KVO source change updates Cocoa state")
  },
  {
    check(capture("bound-off") == 0, "KVO source change updates hosted state")
    boundValue.enabled = true
  },
  {
    check(capture("bound-on") > 100, "KVO on source change updates hosted state")
    control.state = .off
    check(target.actions == 1, "Programmatic state does not invoke target")
  },
  {
    check(capture("programmatic-off") == 0, "Programmatic state updates hosted state")
    clickHostedSwitch()
  },
  {
    check(control.state == .on && boundValue.enabled, "Hosted pointer click updates Cocoa state and binding")
    check(target.actions == 2, "Hosted pointer click invokes target exactly once")
    check(capture("hosted-click-on") > 100, "Hosted pointer click keeps display synchronized")
    control.isEnabled = false
    control.performClick(nil)
    check(control.state == .on && target.actions == 2, "Disabled performClick is ignored")
    check(!control.accessibilityPerformPress(), "Disabled AX press is ignored")
    check(target.actions == 2, "Disabled AX press does not invoke the target")
    clickHostedSwitch()
  },
  {
    check(control.state == .on && target.actions == 2, "Disabled hosted pointer click is ignored")
    check(!control.isAccessibilityEnabled(), "Disabled state is exposed through AX")
    _ = capture("disabled-on")
    control.isEnabled = true
  },
  {
    let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                              timestamp: ProcessInfo.processInfo.systemUptime,
                              windowNumber: window.windowNumber, context: nil,
                              characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    func nativeFocusableView(in view: NSView) -> NSView? {
      for child in view.subviews {
        if child.acceptsFirstResponder { return child }
        if let match = nativeFocusableView(in: child) { return match }
      }
      return nil
    }
    guard let keyboardControl = nativeFocusableView(in: control) else {
      check(false, "Missing hosted native keyboard control")
      return
    }
    check(!control.acceptsFirstResponder, "Wrapper does not duplicate native keyboard focus")
    check(window.makeFirstResponder(keyboardControl), "Hosted native switch accepts keyboard focus")
    app.postEvent(NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [],
                                  timestamp: key.timestamp + 0.01, windowNumber: window.windowNumber,
                                  context: nil, characters: " ", charactersIgnoringModifiers: " ",
                                  isARepeat: false, keyCode: 49)!, atStart: true)
    window.firstResponder?.keyDown(with: key)
  },
  {
    check(control.state == .off && !boundValue.enabled, "Space key updates state and binding")
    check(target.actions == 3, "Space key invokes target once")
    target.reverts = true
    clickHostedSwitch()
  },
  {
    check(control.state == .off, "Target may synchronously revert the new state")
    check(capture("reverted-off") == 0, "Hosted state follows synchronous reversion")
    check(target.actions == 4, "Reversion does not duplicate target invocation")
    control.animator().state = .on
  },
  {
    check(control.state == .on, "animator state assignment works")
    check(capture("animator-on") > 100, "animator state updates hosted display")
    control.controlSize = .mini
  },
  {
    let mini = control.intrinsicContentSize
    print("mini: \(mini)")
    check(mini.width > 0 && mini.height > 0, "Mini control has a natural size")
    control.controlSize = .small
  },
  {
    _ = capture("small")
    control.unbind(.value)
    control.bind(.value, to: boundValue, withKeyPath: "enabled", options: [
      .valueTransformerName: NSValueTransformerName(rawValue: "NSNegateBoolean")
    ])
    boundValue.enabled = false
  },
  {
    check(control.state == .on, "Inverted binding reads false as on")
    target.reverts = false
    control.performClick(nil)
    check(control.state == .off && boundValue.enabled, "Inverted binding writes transformed value")
    check(target.actions == 5, "Inverted binding invokes target once")
    let actionsBeforeAX = target.actions
    check(control.accessibilityPerformPress(), "AX press is supported")
    check(target.actions == actionsBeforeAX + 1 && control.state == .on, "AX press invokes one action and updates state")

  },
]
var stepIndex = 0
func nextStep() {
  if stepIndex < steps.count {
    steps[stepIndex]()
    stepIndex += 1
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: nextStep)
  } else {
    control.unbind(.value)
    print("\(checks) checks, \(failures.count) failures")
    failures.forEach { print("FAIL: \($0)") }
    window.orderOut(nil)
    previousApplication?.activate(options: [])
    exit(failures.isEmpty ? 0 : 1)
  }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: nextStep)
app.run()
