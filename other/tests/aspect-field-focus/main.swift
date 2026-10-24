extension AspectRatioView {
  var testedField: SidebarInputField { input as! SidebarInputField }
}
extension SidebarInputField {
  var hasFocusMonitor: Bool { inputFocusMonitor != nil }
  @discardableResult func checkClick(_ event: NSEvent) -> NSEvent? { routeInputFocus(for: event) }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let player = PlayerCore()
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
fileprivate let view = AspectRatioView(player: player)
window.contentView!.addSubview(view)
view.frame = window.contentView!.bounds
view.scrollView.frame = view.bounds
view.scrollView.documentView!.frame = view.bounds
let field = view.testedField
field.frame = NSRect(x: 240, y: 40, width: 40, height: 24)
var checks = 0
func check(_ condition: Bool, _ message: String) {
  precondition(condition, message)
  checks += 1
  print("PASS: \(message)")
}
func click(_ point: NSPoint, in targetWindow: NSWindow = window) -> NSEvent {
  NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: targetWindow.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
}
func focusField() {
  check(window.makeFirstResponder(field) && field.currentEditor() != nil,
        "native field editor accepts focus")
}
check(field.focusRingType == .exterior, "aspect input keeps its native exterior focus ring")
check(field.hasFocusMonitor, "attaching the view installs outside-click routing")
focusField()
let inside = field.convert(NSPoint(x: 10, y: 10), to: nil)
field.checkClick(click(inside))
check(field.currentEditor() != nil, "click inside the input preserves editing")
let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                           styleMask: [.titled], backing: .buffered, defer: false)
otherWindow.isReleasedWhenClosed = false
field.checkClick(click(NSPoint(x: 5, y: 5), in: otherWindow))
check(field.currentEditor() != nil, "click in a different window leaves this editor alone")
field.checkClick(click(NSPoint(x: 5, y: 5)))
check(field.currentEditor() == nil && window.firstResponder === window,
      "outside label/background click ends editing and returns focus to the window")
let nextField = NSTextField(frame: NSRect(x: 10, y: 100, width: 50, height: 24))
window.contentView!.addSubview(nextField)
focusField()
field.checkClick(click(NSPoint(x: 20, y: 110)))
check(window.makeFirstResponder(nextField) && nextField.currentEditor() != nil,
      "outside click still allows another input to take focus")
window.makeFirstResponder(nil)
view.removeFromSuperview()
check(!field.hasFocusMonitor, "detaching the view removes its event monitor")
window.contentView!.addSubview(view)
check(field.hasFocusMonitor, "reattaching restores one active monitor")
focusField()
field.checkClick(click(NSPoint(x: 5, y: 5)))
check(field.currentEditor() == nil, "outside dismissal works after reattachment")
focusField()
field.currentEditor()!.string = "2.35:1"
window.makeFirstResponder(nil)
check(player.info.unsureAspect == "2.35:1", "custom aspect commits on native focus loss")
focusField()
field.currentEditor()!.string = ""
window.makeFirstResponder(nil)
check(player.info.unsureAspect == "Default" && field.stringValue.isEmpty,
      "empty aspect restores Default and leaves the custom field empty")
focusField()
field.currentEditor()!.string = "1.85:1"
(field.currentEditor() as! NSTextView).insertNewline(nil)
check(player.info.unsureAspect == "1.85:1", "custom aspect commits on native Enter")
focusField()
field.currentEditor()!.string = ""
(field.currentEditor() as! NSTextView).insertNewline(nil)
check(player.info.unsureAspect == "Default", "empty aspect Enter restores Default")
view.removeFromSuperview()
print("Completed \(checks) production-view focus checks; native responder state, synthetic events and unrelated player/layout stubs.")
