import Cocoa

final class SettingsWindow: NSWindow {
  static let `default` = SettingsWindow()
  var navigationSaves = 0
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
  init() {
    super.init(contentRect: NSRect(x: -20000, y: -20000, width: 600, height: 400),
               styleMask: [.titled, .closable], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
  }
  func saveNavigationLocation() { navigationSaves += 1 }
}
enum AppRestartSession {
  static let preferenceKey = "playerSessionAfterSettingsRestart"
  static func capture(defaults: UserDefaults) { fatalError("Presenter must not capture media") }
}
enum Probe {
  static var restartRequests: [SettingsWindow] = []
  static var failRestart = false
}
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func waitUntil(_ message: String, timeout: TimeInterval = 2, _ predicate: () -> Bool) {
  let deadline = Date(timeIntervalSinceNow: timeout)
  while !predicate() && Date() < deadline {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
  }
  expect(predicate(), message)
}
func drain() {
  let deadline = Date(timeIntervalSinceNow: 0.08)
  while Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005)) }
}
func buttons(in view: NSView) -> [NSButton] {
  (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
}
func key(_ character: String, in sheet: NSWindow) {
  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: sheet.windowNumber, context: nil, characters: character,
    charactersIgnoringModifiers: character, isARepeat: false, keyCode: character == "\r" ? 36 : 53)!
  expect(sheet.performKeyEquivalent(with: event), "native Return/Escape key equivalent handled")
}
func restartSheet(_ window: SettingsWindow) -> NSWindow {
  waitUntil("restart sheet appears") { window.attachedSheet != nil }
  return window.attachedSheet!
}
func clearRequests() { AppRestart.discardRestoreRequest() }
func hasNoRestoreKeys() -> Bool {
  ["restoreSettingsAfterRestart", "immediateSettingsRestart", AppRestartSession.preferenceKey]
    .allSatisfy { UserDefaults.standard.object(forKey: $0) == nil }
}
func request(_ window: SettingsWindow, count: Int = 1) {
  for _ in 0..<count { AppRestart.confirmSettingsChange(in: window) }
}
func testPresenter() {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  let window = SettingsWindow.default
  window.appearance = NSAppearance(named: CommandLine.arguments.last == "dark" ? .darkAqua : .aqua)
  window.makeKeyAndOrderFront(nil)
  expect(window.isVisible, "offscreen native Settings fixture visible without activation")
  var sheetBegins = 0
  let token = NotificationCenter.default.addObserver(forName: NSWindow.willBeginSheetNotification,
    object: window, queue: .main) { _ in sheetBegins += 1 }
  defer { NotificationCenter.default.removeObserver(token); window.close() }

  UserDefaults.standard.set(3, forKey: "accentColorSource")
  UserDefaults.standard.set("#A03050", forKey: "customAccentColor")
  request(window, count: 8)
  expect(window.attachedSheet == nil, "commit callback defers presentation to next main-loop turn")
  let first = restartSheet(window)
  expect(sheetBegins == 1, "same-turn commits coalesce to one sheet")
  expect(UserDefaults.standard.integer(forKey: "accentColorSource") == 3 &&
    UserDefaults.standard.string(forKey: "customAccentColor") == "#A03050", "saved choice exists before prompt")
  expect(hasNoRestoreKeys(), "showing modal does not arm any restoration")
  let nativeButtons = buttons(in: first.contentView!)
  expect(nativeButtons.contains { $0.title == "Restart" && $0.keyEquivalent == "\r" }, "Restart has Return key")
  expect(nativeButtons.contains { $0.title == "Later" && $0.keyEquivalent == "\u{1b}" }, "Later has Escape key")
  expect(String(describing: type(of: first.defaultButtonCell!)) == "AccentAlertButtonCell", "native default button uses production accent cell")
  request(window, count: 5)
  drain()
  expect(sheetBegins == 1 && window.attachedSheet === first, "active own modal suppresses duplicate requests")
  UserDefaults.standard.set(true, forKey: "restoreSettingsAfterRestart")
  UserDefaults.standard.set(true, forKey: "immediateSettingsRestart")
  UserDefaults.standard.set(Data([1, 2, 3]), forKey: AppRestartSession.preferenceKey)
  key("\u{1b}", in: first)
  waitUntil("Later closes sheet") { window.attachedSheet == nil }
  drain()
  expect(hasNoRestoreKeys(), "Later clears stale legacy, immediate, and session handoffs")
  expect(Probe.restartRequests.isEmpty && sheetBegins == 1, "Later does not restart or replay duplicates")
  expect(UserDefaults.standard.string(forKey: "customAccentColor") == "#A03050", "Later keeps committed setting")

  request(window)
  let second = restartSheet(window)
  key("\r", in: second)
  waitUntil("Return routes Restart") { Probe.restartRequests.count == 1 }
  waitUntil("Restart modal ends") { window.attachedSheet == nil }
  expect(Probe.restartRequests[0] === window && window.navigationSaves == 1, "Restart preserves requesting Settings window")
  expect(UserDefaults.standard.bool(forKey: "restoreSettingsAfterRestart") &&
    UserDefaults.standard.bool(forKey: "immediateSettingsRestart"), "immediate Restart boundary arms its one-shot handoff")
  clearRequests()

  Probe.failRestart = true
  request(window)
  let failing = restartSheet(window)
  key("\r", in: failing)
  waitUntil("restart failure presents its native error sheet after closing prompt") {
    window.attachedSheet != nil && window.attachedSheet !== failing
  }
  expect(Probe.restartRequests.count == 2 && window.navigationSaves == 1 && hasNoRestoreKeys(),
         "failed restart boundary does not arm restoration")
  let failureSheet = window.attachedSheet!
  window.endSheet(failureSheet, returnCode: .alertFirstButtonReturn)
  waitUntil("native error sheet dismisses") { window.attachedSheet == nil }
  Probe.failRestart = false

  let foreign = NSAlert()
  foreign.messageText = "Existing picker transaction"
  foreign.addButton(withTitle: "Apply")
  foreign.beginSheetModal(for: window)
  let foreignSheet = window.attachedSheet!
  let beforeForeign = sheetBegins
  request(window, count: 4)
  drain()
  expect(window.attachedSheet === foreignSheet && sheetBegins == beforeForeign, "restart request does not overlap another sheet")
  window.endSheet(foreignSheet, returnCode: .alertFirstButtonReturn)
  waitUntil("restart waits for actual foreign sheet end") { window.attachedSheet != nil && window.attachedSheet !== foreignSheet }
  expect(sheetBegins == beforeForeign + 1, "foreign-sheet commits produce exactly one later restart modal")
  key("\u{1b}", in: window.attachedSheet!)
  waitUntil("deferred modal dismisses") { window.attachedSheet == nil }

  let closing = SettingsWindow()
  closing.makeKeyAndOrderFront(nil)
  request(closing)
  closing.close()
  drain()
  expect(closing.attachedSheet == nil && hasNoRestoreKeys(), "closed Settings drops queued presentation without handoff")

  let hidden = SettingsWindow()
  hidden.makeKeyAndOrderFront(nil)
  request(hidden)
  hidden.orderOut(nil)
  drain()
  expect(hidden.attachedSheet == nil && hasNoRestoreKeys(), "hidden Settings drops queued presentation without handoff")
  hidden.makeKeyAndOrderFront(nil)
  drain()
  expect(hidden.attachedSheet == nil, "hidden dropped request never replays on showing Settings")
  hidden.close()

  let closingBehindSheet = SettingsWindow()
  closingBehindSheet.makeKeyAndOrderFront(nil)
  let anotherPicker = NSAlert()
  anotherPicker.messageText = "Closing picker"
  anotherPicker.addButton(withTitle: "Apply")
  anotherPicker.beginSheetModal(for: closingBehindSheet)
  let pickerSheet = closingBehindSheet.attachedSheet!
  request(closingBehindSheet)
  drain()
  closingBehindSheet.close()
  if closingBehindSheet.attachedSheet === pickerSheet {
    closingBehindSheet.endSheet(pickerSheet, returnCode: .alertSecondButtonReturn)
  }
  drain()
  expect(closingBehindSheet.attachedSheet == nil && hasNoRestoreKeys(), "close while waiting for foreign sheet leaves no stale modal")

  let closingOwn = SettingsWindow()
  closingOwn.makeKeyAndOrderFront(nil)
  request(closingOwn)
  _ = restartSheet(closingOwn)
  closingOwn.close()
  drain()
  expect(closingOwn.attachedSheet == nil, "closing Settings dismisses its active restart prompt")
  drain()
  expect(hasNoRestoreKeys(), "closing active prompt does not leave explicit restore intent")
  closingOwn.makeKeyAndOrderFront(nil)
  request(closingOwn)
  let afterClosingOwn = restartSheet(closingOwn)
  key("\u{1b}", in: afterClosingOwn)
  waitUntil("new prompt after closed Settings dismisses") { closingOwn.attachedSheet == nil }
  closingOwn.close()
  expect(!app.isActive, "presenter test application remained inactive")
}

guard let identifier = Bundle.main.bundleIdentifier,
      identifier.hasPrefix("org.iina.tests.settings-restart-presenter.") else { fatalError("Use run.py test bundle") }
UserDefaults.standard.setVolatileDomain(["accentColorSource": 3, "customAccentColor": "#A03050"],
                                       forName: UserDefaults.argumentDomain)
AppAccentColor.configure()
defer { UserDefaults.standard.removePersistentDomain(forName: identifier) }
testPresenter()
print("\(checks) native settings-restart presenter checks passed")
