import Cocoa
import JavaScriptCore
@preconcurrency import WebKit

private var checks = 0
final class WeakBox<T: AnyObject> {
  weak var value: T?
  init(_ value: T?) { self.value = value }
}
final class BackgroundResult: @unchecked Sendable {
  private let lock = NSLock()
  private var result = false
  func set(_ value: Bool) { lock.lock(); result = value; lock.unlock() }
  func get() -> Bool { lock.lock(); defer { lock.unlock() }; return result }
}
func check(_ value: Bool, _ message: String) {
  checks += 1
  precondition(value, "FAIL: \(message)")
}
func setHighlight(_ hex: String, defaults: UserDefaults) {
  let value = UInt32(hex.dropFirst(), radix: 16)!
  let components = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)]
  let raw = components.map { String($0 / 255) }.joined(separator: " ") + " Other"
  defaults.setVolatileDomain(["AppleHighlightColor": raw], forName: UserDefaults.argumentDomain)
  NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
}
func boundedMainWait(_ semaphore: DispatchSemaphore) -> Bool {
  semaphore.wait(timeout: .now() + 1) == .success
}
func settle() async { try? await Task.sleep(nanoseconds: 90_000_000) }

final class NativeFixture {
  private let instance = JavascriptPluginInstance()
  var context: JSContext!
  var api: JavascriptAPIAppearance!
  init() {
    context = JSContext()!
    api = JavascriptAPIAppearance(context: context, pluginInstance: instance)
    context.setObject(["appearance": api!], forKeyedSubscript: "iina" as NSString)
    api.extraSetup()
  }
  @discardableResult func evaluate(_ script: String) -> JSValue? { context.evaluateScript(script) }
  func dispose() {
    api.cleanUp(instance)
    context.setObject(nil, forKeyedSubscript: "iina" as NSString)
    api = nil
    context = nil
  }
}

final class WeakHandler: NSObject, WKScriptMessageHandler {
  weak var owner: WebFixture?
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    owner?.messages.append(message.body)
  }
}
final class WebFixture: NSObject, WKNavigationDelegate {
  var webView: WKWebView!
  var bridge: PluginAppearanceBridge!
  var messages: [Any] = []
  var completion: CheckedContinuation<Void, Error>?
  private let handler = WeakHandler()
  let originalScripts: [WKUserScript]

  override init() {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    let legacy = WKUserScript(source: FixtureScripts.messageBridge, injectionTime: .atDocumentStart,
                              forMainFrameOnly: true)
    let isolated = WKUserScript(source: "window.__isolatedFixture = 17;", injectionTime: .atDocumentStart,
                                forMainFrameOnly: true, in: .defaultClient)
    originalScripts = [legacy, isolated]
    originalScripts.forEach { config.userContentController.addUserScript($0) }
    super.init()
    handler.owner = self
    config.userContentController.add(handler, name: "iina")
    webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
    webView.navigationDelegate = self
    bridge = PluginAppearanceBridge(webView: webView)
  }

  func load(_ html: String) async throws {
    try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      webView.loadHTMLString(html, baseURL: nil)
    }
  }
  func loadFile(_ html: String) async throws {
    let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("author.html")
    try html.write(to: file, atomically: true, encoding: .utf8)
    try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      webView.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
    }
  }
  func reload() async throws {
    try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      webView.reload()
    }
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    bridge.prepareForNavigation()
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    bridge.didFinishNavigation()
    completion?.resume()
    completion = nil
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    completion?.resume(throwing: error)
    completion = nil
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    completion?.resume(throwing: error)
    completion = nil
  }
  func value(_ expression: String) async throws -> Any? { try await webView.evaluateJavaScript(expression) }
  func dispose() {
    bridge.invalidate()
    bridge = nil
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "iina")
    webView.navigationDelegate = nil
    webView = nil
  }
}

let authorHTML = #"""
<!DOCTYPE html><html><head><meta charset="utf-8">
<script>
window.firstTheme = iina.appearance.getTheme();
window.firstAccent = getComputedStyle(document.documentElement).getPropertyValue('--iina-accent-color').trim();
window.callbackCount = 0; window.eventCount = 0;
window.listenerID = iina.appearance.onChange(theme => { callbackCount++; window.lastTheme = theme; });
addEventListener('iina-theme-changed', event => { eventCount++; window.lastEvent = event.detail; });
iina.onMessage('legacy', data => { window.legacyMessage = data; });
iina.postMessage('fixture-ready', { accent: firstTheme.accentColor });
</script></head><body><button id="authored" style="background: rgb(12, 34, 56); color: rgb(240, 230, 220)">Fixed author color</button></body></html>
"""#

@MainActor func runChecks() async throws {
  let defaults = UserDefaults(suiteName: "iina-appearance-fixture-\(UUID().uuidString)")!
  setHighlight("#336699", defaults: defaults)
  AppAccentColor.configure(source: .textHighlight, defaults: defaults)
  PluginAppearance.startObserving()
  PluginAppearance.startObserving()
  check(PluginAppearance.observationCounts.source == 3 && Preference.observerCount == 1,
        "One idempotent application source owns three OS/preference observers")
  check(PluginAppearance.observationCounts.subscribers == 0 && PluginAppearance.observationCounts.views == 0,
        "Bootstrap needs no native subscriber or view observer")
  let many = (0..<12).map { _ in NativeFixture() }
  check(many.allSatisfy { $0.evaluate("iina.appearance.getTheme().accentColor === '#336699'")?.toBool() == true },
        "Many getter-only contexts read the shared snapshot")
  check(PluginAppearance.observationCounts.source == 3 && Preference.observerCount == 1 &&
        PluginAppearance.observationCounts.subscribers == 0,
        "Twelve getter-only contexts add no source observers or native subscriptions")
  many.forEach { $0.evaluate("var changes = 0; var first = iina.appearance.onChange(() => changes++); var second = iina.appearance.onChange(() => changes++);") }
  check(PluginAppearance.observationCounts.source == 3 && Preference.observerCount == 1 &&
        PluginAppearance.observationCounts.subscribers == 12 && PluginAppearance.observationCounts.views == 0,
        "Twenty-four callbacks use twelve lightweight subscriptions and the same three source observers")
  setHighlight("#B22255", defaults: defaults)
  await settle()
  check(many.allSatisfy { $0.evaluate("changes === 2")?.toBool() == true },
        "A shared source update reaches every actual JavaScriptCore context once per callback")
  many.forEach { $0.evaluate("iina.appearance.offChange(first)") }
  check(PluginAppearance.observationCounts.subscribers == 12, "Removing one callback retains each active native subscription")
  many.forEach { $0.evaluate("iina.appearance.offChange(second)") }
  check(PluginAppearance.observationCounts.subscribers == 0 && PluginAppearance.observationCounts.source == 3,
        "Removing the last callback unsubscribes every native context without stopping the cache source")
  setHighlight("#228844", defaults: defaults)
  await settle()
  check(many.allSatisfy { $0.evaluate("changes === 2")?.toBool() == true }, "Unsubscribed native contexts receive no late updates")
  many.forEach { $0.dispose() }
  setHighlight("#336699", defaults: defaults)
  await settle()
  let instance = JavascriptPluginInstance()
  var context: JSContext! = JSContext()!
  context.exceptionHandler = { _, error in print("JS exception: \(error?.toString() ?? "?")") }
  var api: JavascriptAPIAppearance? = JavascriptAPIAppearance(context: context, pluginInstance: instance)
  let weakAPI = WeakBox(api)
  context.setObject(["appearance": api!], forKeyedSubscript: "iina" as NSString)
  api!.extraSetup()
  check(PluginAppearance.observationCounts.subscribers == 0, "Native extraSetup and getters do not subscribe")
  check(context.evaluateScript("typeof iina.appearance.getTheme === 'function' && typeof iina.appearance.onChange === 'function' && typeof iina.appearance.offChange === 'function'")!.toBool(), "Actual JSExport methods")
  check(context.evaluateScript("iina.appearance.getTheme().version === 1 && iina.appearance.getTheme().source === 'textHighlight' && iina.appearance.getTheme().accentColor === '#336699'")!.toBool(), "Versioned policy snapshot")
  check(context.evaluateScript("(() => { const copy = iina.appearance.getTheme(); copy.accentColor = '#000000'; return iina.appearance.getTheme().accentColor === '#336699'; })()")!.toBool(), "Fresh snapshot objects")
  check(context.evaluateScript("typeof iina.appearance.setTheme === 'undefined' && typeof iina.appearance.setAccentColor === 'undefined'")!.toBool(), "Read-only API has no setters")
  check(context.evaluateScript("(() => { try { iina.appearance.onChange({}); return false; } catch (_) { return true; } })()")!.toBool(), "Reject nonfunction callback")
  context.exception = nil
  context.evaluateScript("var calls = []; var listener = iina.appearance.onChange(theme => calls.push(theme));")
  JSGarbageCollect(context.jsGlobalContextRef)
  setHighlight("#B22255", defaults: defaults)
  await settle()
  check(context.evaluateScript("calls.length === 1 && calls[0].accentColor === '#B22255'")!.toBool(), "Managed callback survives GC and receives update")
  NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
  NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
  await settle()
  check(context.evaluateScript("calls.length === 1")!.toBool(), "Unchanged native notifications are deduplicated")
  context.evaluateScript("iina.appearance.offChange(listener)")
  check(PluginAppearance.observationCounts.subscribers == 0, "Native offChange releases its final source subscription")
  setHighlight("#228844", defaults: defaults)
  await settle()
  check(context.evaluateScript("calls.length === 1")!.toBool(), "offChange removes callback")
  context.evaluateScript("var afterCleanup = 0; iina.appearance.onChange(() => afterCleanup++)")
  api!.cleanUp(instance)
  setHighlight("#336699", defaults: defaults)
  await settle()
  check(context.evaluateScript("afterCleanup === 0")!.toBool(), "Unload cancels observers and callbacks")
  check(PluginAppearance.observationCounts.subscribers == 0, "Native unload removes its lightweight subscription")
  context.setObject(nil, forKeyedSubscript: "iina" as NSString)
  api = nil
  JSGarbageCollect(context.jsGlobalContextRef)
  context = nil
  await settle()
  check(weakAPI.value == nil, "No API/context/managed callback retain cycle")

  // Forced player Theme must win over the application's effective appearance.
  AppAccentColor.configure(source: .systemAccent)
  NSApp.appearance = NSAppearance(named: .aqua)
  Preference.setTheme(.dark)
  let expectedDark = AppAccentColor.snapshot(appearance: NSAppearance(named: .darkAqua))
  check(PluginAppearance.equal(PluginAppearance.snapshot(), expectedDark), "Configured Theme resolution")
  Preference.setTheme(.system)
  NSApp.appearance = NSAppearance(named: .darkAqua)
  await settle()
  check(PluginAppearance.observationCounts.subscribers == 0, "No native subscribers are needed to refresh the background cache")
  let cachedRead = BackgroundResult()
  let cachedReadFinished = DispatchSemaphore(value: 0)
  DispatchQueue.global().async {
    cachedRead.set(PluginAppearance.equal(PluginAppearance.snapshot(), expectedDark))
    cachedReadFinished.signal()
  }
  check(boundedMainWait(cachedReadFinished) && cachedRead.get(), "Shared source keeps background getter appearance current without listeners")
  NSApp.appearance = nil
  AppAccentColor.configure(source: .textHighlight, defaults: defaults)
  PluginAppearance.startObserving() // Production AppDelegate bootstraps the shared source before plugins.
  let observerCountBeforeBackground = Preference.observerCount
  let background = BackgroundResult()
  let finished = DispatchSemaphore(value: 0)
  DispatchQueue.global().async {
    let childContext = JSContext()!
    var childAPI: JavascriptAPIAppearance?
    let construct: @convention(block) () -> Void = {
      let child = JavascriptAPIAppearance(context: childContext, pluginInstance: JavascriptPluginInstance())
      childAPI = child
      childContext.setObject(["appearance": child], forKeyedSubscript: "iina" as NSString)
      child.extraSetup()
    }
    childContext.setObject(construct, forKeyedSubscript: "constructAppearance" as NSString)
    let result = childContext.evaluateScript("constructAppearance(); var offMainCalls = 0; iina.appearance.onChange(() => offMainCalls++); iina.appearance.getTheme().accentColor === '#336699'")?.toBool() == true
    childAPI?.cleanUp(JavascriptPluginInstance())
    childContext.setObject(nil, forKeyedSubscript: "constructAppearance" as NSString)
    background.set(result)
    finished.signal()
  }
  // Main is deliberately unavailable while the background JS VM is executing.
  check(boundedMainWait(finished) && background.get(), "Background JSExport initialization/getTheme never synchronously waits for main")
  await settle()
  check(Preference.observerCount == observerCountBeforeBackground && PluginAppearance.observationCounts.subscribers == 0, "Cleanup rejects deferred lightweight subscription startup")

  let web = WebFixture()
  let weakWebView = WeakBox(web.webView)
  check(PluginAppearance.observationCounts.source == 3 && PluginAppearance.observationCounts.subscribers == 1 && PluginAppearance.observationCounts.views == 1, "HTML adds one source subscription and only its view-specific KVO")
  try await web.loadFile(authorHTML)
  check(try await web.value("firstTheme.accentColor") as? String == "#336699", "HTML first script sees current snapshot")
  check(try await web.value("firstAccent") as? String == "#336699", "CSS token exists before first plugin script")
  check(try await web.value("Object.isFrozen(iina.appearance) && typeof iina.postMessage === 'function'") as? Bool == true, "Read-only appearance preserves message API")
  check(web.messages.count == 1, "Existing native postMessage handler receives message")
  _ = try await web.value("iina._emit('legacy', JSON.stringify({ok:true}))")
  check(try await web.value("legacyMessage.ok") as? Bool == true, "Existing onMessage/_emit compatibility")
  check(try await web.value("callbackCount + eventCount") as? Int == 0, "Initial seed does not emit a duplicate change")
  _ = try await web.value("window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted:true}))")
  setHighlight("#B22255", defaults: defaults)
  await settle()
  check(try await web.value("callbackCount === 1 && eventCount === 1 && lastTheme.accentColor === '#B22255' && lastEvent.accentColor === '#B22255'") as? Bool == true, "HTML callback survives persisted pagehide and browser event updates once")
  check(try await web.value("getComputedStyle(document.documentElement).getPropertyValue('--iina-accent-color').trim()") as? String == "#B22255", "Live CSS token update")
  check(try await web.value("getComputedStyle(document.getElementById('authored')).backgroundColor") as? String == "rgb(12, 34, 56)", "Plugin-authored color is preserved")
  check(try await web.value("typeof window.__isolatedFixture") as? String == "undefined", "Isolated legacy script does not leak into page world")
  let isolatedValue: Any = try await withCheckedThrowingContinuation { continuation in
    web.webView.evaluateJavaScript("window.__isolatedFixture", in: nil, in: .defaultClient) { result in
      continuation.resume(with: result)
    }
  }
  check(isolatedValue as? Int == 17, "Isolated legacy script content world is retained")
  let scripts = web.webView.configuration.userContentController.userScripts
  check(scripts.count == 3 && scripts[0].source == web.originalScripts[0].source && scripts[1].source == web.originalScripts[1].source, "Original script order/content worlds are preserved")
  NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
  await settle()
  check(try await web.value("callbackCount === 1 && eventCount === 1") as? Bool == true, "HTML unchanged update deduplication")
  _ = try await web.value("iina.appearance.offChange(listenerID)")
  setHighlight("#228844", defaults: defaults)
  await settle()
  check(try await web.value("callbackCount === 1 && eventCount === 2") as? Bool == true, "HTML offChange removes callback only")
  try await web.reload()
  check(try await web.value("firstAccent") as? String == "#228844", "Reload first plugin script sees refreshed seed")
  check(try await web.value("firstTheme.accentColor") as? String == "#228844", "Reload API snapshot is current")
  check(try await web.value("callbackCount + eventCount") as? Int == 0, "Reload has one new subscription set")
  try await web.load(FixtureScripts.simpleModeHTML)
  check(try await web.value("iina.appearance.getTheme().accentColor") as? String == "#228844", "Simple mode API injection")
  _ = try await web.value("iina._simpleModeSetStyle('#content { color: var(--iina-accent-color, #007AFF); }'); iina._simpleModeSetContent('Token text')")
  check(try await web.value("getComputedStyle(document.getElementById('content')).color") as? String == "rgb(34, 136, 68)", "Simple mode content/style bridge uses tokens")
  let bridge = web.bridge!
  bridge.invalidate()
  setHighlight("#445566", defaults: defaults)
  await settle()
  check(try await web.value("iina.appearance.getTheme().accentColor") as? String == "#228844", "Disposed bridge stops page updates")
  web.dispose()
  await settle()
  check(weakWebView.value == nil, "Bridge does not retain WebView")
  check(PluginAppearance.observationCounts.source == 3 && PluginAppearance.observationCounts.subscribers == 0 && PluginAppearance.observationCounts.views == 0, "Disposal removes consumers and view KVO while retaining one application source")
  print("Observer ownership: source=3; 12 getter-only contexts=0 subscribers; 24 callbacks=12 lightweight subscriptions; after cleanup=0 subscribers/0 views")
  check(!NSApp.isActive, "All fixtures remained nonactivating")
  print("\(checks) JavaScriptCore/WebKit appearance checks passed; no profile or system writes")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
  do { try await runChecks(); exit(0) }
  catch { print("FAIL: \(error)"); exit(1) }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 45) { print("FAIL: fixture timed out"); exit(2) }
app.run()
