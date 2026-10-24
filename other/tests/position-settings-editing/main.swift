let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let panel = PositionSettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
panel.isReleasedWhenClosed = false
let field = PositionSettingsTextField(frame: NSRect(x: 20, y: 20, width: 100, height: 24))
let formatter = NumberFormatter()
formatter.minimum = 1
formatter.maximum = 100
field.formatter = formatter
field.stringValue = "50"
field.isValid = {
  guard let text = field.currentEditor()?.string, let value = Int(text) else { return false }
  return (1...100).contains(value)
}
panel.contentView!.addSubview(field)
var checks = 0
func check(_ condition: Bool, _ message: String) {
  precondition(condition, message)
  checks += 1
  print("PASS: \(message)")
}
func edit(_ text: String) {
  check(panel.makeFirstResponder(field), "field takes focus")
  field.currentEditor()!.string = text
}
func enter() {
  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
  panel.sendEvent(event)
}
func backgroundClick() {
  panel.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 200, y: 100), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
}
edit("75")
enter()
check(field.currentEditor() == nil && field.integerValue == 75, "Enter commits valid input and ends editing")
for invalid in ["", "abc", "1000", "-1", "99999999999999999999999999"] {
  edit(invalid)
  enter()
  check(field.currentEditor() == nil && field.integerValue == 75, "Enter restores original value for \(invalid)")
}
edit("60")
backgroundClick()
check(field.currentEditor() == nil && field.integerValue == 60, "background click commits valid input")
edit("abc")
backgroundClick()
check(field.currentEditor() == nil && field.integerValue == 60, "background click restores invalid input")
print("Completed \(checks) native editing checks")

let nextField = PositionSettingsTextField(frame: NSRect(x: 140, y: 20, width: 100, height: 24))
panel.contentView!.addSubview(nextField)
edit("80")
check(panel.makeFirstResponder(nextField), "another field takes focus")
check(field.integerValue == 80 && field.currentEditor() == nil, "changing fields commits prior input")
_ = panel.makeFirstResponder(nil)
edit("invalid")
let returnEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
check(panel.performKeyEquivalent(with: returnEvent), "editing consumes default-button Return")
check(field.currentEditor() == nil && field.integerValue == 80, "default-button route restores invalid input and dismisses editor")
print("Completed \(checks) native editing checks including focus transfer and key equivalents")

final class SaveCounter: NSObject {
  var count = 0
  @objc func save(_ sender: Any?) { count += 1 }
}
let counter = SaveCounter()
let saveButton = NSButton(title: "Save", target: counter, action: #selector(SaveCounter.save(_:)))
saveButton.keyEquivalent = "\r"
saveButton.frame = NSRect(x: 280, y: 20, width: 80, height: 24)
panel.contentView!.addSubview(saveButton)
edit("90")
check(panel.performKeyEquivalent(with: returnEvent) && counter.count == 0, "first Return confirms input without saving")
check(panel.performKeyEquivalent(with: returnEvent) && counter.count == 1, "second Return invokes Save after editing ends")
print("Completed \(checks) native editing checks")

for text in ["", "12345", "1234,5", "12345.", "-12345"] {
  check(PositionSettingsNumberFormatter.acceptsInput(text), "length limiter accepts \(text)")
}
for text in ["123456", "12345,6", "-1234,5", "1..2", "abc", String(repeating: "9", count: 100000)] {
  check(!PositionSettingsNumberFormatter.acceptsInput(text), "length limiter rejects excessive digits or signs")
}
let limitedFormatter = PositionSettingsNumberFormatter()
limitedFormatter.isPartialStringValidationEnabled = true
limitedFormatter.numberStyle = .decimal
limitedFormatter.usesGroupingSeparator = false
field.formatter = limitedFormatter
field.normalizedInput = nil
field.isValid = nil
field.stringValue = "12345"
_ = panel.makeFirstResponder(field)
let limitedEditor = field.currentEditor() as! NSTextView
limitedEditor.insertText("6", replacementRange: NSRange(location: 5, length: 0))
check(limitedEditor.string == "12345", "native editor rejects sixth digit")
limitedEditor.insertText("999999999", replacementRange: NSRange(location: 0, length: 5))
check(limitedEditor.string == "12345", "native editor rejects oversized replacement without truncation")
limitedEditor.insertText("42", replacementRange: NSRange(location: 0, length: 5))
check(limitedEditor.string == "42", "native editor accepts valid replacement")
_ = panel.makeFirstResponder(nil)
print("Completed \(checks) native editing and length checks")
