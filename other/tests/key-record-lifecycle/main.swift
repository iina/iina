import Cocoa

extension Notification.Name {
  static let iinaKeyBindingInputChanged = Self("key-record-lifecycle.input-changed")
}
protocol KeyRecordViewDelegate: AnyObject {
  func keyRecordView(_ view: KeyRecordView, recordedKeyDownWith event: NSEvent)
}
class KeyRecordView: NSView { weak var delegate: KeyRecordViewDelegate? }
enum KeyBindingDataLoader {
  static func load() -> [Criterion] { [TextCriterion(name: "ignore", localizedName: "Ignore")] }
}
enum KeyBindingTranslator {
  static var renderRequests = 0
  static func string(fromCriteria criteria: [Criterion]) -> String {
    renderRequests += 1
    return criteria.map(\.mpvCommandValue).joined(separator: " ")
  }
}
enum KeyCodeHelper {
  static func mpvKeyCode(from event: NSEvent) -> String { "F1" }
}

// PRODUCTION_SOURCES

final class EditorFixture: KeyRecordViewController {
  override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let key = KeyRecordView(), label = NSTextField(), action = NSTextField(), rule = NSRuleEditor()
    [key, label, action, rule].forEach { container.addSubview($0) }
    keyRecordView = key
    keyLabel = label
    actionTextField = action
    ruleEditor = rule
    view = container
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  checks += 1
  print("PASS: \(message)")
}
func loadEditor() -> EditorFixture {
  let editor = EditorFixture(nibName: nil, bundle: nil)
  _ = editor.view
  let criterion = TextCriterion(name: "ignore", localizedName: "Ignore")
  editor.ruleEditor.setCriteria([criterion], andDisplayValues: [criterion.displayValue()], forRowAt: 0)
  return editor
}
func notify() { NotificationCenter.default.post(name: .iinaKeyBindingInputChanged, object: nil) }

for index in 1...5 {
  weak var releasedEditor: EditorFixture?
  autoreleasepool {
    let editor = loadEditor()
    releasedEditor = editor
    let before = KeyBindingTranslator.renderRequests
    notify()
    check(KeyBindingTranslator.renderRequests == before + 1 && editor.action == "ignore",
          "editor \(index) receives input changes while open")
  }
  check(releasedEditor == nil, "closing editor \(index) releases its controller")
  let before = KeyBindingTranslator.renderRequests
  notify()
  check(KeyBindingTranslator.renderRequests == before,
        "closed editor \(index) no longer receives global input changes")
}
print("Completed \(checks) key-binding editor observer lifecycle checks.")
