final class Recorder: NSObject {
  var values: [String] = []
  @objc func commit(_ sender: NSTextField) { values.append(sender.stringValue) }
}
extension SidebarInputField {
  func routeTestClick(_ event: NSEvent) -> NSEvent? { routeInputFocus(for: event) }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let destination = NSTextField(frame: NSRect(x: 100, y: 40, width: 60, height: 24))
window.contentView!.addSubview(destination)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  checks += 1
  print("PASS: \(message)")
}
func drainFocusSelection() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }

for name in ["Speed", "Audio Delay", "Primary Subtitle Delay", "Secondary Subtitle Delay", "Color"] {
  let field = SidebarInputField(frame: NSRect(x: 10, y: 40, width: 70, height: 24))
  let recorder = Recorder()
  field.target = recorder
  field.action = #selector(Recorder.commit(_:))
  field.emptyValue = name == "Speed" ? "1" : "0"
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.allowsFloats = name != "Color"
  if name == "Speed" { formatter.minimum = 0.01 }
  field.formatter = formatter
  window.contentView!.addSubview(field)
  field.stringValue = "123"
  check(window.makeFirstResponder(field), "\(name) accepts native focus")
  drainFocusSelection()
  var editor = field.currentEditor() as! NSTextView
  check(editor.selectedRange == NSRange(location: 0, length: 3), "\(name) selects the entire value on entry")
  editor.insertText("42", replacementRange: editor.selectedRange)
  check(editor.string == "42", "\(name) typing immediately replaces the selected value")
  editor.insertNewline(nil)
  check(recorder.values == ["42"], "\(name) Enter commits once")

  window.makeFirstResponder(field)
  editor = field.currentEditor() as! NSTextView
  editor.string = ""
  editor.insertNewline(nil)
  check(recorder.values.last == field.emptyValue && field.stringValue == field.emptyValue,
        "\(name) empty Enter resets to its default through the formatter")

  window.makeFirstResponder(field)
  editor = field.currentEditor() as! NSTextView
  editor.string = "29"
  let beforeBlur = recorder.values.count
  window.makeFirstResponder(destination)
  check(recorder.values.count == beforeBlur + 1 && recorder.values.last == "29",
        "\(name) focus loss commits once and transfers focus")

  window.makeFirstResponder(field)
  field.currentEditor()!.string = ""
  window.makeFirstResponder(destination)
  check(recorder.values.last == field.emptyValue && field.stringValue == field.emptyValue,
        "\(name) empty focus loss resets to its default")

  window.makeFirstResponder(field)
  field.currentEditor()!.string = "   "
  window.makeFirstResponder(destination)
  check(recorder.values.last == field.emptyValue && field.currentEditor() == nil,
        "\(name) whitespace reset does not trap keyboard focus")

  window.makeFirstResponder(field)
  field.currentEditor()!.string = "31"
  field.nextKeyView = destination
  (field.currentEditor() as! NSTextView).insertTab(nil)
  check(recorder.values.last == "31" && destination.currentEditor() != nil,
        "\(name) Tab commits and advances to the next field")

  window.makeFirstResponder(field)
  field.currentEditor()!.string = "123"
  let location = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                             context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
  let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                               timestamp: up.timestamp, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
  NSApp.postEvent(up, atStart: true)
  field.mouseDown(with: down)
  check((field.currentEditor() as! NSTextView).selectedRange == NSRange(location: 0, length: 3),
        "\(name) control mouseDown selects the whole value")
  (field.currentEditor() as! NSTextView).setSelectedRange(NSRange(location: 1, length: 0))
  check(field.routeTestClick(down) == nil && (field.currentEditor() as! NSTextView).selectedRange == NSRange(location: 0, length: 3),
        "\(name) a click on the active field editor selects all without placing the caret again")
  window.makeFirstResponder(nil)
  field.removeFromSuperview()
}
window.close()
print("Completed \(checks) native field editor lifecycle checks using the production SidebarInputField.")
