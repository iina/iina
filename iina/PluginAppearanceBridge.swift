//
//  PluginAppearanceBridge.swift
//  iina
//

import Cocoa
@preconcurrency import WebKit

/// Shared resolution for the plugin process and its HTML documents. Reading the
/// tokens never creates a player window or changes the current launch's policy.
enum PluginAppearance {
  private static let appearanceLock = NSLock()
  private static var systemAppearance = NSAppearance(named: .aqua)!
  private static let source = PluginAppearanceSource()
  fileprivate static let changedNotification = Notification.Name("IINAPluginAppearanceChanged")

  /// Bootstrap once after defaults, before any plugin can enter JavaScriptCore.
  /// Background callers must never wait for main while holding the JS VM lock.
  static func startObserving() {
    if Thread.isMainThread {
      source.start()
    } else {
      DispatchQueue.main.async { source.start() }
    }
  }

  static func snapshot(appearance: NSAppearance? = nil) -> [String: Any] {
    let theme: Preference.Theme = Preference.enum(for: .themeMaterial)
    let system: NSAppearance
    if Thread.isMainThread {
      let applicationAppearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
      system = appearance ?? applicationAppearance
      appearanceLock.lock()
      systemAppearance = applicationAppearance
      appearanceLock.unlock()
    } else {
      // JavaScriptCore can enter an API on a plugin queue. Do not synchronously
      // hop to main while that thread holds the JS virtual machine's lock.
      appearanceLock.lock()
      system = systemAppearance
      appearanceLock.unlock()
    }
    return AppAccentColor.snapshot(appearance: NSAppearance(iinaTheme: theme) ?? system)
  }

  static func equal(_ first: [String: Any], _ second: [String: Any]) -> Bool {
    NSDictionary(dictionary: first).isEqual(to: second)
  }

  #if PLUGIN_APPEARANCE_TESTING
  static var observationCounts: (source: Int, subscribers: Int, views: Int) {
    let subscribers = PluginAppearanceObservation.registrationCounts
    return (source.registrationCount, subscribers.source, subscribers.view)
  }
  #endif
}

/// One app-level owner of the three OS/preference registrations. It keeps the
/// background getter's appearance cache fresh even when no plugin subscribes.
private final class PluginAppearanceSource {
  private var started = false
  private var refreshPending = false
  private var colorsToken: NSObjectProtocol?
  private var appObservation: NSKeyValueObservation?
  private var preferenceObserver: Preference.Observer?

  func start() {
    guard !started else { return }
    started = true
    _ = PluginAppearance.snapshot()
    colorsToken = NotificationCenter.default.addObserver(
      forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.scheduleRefresh() }
    appObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
      self?.scheduleRefresh()
    }
    let observer = Preference.Observer()
    observer.add(.themeMaterial) { [weak self] _ in self?.scheduleRefresh() }
    preferenceObserver = observer
  }

  deinit {
    if let colorsToken { NotificationCenter.default.removeObserver(colorsToken) }
    appObservation?.invalidate()
  }

  private func scheduleRefresh() {
    DispatchQueue.main.async { [weak self] in
      guard let self, !refreshPending else { return }
      refreshPending = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        refreshPending = false
        _ = PluginAppearance.snapshot()
        NotificationCenter.default.post(name: PluginAppearance.changedNotification, object: self)
      }
    }
  }

  #if PLUGIN_APPEARANCE_TESTING
  var registrationCount: Int {
    (colorsToken == nil ? 0 : 1) + (appObservation == nil ? 0 : 1) + (preferenceObserver == nil ? 0 : 1)
  }
  #endif
}

/// A lightweight source subscription, with KVO only for a consumer's own view.
/// Publish only changed versioned tokens after app/view notifications settle.
final class PluginAppearanceObservation {
  private let changed: ([String: Any]) -> Void
  private let appearance: () -> NSAppearance?
  private var lastSnapshot: [String: Any]
  private var sourceToken: NSObjectProtocol?
  private var viewObservation: NSKeyValueObservation?
  private let lifecycleLock = NSLock()
  private var invalidated = false
  private var refreshPending = false

  init(view: NSView? = nil, changed: @escaping ([String: Any]) -> Void) {
    self.changed = changed
    appearance = { [weak view] in view?.effectiveAppearance }
    lastSnapshot = [:]
    if Thread.isMainThread {
      startObserving(view: view)
    } else {
      // Child plugin initialization can hold the JS virtual machine's lock.
      // App startup seeds the system appearance cache before creating plugins.
      DispatchQueue.main.async { [weak self, weak view] in
        self?.startObserving(view: view)
      }
    }
  }

  private func startObserving(view: NSView?) {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    guard !invalidated else { return }
    PluginAppearance.startObserving()
    lastSnapshot = PluginAppearance.snapshot(appearance: appearance())
    sourceToken = NotificationCenter.default.addObserver(
      forName: PluginAppearance.changedNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.scheduleRefresh() }
    viewObservation = view?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
      self?.scheduleRefresh()
    }
    #if PLUGIN_APPEARANCE_TESTING
    Self.recordRegistrations(source: 1, view: viewObservation == nil ? 0 : 1)
    #endif
  }

  deinit { invalidate() }

  func invalidate() {
    lifecycleLock.lock()
    guard !invalidated else { lifecycleLock.unlock(); return }
    invalidated = true
    let token = sourceToken
    let view = viewObservation
    sourceToken = nil
    viewObservation = nil
    #if PLUGIN_APPEARANCE_TESTING
    Self.recordRegistrations(source: token == nil ? 0 : -1, view: view == nil ? 0 : -1)
    #endif
    lifecycleLock.unlock()
    if let token { NotificationCenter.default.removeObserver(token) }
    view?.invalidate()
  }

  #if PLUGIN_APPEARANCE_TESTING
  private static let registrationsLock = NSLock()
  private static var sourceRegistrations = 0
  private static var viewRegistrations = 0
  fileprivate static var registrationCounts: (source: Int, view: Int) {
    registrationsLock.lock()
    defer { registrationsLock.unlock() }
    return (sourceRegistrations, viewRegistrations)
  }
  private static func recordRegistrations(source: Int, view: Int) {
    registrationsLock.lock()
    sourceRegistrations += source
    viewRegistrations += view
    registrationsLock.unlock()
  }
  #endif

  private var isActive: Bool {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    return !invalidated
  }

  private func scheduleRefresh() {
    // KVO can arrive from the thread changing a preference. AppKit access and
    // callbacks use the same main-thread delivery as the existing plugin UI API.
    DispatchQueue.main.async { [weak self] in
      guard let self, isActive, !refreshPending else { return }
      refreshPending = true
      DispatchQueue.main.async { [weak self] in
        guard let self, isActive else { return }
        refreshPending = false
        let snapshot = PluginAppearance.snapshot(appearance: appearance())
        guard !PluginAppearance.equal(lastSnapshot, snapshot) else { return }
        lastSnapshot = snapshot
        changed(snapshot)
      }
    }
  }
}

/// Owns only appearance injection. The existing window.iina message hub and
/// isolated sidebar input script keep their original handlers and content worlds.
final class PluginAppearanceBridge {
  private weak var webView: WKWebView?
  private var observation: PluginAppearanceObservation?
  private var userScript: WKUserScript?
  private var lastSnapshot: [String: Any] = [:]
  private var invalidated = false

  init(webView: WKWebView) {
    self.webView = webView
    update(PluginAppearance.snapshot(appearance: webView.effectiveAppearance), publish: false)
    observation = PluginAppearanceObservation(view: webView) { [weak self] snapshot in
      self?.update(snapshot, publish: true)
    }
  }

  deinit { invalidate() }

  func invalidate() {
    invalidated = true
    observation?.invalidate()
    observation = nil
  }

  /// Refresh the document-start seed before reloads and navigations are allowed.
  func prepareForNavigation() {
    guard let webView, !invalidated else { return }
    update(PluginAppearance.snapshot(appearance: webView.effectiveAppearance), publish: true)
  }

  func didFinishNavigation() {
    guard let webView, !invalidated else { return }
    update(PluginAppearance.snapshot(appearance: webView.effectiveAppearance), publish: false)
    publish(lastSnapshot)
  }

  private func update(_ snapshot: [String: Any], publish shouldPublish: Bool) {
    guard let webView, !invalidated, !PluginAppearance.equal(lastSnapshot, snapshot) else { return }
    lastSnapshot = snapshot
    let next = WKUserScript(source: Self.script(snapshot: snapshot), injectionTime: .atDocumentStart,
                            forMainFrameOnly: true)
    let controller = webView.configuration.userContentController
    if let previous = userScript, controller.userScripts.contains(where: { $0.source == previous.source }) {
      // Locate our exact generated source independently of WK object identity.
      // Materialize the collection before removal, preserving scripts and worlds.
      let scripts = controller.userScripts.map { $0 }
      controller.removeAllUserScripts()
      scripts.forEach { controller.addUserScript($0.source == previous.source ? next : $0) }
    } else {
      controller.addUserScript(next)
    }
    userScript = next
    if shouldPublish { publish(snapshot) }
  }

  private func publish(_ snapshot: [String: Any]) {
    guard let webView, let json = Self.json(snapshot), !invalidated else { return }
    webView.evaluateJavaScript("window[Symbol.for('iina.appearance.update.v1')]?.(\(json));")
  }

  private static func json(_ snapshot: [String: Any]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func script(snapshot: [String: Any]) -> String {
    let initial = json(snapshot) ?? "{}"
    return #"""
    /* IINA appearance bridge v1 */
    (() => {
      const updateKey = Symbol.for('iina.appearance.update.v1');
      let current = Object.freeze(\#(initial));
      const listeners = new Map();
      let nextID = 0;
      let rootObserver = null;
      const copy = () => ({ ...current });
      function setTokens() {
        const root = document.documentElement;
        if (!root) return false;
        root.style.setProperty('--iina-accent-color', current.accentColor);
        root.style.setProperty('--iina-accent-text-color', current.accentTextColor);
        if (rootObserver) { rootObserver.disconnect(); rootObserver = null; }
        return true;
      }
      if (!setTokens()) {
        rootObserver = new MutationObserver(setTokens);
        rootObserver.observe(document, { childList: true });
      }
      const api = Object.freeze({
        getTheme() { return copy(); },
        onChange(callback) {
          if (typeof callback !== 'function') throw new TypeError('appearance.onChange requires a function');
          const id = `appearance-${++nextID}`;
          listeners.set(id, callback);
          return id;
        },
        offChange(id) { listeners.delete(id); }
      });
      window.iina = window.iina || {};
      Object.defineProperty(window.iina, 'appearance', { value: api, enumerable: true });
      Object.defineProperty(window, updateKey, { value(snapshot) {
        if (JSON.stringify(current) === JSON.stringify(snapshot)) return;
        current = Object.freeze({ ...snapshot });
        setTokens();
        for (const [id, callback] of [...listeners]) {
          if (listeners.get(id) !== callback) continue;
          try { callback(copy()); } catch (error) { console.error(error); }
        }
        window.dispatchEvent(new CustomEvent('iina-theme-changed', { detail: copy() }));
      }});
      window.addEventListener('pagehide', event => {
        if (event.persisted) return;
        listeners.clear();
        if (rootObserver) rootObserver.disconnect();
      });
    })();
    """#
  }
}
