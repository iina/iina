import Cocoa
import Darwin
setbuf(stdout, nil)

let minimumInitialDragDistance: CGFloat = 3
enum Logger { enum Level { case verbose }; static func isEmitting(_ level: Level) -> Bool { false } }
enum Preference { enum Key { case pauseWhenInactive }; static func bool(for key: Key) -> Bool { false } }
extension NSPoint { func distance(to point: NSPoint) -> CGFloat { hypot(x-point.x, y-point.y) } }
extension NSEvent { func inAnyOf(_ views: [NSView?]) -> Bool { false } }
class MiniPlayerWindowController: NSWindowController {}
class PlayerFixture {
  enum State { case playing, paused }
  class Info { var state = State.paused }
  let info = Info()
  let miniPlayer = MiniPlayerWindowController()
  func pause() { info.state = .paused }
}
class HeaderFixture: NSView {
  var consumeUp = false
  func handleBackgroundMouseEvent(_ event: NSEvent) -> Bool { consumeUp && event.type == .leftMouseUp }
}
class SidebarFixture {
  var resizingSidebarSide: Int?
  var consumeDown = false, consumeUp = false
  func handleMouseDown(_ event: NSEvent, at point: NSPoint) -> Bool { consumeDown || resizingSidebarSide != nil }
  func handleMouseDragged(_ event: NSEvent) -> Bool { resizingSidebarSide != nil }
  func handleMouseUp(_ event: NSEvent) -> Bool {
    if resizingSidebarSide != nil { resizingSidebarSide = nil; return true }
    return consumeUp
  }
  func handlePanelMouseEvent(_ event: NSEvent) -> Bool { consumeUp && event.type == .leftMouseUp }
}
class InteractiveFixture {
  var isActive = false, canDrag = true
  func canDragWindow(at point: NSPoint) -> Bool { canDrag }
}
class OSCFixture { var isDragging = false }
class InputBase: NSWindowController {
  var pluginDown = 0, pluginDrag = 0, clicks = 0
  override func mouseDown(with event: NSEvent) { pluginDown += 1 }
  override func mouseUp(with event: NSEvent) { clicks += 1 }
  func informPluginMouseDragged(with event: NSEvent) { pluginDrag += 1 }
}
class DragWindow: NSWindow {
  var handoffs: [NSEvent] = []
  var onHandoff: (() -> Void)?
  override func performDrag(with event: NSEvent) { handoffs.append(event); onHandoff?() }
}
class MainWindowController: InputBase {
  var mousePosRelatedToWindow: NSPoint?
  var isDragging = false
  var windowDragMouseDownEvent: NSEvent?
  var didDragWindow = false
  var pressedMouseButtons = 1
  struct Fullscreen { var isFullscreen = false }
  var fsState = Fullscreen()
  let interactiveMode = InteractiveFixture()
  let oscFloatingView = OSCFixture()
  let sidebars = SidebarFixture()
  var titleBarView: HeaderFixture? = HeaderFixture()
  var player = PlayerFixture()
  var isPausedDueToInactive = false
  func log(_ text: String, level: Logger.Level) {}
  func workaroundCursorDefect() {}
  func restoreUIFromVideoClick(_ event: NSEvent) -> Bool { false }
  func handleDefaultEscape(with event: NSEvent) -> Bool { false }
  // PRODUCTION_HANDLERS
}
class RoutingBase {
  var windowController: NSWindowController?
  var dispatch: ((NSEvent) -> Void)?
  func sendEvent(_ event: NSEvent) { dispatch?(event) }
}
class RoutingWindow: RoutingBase {
  // PRODUCTION_ROUTING
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ result: @autoclosure () -> Bool, _ label: String) {
  precondition(result(), label); checks += 1; print("PASS: \(label)")
}
struct Gesture {
  let controller: MainWindowController
  let window: DragWindow
  let routing: RoutingWindow
  init() {
    controller = MainWindowController()
    window = DragWindow(contentRect: NSRect(x:100,y:100,width:600,height:340), styleMask: [.borderless], backing:.buffered, defer:false)
    window.isReleasedWhenClosed = false
    controller.window = window
    routing = RoutingWindow(); routing.windowController = controller
    let target = controller
    routing.dispatch = { event in
      switch event.type {
      case .leftMouseDown: target.mouseDown(with:event)
      case .leftMouseDragged: target.mouseDragged(with:event)
      case .leftMouseUp: target.mouseUp(with:event)
      default: break
      }
    }
  }
  func event(_ type: NSEvent.EventType, _ x: CGFloat = 100, _ y: CGFloat = 100, number: Int = 1, clicks: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(with:type, location:NSPoint(x:x,y:y), modifierFlags:[], timestamp:Double(number), windowNumber:window.windowNumber, context:nil, eventNumber:number, clickCount:clicks, pressure:1)!
  }
  func send(_ type: NSEvent.EventType, _ x: CGFloat = 100, _ y: CGFloat = 100, number: Int = 1, clicks: Int = 1) { routing.sendEvent(event(type,x,y,number:number,clicks:clicks)) }
}

let scenario = CommandLine.arguments.dropFirst().first ?? "all"
if scenario == "repeat" || scenario == "all" {
  let g = Gesture()
  g.send(.leftMouseDown)
  g.send(.leftMouseDragged,120,100)
  g.send(.leftMouseDragged,140,100)
  check(g.window.handoffs.count == 1, "one press hands the window to Window Server only once even without mouseUp")
  check(g.window.handoffs[0].type == .leftMouseDown && g.window.handoffs[0].locationInWindow == NSPoint(x:100,y:100), "native drag receives the original mouse-down event")
  check(g.controller.pluginDrag == 2, "continued held-button movement still reaches plugin drag handlers")
  g.send(.leftMouseUp,140,100)
  check(g.controller.clicks == 0, "releasing a window drag does not trigger the click action")
}
if scenario == "released" || scenario == "all" {
  let g = Gesture(); g.send(.leftMouseDown)
  g.controller.pressedMouseButtons = 0
  g.send(.leftMouseDragged,120,100)
  check(g.window.handoffs.isEmpty, "a queued drag cannot start after the physical button was released")
  g.controller.pressedMouseButtons = 1
  g.send(.leftMouseDragged,140,100)
  check(g.window.handoffs.isEmpty, "a released press cannot attach to a later button hold")
  g.send(.leftMouseUp,140,100)
  check(g.controller.clicks == 0, "discarding a released drag does not turn it into a video click")
}
if scenario == "all" {
  let click = Gesture(); click.send(.leftMouseDown); click.send(.leftMouseDragged,102,101); click.send(.leftMouseUp)
  check(click.window.handoffs.isEmpty && click.controller.clicks == 1, "trackpad jitter remains an ordinary click")
  let repeated = Gesture()
  for i in 1...20 { repeated.send(.leftMouseDown,number:i); repeated.send(.leftMouseDragged,120,100,number:i); repeated.send(.leftMouseUp,120,100,number:i) }
  check(repeated.window.handoffs.count == 20 && repeated.controller.clicks == 0, "fresh gestures remain independent across repeated drags")
  let missingUp = Gesture(); missingUp.send(.leftMouseDown); missingUp.send(.leftMouseDragged,120,100)
  missingUp.send(.leftMouseDown,number:2); missingUp.send(.leftMouseUp,number:2)
  check(missingUp.window.handoffs.count == 1 && missingUp.controller.clicks == 1, "a new click works when the preceding native handoff never delivered mouseUp")
  let releasedAfterHandoff = Gesture(); releasedAfterHandoff.send(.leftMouseDown); releasedAfterHandoff.send(.leftMouseDragged,120,100)
  releasedAfterHandoff.controller.pressedMouseButtons = 0
  releasedAfterHandoff.send(.leftMouseDragged,140,100); releasedAfterHandoff.send(.leftMouseUp,140,100)
  check(releasedAfterHandoff.window.handoffs.count == 1 && releasedAfterHandoff.controller.clicks == 0,
        "a delayed movement after release neither restarts native drag nor turns its release into a click")
  let otherWindow = Gesture(); otherWindow.send(.leftMouseDown)
  let unrelated = Gesture()
  otherWindow.controller.mouseDragged(with:unrelated.event(.leftMouseDragged,150,100))
  check(otherWindow.window.handoffs.isEmpty, "another window's event cannot claim the pending press")
  for swallowed in ["control", "sidebar", "header"] {
    let g = Gesture(); g.send(.leftMouseDown)
    if swallowed == "control" { g.routing.dispatch = { _ in } }
    if swallowed == "sidebar" { g.controller.sidebars.consumeUp = true }
    if swallowed == "header" { g.controller.titleBarView!.consumeUp = true }
    g.send(.leftMouseUp)
    g.controller.sidebars.consumeUp = false; g.controller.titleBarView!.consumeUp = false
    g.controller.mouseDragged(with:g.event(.leftMouseDragged,130,100))
    check(g.window.handoffs.isEmpty, "\(swallowed)-consumed mouseUp cancels pending window drag")
  }
  let focus = Gesture(); focus.send(.leftMouseDown)
  focus.controller.windowDidResignKey(Notification(name:NSWindow.didResignKeyNotification))
  focus.send(.leftMouseDragged,130,100)
  check(focus.window.handoffs.isEmpty, "focus loss cancels a pending press before another drag callback")
  let orphan = Gesture(); orphan.send(.leftMouseDragged,130,100)
  check(orphan.window.handoffs.isEmpty, "movement without a matching press cannot start a window drag")
  let full = Gesture(); full.controller.fsState.isFullscreen = true; full.send(.leftMouseDown); full.send(.leftMouseDragged,130,100)
  check(full.window.handoffs.isEmpty, "fullscreen video does not begin window dragging")
  let osc = Gesture(); osc.controller.oscFloatingView.isDragging = true; osc.send(.leftMouseDown); osc.send(.leftMouseDragged,130,100)
  check(osc.window.handoffs.isEmpty, "floating OSC drag cannot start a native window drag")
  let sidebar = Gesture(); sidebar.controller.sidebars.resizingSidebarSide = 1; sidebar.send(.leftMouseDown); sidebar.send(.leftMouseDragged,130,100); sidebar.send(.leftMouseUp,130,100)
  check(sidebar.window.handoffs.isEmpty && sidebar.controller.sidebars.resizingSidebarSide == nil, "sidebar resizing retains its own release path")
  let editor = Gesture(); editor.controller.interactiveMode.isActive = true; editor.send(.leftMouseDown)
  check(editor.window.handoffs.count == 1 && editor.window.handoffs[0].type == .leftMouseDown, "editor background can hand off its original press immediately")
  let editorReleased = Gesture(); editorReleased.controller.interactiveMode.isActive = true; editorReleased.controller.pressedMouseButtons = 0; editorReleased.send(.leftMouseDown)
  check(editorReleased.window.handoffs.isEmpty, "an already released editor press cannot start native dragging")
  let crop = Gesture(); crop.controller.interactiveMode.isActive = true; crop.controller.interactiveMode.canDrag = false; crop.send(.leftMouseDown)
  check(crop.window.handoffs.isEmpty, "crop selection and controls retain their interaction ownership")
  let right = Gesture(); right.send(.leftMouseDown); right.controller.pressedMouseButtons = 2; right.send(.leftMouseDragged,130,100)
  check(right.window.handoffs.isEmpty, "a right-button hold cannot authorize a stale left-button drag")
}
print("Completed \(checks) window drag lifecycle checks.")
