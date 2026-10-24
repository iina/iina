import Cocoa

struct Preference {
  struct Key: Hashable { let rawValue: String; init(_ value: String) { rawValue = value }
    static let userOptions = Key("userOptions")
    static let enableAdvancedSettings = Key("enableAdvancedSettings")
    static let enableLogging = Key("enableLogging")
    static let useMpvOsd = Key("useMpvOsd")
    static let useUserDefinedConfDir = Key("useUserDefinedConfDir")
    static let screenshotFolder = Key("screenshotFolder")
  }
  static var stored: [String: Any] = [:]
  static var writes = 0
  static func value(for key: Key) -> Any? { stored[key.rawValue] }
  static func bool(for key: Key) -> Bool { stored[key.rawValue] as? Bool ?? false }
  static func set(_ value: Any, for key: Key) { stored[key.rawValue] = value; writes += 1 }
}
final class SettingsWindow: NSWindow {
  var testVisible = true
  override var isVisible: Bool { testVisible }
}
enum AppRestart {
  static var requests = 0
  static func confirmSettingsChange(in window: SettingsWindow) { requests += 1 }
}
final class EditingField: NSTextField {
  var editing = false
  let editor = NSTextView()
  override func currentEditor() -> NSText? { editing ? editor : nil }
}
enum Utility {
  static var errors = 0
  static var selectedURL: URL?
  static func showAlert(_ key: String, sheetWindow: NSWindow?) { errors += 1 }
  static func quickOpenPanel(title: String, chooseDir: Bool, sheetWindow: NSWindow?, callback: (URL) -> Void) {
    if let selectedURL { callback(selectedURL) }
  }
}
enum SettingsAccessory {
  class Base: NSObject { let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 180)) }
}
enum SettingsSubList { static let indent: CGFloat = 12 }
struct TestUI { func vStack(_ view: NSView) -> NSStackView { NSStackView(views: [view]) } }
let ui = TestUI()
enum TestInset { case leading(CGFloat), trailing(CGFloat), bottom(CGFloat), top(CGFloat) }
extension NSView {
  @discardableResult func padding(_ values: TestInset...) -> Self { self }
  @discardableResult func size(height: CGFloat) -> Self { self }
}
extension NSImage { static func sf(_ name: String) -> NSImage? { nil } }
extension NSUserInterfaceItemIdentifier {
  static let key = NSUserInterfaceItemIdentifier("Key")
  static let value = NSUserInterfaceItemIdentifier("Value")
}
final class MPVOptionFieldEditor: NSTextView { var pasteHandler: ((String) -> Bool)? }
final class MPVOptionsTableView: NSTableView {
  let optionFieldEditor = MPVOptionFieldEditor()
  var testRow = -1
  var testColumn = -1
  override var editedRow: Int { testRow }
  override var editedColumn: Int { testColumn }
  override func currentEditor() -> NSText? { testRow >= 0 ? optionFieldEditor : nil }
  override func abortEditing() -> Bool { testRow = -1; testColumn = -1; return true }
}
final class MPVOptionTextFieldCell: NSTextFieldCell {}

// NSDraggingInfo is the input boundary; the production drop method runs unchanged.
final class DropInfo: NSObject, NSDraggingInfo {
  let draggingPasteboard = NSPasteboard.withUniqueName()
  var draggingDestinationWindow: NSWindow? { nil }
  var draggingLocation: NSPoint { .zero }
  var draggingSequenceNumber: Int { 1 }
  var draggingSource: Any? { nil }
  var draggingSourceOperationMask: NSDragOperation { .move }
  var draggedImageLocation: NSPoint { .zero }
  var draggedImage: NSImage? { nil }
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 1
  var draggingFormation = NSDraggingFormation.none
  var springLoadingHighlight: NSSpringLoadingHighlight { .none }
  func resetSpringLoading() {}
  func slideDraggedImage(to screenPoint: NSPoint) {}
  override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
  func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
    classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
