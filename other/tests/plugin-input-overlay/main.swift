import AppKit
import JavaScriptCore

final class PluginFixture {
  let input = PluginInputManager()
}

final class PlayerCore {
  var plugins: [PluginFixture] = []
}

enum Utility {
  static func quickConstraints(_ formats: [String], _ views: [String: NSView]) {
    for format in formats {
      NSLayoutConstraint.activate(NSLayoutConstraint.constraints(
        withVisualFormat: format, options: [], metrics: nil, views: views))
    }
  }
}

// PRODUCTION_CONTAINER

final class MainWindowController {
  let window: NSWindow?
  let bufferIndicatorView = NSView()

  init() {
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                      styleMask: .borderless, backing: .buffered, defer: false)
    window!.contentView!.addSubview(bufferIndicatorView)
  }

  // PRODUCTION_FACTORY
}

@objc protocol RegistrarExport: JSExport {
  func register(_ input: String, _ callback: JSValue)
}

final class Registrar: NSObject, RegistrarExport {
  let manager: PluginInputManager
  init(_ manager: PluginInputManager) { self.manager = manager }

  func register(_ input: String, _ callback: JSValue) {
    manager.addListener(forInput: input, event: .keyUp, callback: callback,
                        priority: 200, owner: self)
  }
}

final class OverlayFixture: NSView {
  var clickable = false
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard clickable, NSRect(x: 400, y: 250, width: 100, height: 100).contains(point) else {
      return nil
    }
    return super.hitTest(point)
  }
}

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { failures += 1; print("FAIL: \(message)") }
}

if CommandLine.arguments.contains("--expired-listener") {
  let managed: JSManagedValue = autoreleasepool {
    let context = JSContext()!
    return JSManagedValue(value: context.evaluateScript("(function () { return true; })"))!
  }
  check(managed.value == nil, "expired callback fixture released its JavaScript context")
  check(PluginInputManager.Listener(callback: managed, priority: .high).call(withArgs: []) == nil,
        "expired callback is ignored")
  print("\(checks) expired-callback checks; \(failures) failures")
  exit(failures == 0 ? 0 : 1)
}

let context = JSContext()!
let plugin = PluginFixture()
let registrar = Registrar(plugin.input)
context.setObject(registrar, forKeyedSubscript: "input" as NSString)
context.evaluateScript("var calls = 0; input.register('SPACE', function () { calls += 1; return true; });")
check(plugin.input.listener(forInput: "SPACE", event: .keyUp) != nil, "registered callback is stored")
check(plugin.input.listener(forInput: "SPACE", event: .keyUp)?.call(withArgs: [])?.toBool() == true,
      "registered callback can consume an event")
check(context.objectForKeyedSubscript("calls")!.toInt32() == 1, "registered callback runs once")
context.evaluateScript("input.register('SPACE', null);")
check(plugin.input.listener(forInput: "SPACE", event: .keyUp) == nil, "null unregisters the callback")
check(plugin.input.listeners["SPACE"] == nil, "unregister removes an empty input bucket")

let player = PlayerCore()
player.plugins = [plugin]
var defaultCalls = 0
PluginInputManager.handle(input: "SPACE", event: .keyUp, player: player, arguments: [],
                          defaultHandler: { defaultCalls += 1 })
check(defaultCalls == 1, "unregistered callback does not consume normal input")
check(context.objectForKeyedSubscript("calls")!.toInt32() == 1, "unregistered callback is never called")

context.evaluateScript("input.register('SPACE', function () { calls += 10; return false; });")
context.evaluateScript("input.register('SPACE', function () { calls += 100; return false; });")
plugin.input.callListener(forInput: "SPACE", event: .keyUp, withArgs: [])
check(context.objectForKeyedSubscript("calls")!.toInt32() == 101, "replacement invokes only the latest callback")
context.evaluateScript("input.register('SPACE', undefined);")
check(plugin.input.listener(forInput: "SPACE", event: .keyUp) == nil, "undefined unregisters the callback")
context.evaluateScript("input.register('SPACE', function () { return false; });")
context.evaluateScript("input.register('SPACE', 42);")
check(plugin.input.listener(forInput: "SPACE", event: .keyUp) == nil, "invalid replacement removes the previous callback")

autoreleasepool {
  _ = context.evaluateScript("input.register('SPACE', function () { return true; });")
}
JSGarbageCollect(context.jsGlobalContextRef)
autoreleasepool {
  check(plugin.input.listener(forInput: "SPACE", event: .keyUp)?.call(withArgs: [])?.toBool() == true,
        "active callback survives JavaScript garbage collection")
}
autoreleasepool {
  _ = context.evaluateScript("input.register('SPACE', function () { return false; });")
}
JSGarbageCollect(context.jsGlobalContextRef)
check(plugin.input.listener(forInput: "SPACE", event: .keyUp)?.call(withArgs: [])?.toBool() == false,
      "replacement callback remains active after garbage collection")
var repeatedDefaults = 0
for _ in 0..<50 {
  autoreleasepool {
    context.evaluateScript("input.register('SPACE', function () { throw new Error('stale callback'); });")
    context.evaluateScript("input.register('SPACE', null);")
  }
  JSGarbageCollect(context.jsGlobalContextRef)
  PluginInputManager.handle(input: "SPACE", event: .keyUp, player: player, arguments: [],
                            defaultHandler: { repeatedDefaults += 1 })
}
check(repeatedDefaults == 50 && context.exception == nil,
      "50 register/unregister/collect/input cycles preserve default handling")

_ = NSApplication.shared
let controller = MainWindowController()
let root = controller.window!.contentView!
let button = NSButton(frame: NSRect(x: 100, y: 30, width: 100, height: 50))
root.addSubview(button, positioned: .below, relativeTo: controller.bufferIndicatorView)
let container = controller.pluginOverlayViewContainer!
root.layoutSubtreeIfNeeded()
let buttonPoint = NSPoint(x: 150, y: 55)
check(root.hitTest(buttonPoint) === button, "empty plugin container passes clicks to OSC")
let overlay = OverlayFixture(frame: container.bounds)
container.addSubview(overlay)
check(root.hitTest(buttonPoint) === button, "nonclickable plugin overlay passes clicks to OSC")
overlay.clickable = true
check(root.hitTest(buttonPoint) === button, "transparent overlay region passes clicks to OSC")
check(root.hitTest(NSPoint(x: 450, y: 300)) === overlay, "interactive overlay region still receives clicks")
overlay.isHidden = true
check(root.hitTest(buttonPoint) === button, "hidden plugin overlay passes clicks to OSC")
check(container.hitTest(NSPoint(x: -10, y: -10)) == nil, "container rejects points outside its bounds")

print("\(checks) plugin input/overlay checks; \(failures) failures")
exit(failures == 0 ? 0 : 1)
