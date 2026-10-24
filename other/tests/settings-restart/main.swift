import Cocoa

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
  checks += 1
  guard value() else { fatalError(label) }
}
func flush() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)) }
NSApplication.shared.setActivationPolicy(.prohibited)
let suite = "org.iina.tests.settings-restart.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let valueKey = Preference.Key("value")
let extraKey = Preference.Key("extra")
defaults.set("initial", forKey: valueKey.rawValue)
defaults.set("path", forKey: extraKey.rawValue)
let window = SettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 500, height: 400),
  styleMask: .titled, backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let row = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
let field = EditingField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
row.addSubview(field)
window.contentView!.addSubview(row)
var allowed = true
var extraActive = true
var observer: SettingsRestartChangeObserver? = SettingsRestartChangeObserver(
  keys: [valueKey, extraKey], view: row, defaults: defaults) { key in allowed && (key != extraKey || extraActive) }
flush(); check(AppRestart.requests == 0, "no initial prompt")
defaults.set("initial", forKey: valueKey.rawValue); flush()
check(AppRestart.requests == 0, "equal persisted value ignored")
defaults.set("changed", forKey: valueKey.rawValue); flush()
check(AppRestart.requests == 1, "committed value prompts once")
defaults.set("changed", forKey: valueKey.rawValue); flush()
check(AppRestart.requests == 1, "duplicate callback ignored")
defaults.set("temporary", forKey: valueKey.rawValue)
defaults.set("changed", forKey: valueKey.rawValue); flush()
check(AppRestart.requests == 1, "coalesced net no-op ignored")
row.removeFromSuperview(); defaults.set("offpage", forKey: valueKey.rawValue); flush()
window.contentView!.addSubview(row); flush()
check(AppRestart.requests == 1, "off-page changes never prompt later")
row.isHidden = true; defaults.set("hidden", forKey: valueKey.rawValue); flush(); row.isHidden = false
check(AppRestart.requests == 1, "hidden row change ignored")
field.isEnabled = false; defaults.set("disabled", forKey: valueKey.rawValue); flush(); field.isEnabled = true
check(AppRestart.requests == 1, "disabled row change ignored")
allowed = false; defaults.set("inactive", forKey: valueKey.rawValue); flush(); allowed = true
check(AppRestart.requests == 1, "inactive Advanced gate ignored")
extraActive = false; defaults.set("newpath", forKey: extraKey.rawValue); flush()
check(AppRestart.requests == 1, "inactive config path ignored")
defaults.set("primary-off", forKey: valueKey.rawValue); flush()
check(AppRestart.requests == 2, "master OFF still prompts independent of path gate")
field.editing = true
defaults.set("one keystroke", forKey: valueKey.rawValue); flush()
defaults.set("complete edit", forKey: valueKey.rawValue); flush()
check(AppRestart.requests == 2, "continuous field edits defer")
field.editing = false
NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: field); flush()
check(AppRestart.requests == 3, "field commit emits once")
NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: field); flush()
check(AppRestart.requests == 3, "duplicate end editing ignored")
field.editing = true; defaults.set("cancelled", forKey: valueKey.rawValue); flush()
defaults.set("complete edit", forKey: valueKey.rawValue); field.editing = false
NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: field); flush()
check(AppRestart.requests == 3, "cancelled net edit ignored")
let done = DispatchSemaphore(value: 0)
DispatchQueue.global().async { defaults.set("background", forKey: valueKey.rawValue); done.signal() }
check(done.wait(timeout: .now() + 3) == .success, "background write completed")
flush(); check(AppRestart.requests == 3, "background writes never prompt")
field.editing = true
NotificationCenter.default.post(name: NSControl.textDidBeginEditingNotification, object: field)
defaults.set("committed by navigation", forKey: valueKey.rawValue)
field.editing = false
NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: field)
row.removeFromSuperview(); flush()
check(AppRestart.requests == 4, "actual edit committed by page navigation retains initiating Settings window")
defaults.set("unrelated after navigation", forKey: valueKey.rawValue); flush()
check(AppRestart.requests == 4, "navigation context consumed once; unrelated off-page write ignored")
window.contentView!.addSubview(row)
observer = nil; defaults.set("after disposal", forKey: valueKey.rawValue); flush()
check(AppRestart.requests == 4, "observer removed safely")

// Real AppKit editor/binding: native Return commits while retaining its editor.
let nativeRow = NSView(frame: NSRect(x: 0, y: 100, width: 350, height: 70))
let nativeField = NSTextField(frame: NSRect(x: 10, y: 10, width: 300, height: 24))
nativeRow.addSubview(nativeField)
window.contentView!.addSubview(nativeRow)
let nativeKey = Preference.Key("nativeProxy")
defaults.set("", forKey: nativeKey.rawValue)
nativeField.bind(.value, to: defaults, withKeyPath: nativeKey.rawValue)
let nativeObserver = SettingsRestartChangeObserver(keys: [nativeKey], view: nativeRow, defaults: defaults)
let beforeNativeReturn = AppRestart.requests
nativeField.selectText(nil)
check(nativeField.currentEditor() is NSTextView, "native field editor created without activation")
let nativeEditor = nativeField.currentEditor() as! NSTextView
nativeEditor.insertText("127.0.0.1:9", replacementRange: NSRange(location: 0, length: nativeEditor.string.utf16.count))
flush()
check(defaults.string(forKey: nativeKey.rawValue) == "", "native noncontinuous binding defers saving while typing")
check(AppRestart.requests == beforeNativeReturn, "native typing remains deferred")
nativeEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
flush()
check(defaults.string(forKey: nativeKey.rawValue) == "127.0.0.1:9", "native Return persisted exact proxy")
check(nativeField.currentEditor() != nil, "AppKit retains editor after native Return")
check(AppRestart.requests == beforeNativeReturn + 1, "native Return prompts despite retained editor")
(nativeField.currentEditor() as? NSTextView)?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
flush()
check(AppRestart.requests == beforeNativeReturn + 1, "unchanged repeated Return is a no-op")
// Preserve Tab/cancellation behavior even when a field editor remains attached.
field.editing = true
let tabObserver = SettingsRestartChangeObserver(keys: [valueKey], view: row, defaults: defaults)
defaults.set("Tab draft", forKey: valueKey.rawValue)
NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: field,
                               userInfo: ["NSTextMovement": NSTextMovement.tab.rawValue])
flush()
check(AppRestart.requests == beforeNativeReturn + 1, "Tab with active row editor remains deferred")
defaults.set("after disposal", forKey: valueKey.rawValue)
NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: field,
                               userInfo: ["NSTextMovement": NSTextMovement.return.rawValue])
flush()
check(AppRestart.requests == beforeNativeReturn + 1, "Return after reverting edit remains a no-op")
field.editing = false
withExtendedLifetime((nativeObserver, tabObserver)) {}

// The real FileChooserView is extracted unchanged; only the panel result is injected.
let configKey = Preference.Key("testConfigDirectory")
Utility.selectedURL = URL(fileURLWithPath: "/chosen/config")
Preference.stored[Preference.Key.screenshotFolder.rawValue] = "/screenshots"
let chooser = FileChooserView(configKey)
chooser.chooseFolder(NSObject())
check(Preference.stored[configKey.rawValue] as? String == "/chosen/config", "config chooser writes requested key")
check(Preference.stored[Preference.Key.screenshotFolder.rawValue] as? String == "/screenshots", "config chooser preserves screenshot folder")
let screenshotChooser = FileChooserView(.screenshotFolder)
screenshotChooser.chooseFolder(NSObject())
check(Preference.stored[Preference.Key.screenshotFolder.rawValue] as? String == "/chosen/config", "screenshot chooser still writes screenshot key")

// The actual chooser must yield to the main title in a constrained Settings row.
let pathRow = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 44))
pathRow.translatesAutoresizingMaskIntoConstraints = false
window.contentView!.addSubview(pathRow)
let pathTitle = NSTextField(labelWithString: "Use config directory")
pathTitle.translatesAutoresizingMaskIntoConstraints = false
pathTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
pathTitle.lineBreakMode = .byWordWrapping
let pathValues = NSStackView(views: [chooser.textField, chooser.chooseButton, NSSwitch()])
pathValues.translatesAutoresizingMaskIntoConstraints = false
pathValues.orientation = .horizontal
pathValues.alignment = .centerY
chooser.textField.translatesAutoresizingMaskIntoConstraints = false
pathRow.addSubview(pathTitle)
pathRow.addSubview(pathValues)
NSLayoutConstraint.activate([
  pathRow.widthAnchor.constraint(equalToConstant: 400),
  pathRow.heightAnchor.constraint(equalToConstant: 44),
  pathTitle.leadingAnchor.constraint(equalTo: pathRow.leadingAnchor, constant: 36),
  pathTitle.centerYAnchor.constraint(equalTo: pathRow.centerYAnchor),
  pathTitle.trailingAnchor.constraint(lessThanOrEqualTo: pathValues.leadingAnchor, constant: -8),
  pathValues.trailingAnchor.constraint(equalTo: pathRow.trailingAnchor, constant: -8),
  pathValues.centerYAnchor.constraint(equalTo: pathRow.centerYAnchor)
])
chooser.textField.stringValue = "/tmp/config"
pathRow.layoutSubtreeIfNeeded()
let shortPathFittingWidth = pathRow.fittingSize.width
let pathTitleWidth = pathTitle.intrinsicContentSize.width
let longPath = "/Users/test/" + String(repeating: "long-config-directory/", count: 20) + "mpv"
chooser.textField.stringValue = longPath
pathRow.layoutSubtreeIfNeeded()
print("path layout: \(chooser.textField.frame), title: \(pathTitle.frame), fitting: \(pathRow.fittingSize)")
check(chooser.textField.usesSingleLineMode && chooser.textField.maximumNumberOfLines == 1,
      "long chooser path stays single line")
check(chooser.textField.lineBreakMode == .byTruncatingMiddle, "chooser preserves path ends with middle truncation")
check(chooser.textField.frame.width <= 200.5, "long chooser path width remains bounded")
check(pathTitle.frame.width >= pathTitleWidth - 0.5, "long path yields before compressing row title")
check(pathRow.fittingSize.width <= shortPathFittingWidth + 0.5, "long path does not grow Settings row fitting width")
check(chooser.textField.stringValue == longPath, "truncation preserves complete saved path")

for master in [false, true] {
  Preference.stored = ["enableAdvancedSettings": master, "userOptions": [[String]]()]
  check(!hasAdvancedStartupEffect(), "Advanced master with no active feature has no restart effect")
  for feature in ["enableLogging", "useMpvOsd", "useUserDefinedConfDir"] {
    Preference.stored[feature] = true
    check(hasAdvancedStartupEffect(), "Advanced gate \(master) affects configured \(feature)")
    Preference.stored[feature] = false
  }
  Preference.stored["userOptions"] = [["profile", "fast"]]
  check(hasAdvancedStartupEffect(), "Advanced gate \(master) affects configured options")
}

Preference.stored = ["enableAdvancedSettings": true, "userOptions": [["profile", "fast"], ["cache", "yes"]]]
let editor = MPVOptionsEditor()
window.contentView!.addSubview(editor.view)
let initialRequests = AppRestart.requests
let initialWrites = Preference.writes
flush(); check(AppRestart.requests == initialRequests, "editor initialization ignored")
editor.addOptionAction(NSObject()); flush()
check(Preference.writes == initialWrites && AppRestart.requests == initialRequests, "placeholder Add neither saved nor prompted")
editor.removeOptionAction(NSObject()); flush()
check(Preference.writes == initialWrites && AppRestart.requests == initialRequests, "delete draft is no-op")
let keyColumn = editor.tableView.tableColumns[0]
let valueColumn = editor.tableView.tableColumns[1]
editor.tableView.testRow = 0; editor.tableView.testColumn = 0
editor.tableView(editor.tableView, setObjectValue: "profile", for: keyColumn, row: 0)
flush(); check(Preference.writes == initialWrites, "unchanged cell ignored")
editor.tableView(editor.tableView, setObjectValue: "", for: keyColumn, row: 0)
flush(); check(Preference.writes == initialWrites && Utility.errors == 1, "rejected empty edit ignored")
editor.tableView(editor.tableView, setObjectValue: "vo", for: keyColumn, row: 0)
flush(); check(AppRestart.requests == initialRequests, "key edit does not interrupt Tab transaction")
editor.tableView.testColumn = 1
editor.tableView(editor.tableView, setObjectValue: "gpu", for: valueColumn, row: 0)
flush(); check(AppRestart.requests == initialRequests, "value editing remains uninterrupted")
_ = editor.tableView.abortEditing()
editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification)); flush()
check(AppRestart.requests == initialRequests + 1, "completed key/value transaction prompts once")
editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification)); flush()
check(AppRestart.requests == initialRequests + 1, "duplicate editor save ignored")
editor.tableView.testRow = 0; editor.tableView.testColumn = 0
check(editor.tableView.optionFieldEditor.pasteHandler?("invalid") == false, "rejected paste ignored")
check(editor.tableView.optionFieldEditor.pasteHandler?("user-agent=A=B") == true, "complete pasted option accepted")
flush(); check(AppRestart.requests == initialRequests + 2, "meaningful paste prompts once")
check(editor.options[0] == ["user-agent", "A=B"], "paste preserves equals in value")
editor.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
editor.removeOptionAction(NSObject()); flush()
check(AppRestart.requests == initialRequests + 3, "delete saved option prompts")
editor.addOptionAction(NSObject())
editor.tableView.testRow = 1; editor.tableView.testColumn = 0
check(editor.tableView.optionFieldEditor.pasteHandler?("volume=50") == true, "draft paste becomes committed")
flush()
let beforeMove = AppRestart.requests
let drop = DropInfo()
drop.draggingPasteboard.setString("0", forType: NSPasteboard.PasteboardType("com.colliderli.iina.mpv-option-row"))
check(editor.tableView(editor.tableView, acceptDrop: drop, row: 2, dropOperation: .above), "meaningful reorder accepted")
flush(); check(AppRestart.requests == beforeMove + 1, "reorder prompts")
check((Preference.value(for: .userOptions) as? [[String]])?.first == ["volume", "50"], "reorder saved correct order")
Preference.stored["enableAdvancedSettings"] = false
editor.tableView(editor.tableView, setObjectValue: "51", for: valueColumn, row: 0); flush()
check(AppRestart.requests == beforeMove + 1, "inactive Advanced editor save has no restart request")
Preference.stored["enableAdvancedSettings"] = true
editor.tableView(editor.tableView, setObjectValue: "52", for: valueColumn, row: 0)
editor.view.removeFromSuperview(); flush()
check(AppRestart.requests == beforeMove + 2, "actual MPV option commit survives page navigation")
check(!NSApp.isActive, "native test never activated")
print("\(checks) settings restart hook/editor checks passed")
