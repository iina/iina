//
//  AppRestart.swift
//  iina
//

import Cocoa

/// Relaunch only after normal application termination has finished saving state.
enum AppRestart {
  private static let helperArgument = "--iina-relaunch-after-exit="
  private static let restoreSettingsKey = "restoreSettingsAfterRestart"
  private static let immediateRestartKey = "immediateSettingsRestart"
  private static var helper: Process?
  private static var launchEnvironment: [String: String]?
  private static var capturedSessionForQuit = false
  private static var immediateRestartRequested = false
  private static weak var pendingConfirmationWindow: SettingsWindow?
  private static weak var confirmationWindow: SettingsWindow?
  private static var confirmationScheduled = false
  private static var confirmationObservers: [NSObjectProtocol] = []
  private static var confirmationCloseObserver: NSObjectProtocol?

  /// Present once after a committed Settings change, including picker completion.
  static func confirmSettingsChange(in window: SettingsWindow) {
    precondition(Thread.isMainThread)
    guard window.isVisible, confirmationWindow == nil else { return }
    pendingConfirmationWindow = window
    if confirmationObservers.isEmpty {
      let center = NotificationCenter.default
      confirmationObservers = [
        center.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { _ in
          scheduleConfirmation()
        },
        center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
          pendingConfirmationWindow = nil
          removeConfirmationObservers()
        }
      ]
    }
    scheduleConfirmation()
  }

  private static func scheduleConfirmation() {
    guard !confirmationScheduled else { return }
    confirmationScheduled = true
    DispatchQueue.main.async {
      confirmationScheduled = false
      presentPendingConfirmation()
    }
  }

  private static func removeConfirmationObservers() {
    confirmationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    confirmationObservers.removeAll()
  }

  private static func presentPendingConfirmation() {
    guard let window = pendingConfirmationWindow, window.isVisible else {
      pendingConfirmationWindow = nil
      removeConfirmationObservers()
      return
    }
    // NSOpenPanel and the custom-color sheet may still be completing their action.
    guard window.attachedSheet == nil else { return }
    pendingConfirmationWindow = nil
    removeConfirmationObservers()
    confirmationWindow = window
    window.endEditing(for: nil)
    guard window.isVisible else {
      confirmationWindow = nil
      return
    }
    if window.attachedSheet != nil {
      confirmationWindow = nil
      confirmSettingsChange(in: window)
      return
    }

    let alert = NSAlert()
    alert.messageText = NSLocalizedString("alert.settings_restart.title", comment: "Restart title")
    alert.informativeText = NSLocalizedString("alert.settings_restart.message", comment: "Restart explanation")
    let restartButton = alert.addButton(withTitle: NSLocalizedString("alert.settings_restart.restart", comment: "Restart"))
    let laterButton = alert.addButton(withTitle: NSLocalizedString("alert.settings_restart.later", comment: "Later"))
    laterButton.keyEquivalent = "\u{1b}"
    AccentControls.styleDefaultButton(in: alert)
    confirmationCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak window, weak sheet = alert.window] _ in
      guard let window, let sheet, window.attachedSheet === sheet else { return }
      window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
    }
    alert.beginSheetModal(for: window) { [weak window] response in
      if let observer = confirmationCloseObserver {
        NotificationCenter.default.removeObserver(observer)
        confirmationCloseObserver = nil
      }
      confirmationWindow = nil
      guard response == .alertFirstButtonReturn, let window else {
        discardRestoreRequest()
        return
      }
      do {
        try restart(restoring: window)
      } catch {
        NSAlert(error: error).beginSheetModal(for: window)
      }
    }
    // AppKit resets the default key while presenting a customized alert cell.
    restartButton.keyEquivalent = "\r"
  }

  /// The same executable has a small non-UI mode which waits for its parent to exit.
  /// A process-exit event avoids racing Launch Services or guessing a sleep duration.
  static func runHelperIfRequested() -> Bool {
    // Called first from main, before PlayerCore changes PATH or http_proxy.
    if launchEnvironment == nil { launchEnvironment = ProcessInfo.processInfo.environment }
    guard CommandLine.arguments.count == 2,
          CommandLine.arguments[1].hasPrefix(helperArgument) else { return false }
    let value = CommandLine.arguments[1].dropFirst(helperArgument.count)
    guard let parent = Int32(value), parent > 1, parent != getpid() else { return true }
    let applicationURL = Bundle.main.bundleURL
    let queue = DispatchQueue(label: "iina.relaunch")
    let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: queue)
    var launched = false
    let launch = {
      guard !launched else { return }
      launched = true
      source.cancel()
      let open = Process()
      open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      open.arguments = ["-n", applicationURL.path]
      do {
        try open.run()
        open.waitUntilExit()
        exit(open.terminationStatus)
      } catch {
        fputs("Unable to relaunch application: \(error)\n", stderr)
        exit(EXIT_FAILURE)
      }
    }
    source.setEventHandler(handler: launch)
    source.resume()
    queue.async {
      if kill(parent, 0) == -1 && errno == ESRCH { launch() }
    }
    dispatchMain()
  }

  static func consumeSettingsRestoreRequest(defaults: UserDefaults = .standard) -> Bool {
    // Older builds also set the legacy flag for Later. Only the new immediate
    // handoff marker proves that Settings should reopen on this launch.
    let restore = defaults.bool(forKey: restoreSettingsKey) && defaults.bool(forKey: immediateRestartKey)
    defaults.removeObject(forKey: restoreSettingsKey)
    defaults.removeObject(forKey: immediateRestartKey)
    defaults.synchronize()
    return restore
  }

  /// Only an immediate Restart captures at its actual normal termination.
  static func captureSessionIfRequested(defaults: UserDefaults = .standard) {
    guard immediateRestartRequested, !capturedSessionForQuit,
          defaults.bool(forKey: restoreSettingsKey), defaults.bool(forKey: immediateRestartKey) else { return }
    capturedSessionForQuit = true
    SettingsWindow.default.saveNavigationLocation()
    AppRestartSession.capture(defaults: defaults)
  }

  /// Later keeps the saved preference only. Remove any older restore intent.
  static func discardRestoreRequest(defaults: UserDefaults = .standard) {
    immediateRestartRequested = false
    capturedSessionForQuit = false
    defaults.removeObject(forKey: restoreSettingsKey)
    defaults.removeObject(forKey: immediateRestartKey)
    defaults.removeObject(forKey: AppRestartSession.preferenceKey)
    defaults.synchronize()
  }

  static func prepareForImmediateRestart(_ window: SettingsWindow, defaults: UserDefaults = .standard) {
    window.saveNavigationLocation()
    // A stale payload must not survive if termination cannot capture a new one.
    defaults.removeObject(forKey: AppRestartSession.preferenceKey)
    defaults.set(true, forKey: restoreSettingsKey)
    defaults.set(true, forKey: immediateRestartKey)
    defaults.synchronize()
    capturedSessionForQuit = false
    immediateRestartRequested = true
  }

  static func restart(restoring window: SettingsWindow) throws {
    guard helper == nil else { return }
    discardRestoreRequest()
    helper = try startRelaunchHelper()
    // The next process needs the handoff even when it starts immediately after exit.
    prepareForImmediateRestart(window)
    NSApp.terminate(nil)
  }

  static func startRelaunchHelper() throws -> Process {
    guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
    let process = Process()
    process.executableURL = executable
    process.arguments = [helperArgument + String(getpid())]
    // Preserve the user's launch environment, not app-applied proxy/search paths.
    process.environment = launchEnvironment
    try process.run()
    return process
  }
}
