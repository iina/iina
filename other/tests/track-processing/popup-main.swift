// Opt in: real native menu tracking must remain separate from the left-click action.
if ProcessInfo.processInfo.environment["TRACK_SETTINGS_POPUP_TESTS"] == "1" {
  let host = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 360, height: 260),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
  host.isReleasedWhenClosed = false
  let contextPlayer = PlayerCore()
  contextPlayer.scopedTrackSettings.setTarget(1, for: .audioDelay)
  contextPlayer.scopedTrackSettings.audio[1] = AudioTrackProcessing(delay: 0.5)
  let button = TrackSettingsGroupReset(player: contextPlayer, group: .audioDelay)
  button.translatesAutoresizingMaskIntoConstraints = true
  host.contentView!.addSubview(button)
  host.orderFrontRegardless()
  let before = contextPlayer.mpv.writes
  for (index, origin) in [NSPoint(x: 0, y: 0), NSPoint(x: 300, y: 0),
                          NSPoint(x: 0, y: 236), NSPoint(x: 300, y: 236)].enumerated() {
    button.frame = NSRect(origin: origin, size: NSSize(width: 60, height: 24))
    let menu = button.resetContextMenu!()
    button.resetContextMenu = { menu }
    var observed = false
    let timer = Timer(timeInterval: 0.08, repeats: false) { _ in
      let windows = NSApp.windows.filter { $0 !== host && $0.isVisible }
      check(windows.count == 1 && host.frame.contains(windows[0].frame), "right-click reset menu stays inside player at every corner")
      if let popup = windows.first {
        let buttonFrame = host.convertToScreen(button.convert(button.bounds, to: nil))
        let gap = popup.frame.minY >= buttonFrame.maxY
          ? popup.frame.minY - buttonFrame.maxY : buttonFrame.minY - popup.frame.maxY
        check(abs(gap - 8) < 0.5, "native Reset menu keeps the same 8-point gap above and below the button")
      }
      check(menu.items.count == 2, "native Reset menu contains exactly the two scope choices")
      observed = true
      menu.cancelTrackingWithoutAnimation()
    }
    RunLoop.main.add(timer, forMode: .eventTracking)
    let point = button.convert(NSPoint(x: 30, y: 12), to: nil)
    let event = NSEvent.mouseEvent(with: index == 1 ? .leftMouseDown : .rightMouseDown,
      location: point, modifierFlags: index == 1 ? [.control] : [], timestamp: 0,
      windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    if index == 1 { button.mouseDown(with: event) }
    else if index == 2 { _ = button.accessibilityPerformShowMenu() }
    else { button.rightMouseDown(with: event) }
    timer.invalidate()
    check(observed && contextPlayer.mpv.writes == before, "right click, Control-click and accessibility menu cancellation never reset")
  }
  var primaryRequestedMenu = false
  button.resetContextMenu = { primaryRequestedMenu = true; return NSMenu() }
  let primaryPoint = button.convert(NSPoint(x: 30, y: 12), to: nil)
  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: primaryPoint, modifierFlags: [], timestamp: 0,
    windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
  NSApp.postEvent(up, atStart: true)
  let down = NSEvent.mouseEvent(with: .leftMouseDown, location: primaryPoint, modifierFlags: [], timestamp: 0,
    windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
  button.mouseDown(with: down)
  check(!primaryRequestedMenu && contextPlayer.scopedTrackSettings.audio[1] == nil,
        "real left mouse tracking resets directly without requesting a context menu")
  contextPlayer.scopedTrackSettings.audio[1] = AudioTrackProcessing(delay: 0.7)
  let shared = SidebarResetButton(target: button, action: #selector(NSButton.performClick(_:)))
  shared.translatesAutoresizingMaskIntoConstraints = true
  host.contentView!.addSubview(shared)
  let sharedMenu = shared.resetContextMenu!()
  check(sharedMenu.items.count == 1 && sharedMenu.items[0].action == shared.action
    && sharedMenu.items[0].target === shared.target, "shared Reset automatically exposes only its direct action")
  let beforeSharedMenu = contextPlayer.mpv.writes
  for (index, y) in [20.0, 200.0].enumerated() {
    shared.frame = NSRect(x: 280, y: y, width: 60, height: 24)
    shared.resetContextMenu = { sharedMenu }
    var observed = false
    let timer = Timer(timeInterval: 0.08, repeats: false) { _ in
      let windows = NSApp.windows.filter { $0 !== host && $0.isVisible }
      check(windows.count == 1 && host.frame.contains(windows[0].frame), "single-action Reset menu stays inside the player")
      let frame = windows[0].frame
      let anchor = host.convertToScreen(shared.convert(shared.bounds, to: nil))
      let gap = frame.minY >= anchor.maxY ? frame.minY - anchor.maxY : anchor.minY - frame.maxY
      check(abs(gap - 8) < 0.5, "single-action Reset keeps the same 8-point gap in both directions")
      observed = true
      sharedMenu.cancelTrackingWithoutAnimation()
    }
    RunLoop.main.add(timer, forMode: .eventTracking)
    if index == 0 {
      let event = NSEvent.mouseEvent(with: .rightMouseDown, location: shared.convert(NSPoint(x: 30, y: 12), to: nil),
        modifierFlags: [], timestamp: 0, windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
      shared.rightMouseDown(with: event)
    } else { _ = shared.accessibilityPerformShowMenu() }
    timer.invalidate()
    check(observed && contextPlayer.mpv.writes == beforeSharedMenu, "single-action menu cancellation does not reset")
  }
  let onlyAction = sharedMenu.items[0]
  _ = NSApp.sendAction(onlyAction.action!, to: onlyAction.target, from: onlyAction)
  check(contextPlayer.scopedTrackSettings.audio[1] == nil, "single context action invokes the same reset target as primary click")
  let unconfigured = SidebarResetButton(target: nil, action: nil)
  check(!unconfigured.accessibilityPerformShowMenu(), "an unconfigured Reset cannot present an empty menu")
  host.close()
  print("Reset context presentation checks complete: \(checks) total checks.")
}
