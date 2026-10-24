import Cocoa

func runPanelDepthChecks() {
  Preference.values = [.settingsLeading: true, .playlistLeading: false, .pluginsLeading: true,
                       .edgeToEdgeVideo: true, .disableAnimations: true, .oscDoubleClickAction: 0]
  let controller = MainWindowController()
  let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 600),
                        styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  controller.window = window
  let content = window.contentView!
  controller.titleBarView = ChromeFixture(minimumWidth: 180, titlebar: true)
  controller.oscBottomView = ChromeFixture(minimumWidth: 28, titlebar: false)
  for view in [controller.titleBarView!, controller.oscBottomView!] {
    content.addSubview(view); view.padding(.horizontal)
    view.topAnchor.constraint(equalTo: content.topAnchor).isActive = true
  }
  let osc = controller.oscFloatingView
  content.addSubview(osc, positioned: .below, relativeTo: controller.titleBarView)
  osc.setupConstraints()
  osc.oscTopView.heightAnchor.constraint(equalToConstant: 24).isActive = true
  osc.oscBottomView.heightAnchor.constraint(equalToConstant: 28).isActive = true
  controller.sidebars.installSubviews(in: content)
  window.orderFrontRegardless()
  func pump(_ duration: TimeInterval = 0.04) {
    let end = Date().addingTimeInterval(duration)
    repeat { content.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.002)) } while Date() < end
  }
  func index(_ view: NSView) -> Int { content.subviews.firstIndex(of: view)! }
  func mouse(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
  }
  func leftClick(_ point: NSPoint, clicks: Int = 1) {
    controller.sidebars.handlePanelMouseEvent(mouse(.leftMouseDown, point, clicks: clicks))
    controller.sidebars.handlePanelMouseEvent(mouse(.leftMouseUp, point, clicks: clicks))
  }
  func drag(to origin: NSPoint) {
    let start = osc.convert(NSPoint(x: 3, y: osc.bounds.height - 3), to: nil)
    osc.mouseDown(with: mouse(.leftMouseDown, start))
    let offset = osc.mousePosRelatedToView!
    let target = NSPoint(x: origin.x + offset.x, y: origin.y + offset.y)
    osc.mouseDragged(with: mouse(.leftMouseDragged, target))
    osc.mouseUp(with: mouse(.leftMouseUp, target)); pump()
  }
  osc.updatePosition(); pump()
  let initial = osc.frame
  let initialIntent = osc.currentPosition
  for fade in [false, true] {
    AccessibilityPreferences.motionReductionEnabled = fade
    for onLeft in [true, false] {
      Preference.set(onLeft, for: .settingsLeading)
      Preference.set(!onLeft, for: .playlistLeading)
      for animate in [false, true] {
        Preference.set(!animate, for: .disableAnimations)
        controller.sidebars.show(sidebar: .settings)
        let showDeadline = Date().addingTimeInterval(0.4)
        var stationary = true
        while Date() < showDeadline {
          content.layoutSubtreeIfNeeded(); stationary = stationary && osc.frame == initial
          RunLoop.main.run(until: Date().addingTimeInterval(0.003))
        }
        check(stationary && osc.currentPosition == initialIntent,
              "opening sidebar leaves OSC stationary (left=\(onLeft), fade=\(fade), animate=\(animate))")
        let panel = controller.sidebars.sideBars.first { $0.status == .settings }!
        check(index(panel.view) > index(osc), "new sidebar opens above OSC")
        controller.sidebars.bringPanelToFront(osc); pump()
        check(osc.frame == initial && osc.currentPosition == initialIntent, "raising OSC changes depth only")
        let header = controller.sidebars.quickSettingView.tabHeader
        let headerPoint = header.convert(NSPoint(x: 20, y: 8), to: nil)
        let bodyPoint = panel.view.convert(NSPoint(x: 20, y: 200), to: nil)
        leftClick(bodyPoint)
        check(index(panel.view) > index(osc), "primary sidebar body click raises only its owner")
        controller.sidebars.bringPanelToFront(osc)
        leftClick(headerPoint)
        check(index(panel.view) > index(osc) && osc.frame == initial, "primary sidebar header raises without movement")
        let once = content.subviews
        leftClick(headerPoint)
        check(content.subviews == once, "raising an already-front header is idempotent")
        controller.sidebars.hide(.settings)
        let hideDeadline = Date().addingTimeInterval(0.4)
        stationary = true
        while Date() < hideDeadline {
          content.layoutSubtreeIfNeeded(); stationary = stationary && osc.frame == initial
          RunLoop.main.run(until: Date().addingTimeInterval(0.003))
        }
        check(stationary && osc.currentPosition == initialIntent,
              "closing sidebar leaves OSC stationary through all native frame ticks")
      }
    }
  }
  AccessibilityPreferences.motionReductionEnabled = false
  Preference.set(true, for: .disableAnimations)
  for kind in [SidebarController.ViewType.settings, .playlist, .plugins] {
    controller.sidebars.show(sidebar: kind); pump()
    let panel = controller.sidebars.sideBars.first { $0.status == kind }!
    let vc: SidebarViewController = kind == .settings ? controller.sidebars.quickSettingView :
      (kind == .playlist ? controller.sidebars.playlistView : controller.sidebars.pluginView)
    let header = vc.tabHeader
    let point = header.convert(NSPoint(x: 20, y: 8), to: nil)
    controller.sidebars.bringPanelToFront(osc)
    // Header controls promote their owner without consuming the native action.
    for control in [NSButton(), NSSegmentedControl(), NSPopUpButton()] as [NSControl] {
      control.frame = NSRect(x: 4, y: 4, width: 80, height: 40)
      header.addSubview(control)
      leftClick(point)
      check(index(panel.view) > index(osc), "header control promotes its owner (\(kind), \(type(of: control)))")
      control.removeFromSuperview()
      controller.sidebars.bringPanelToFront(osc)
    }
    let body = panel.view.convert(NSPoint(x: 40, y: 180), to: nil)
    leftClick(body)
    check(index(panel.view) > index(osc), "primary body click raises every sidebar type (\(kind))")
    controller.sidebars.bringPanelToFront(osc)
    controller.sidebars.handlePanelMouseEvent(mouse(.rightMouseDown, point))
    controller.sidebars.handlePanelMouseEvent(mouse(.rightMouseUp, body))
    check(index(osc) > index(panel.view), "secondary header press retains depth (\(kind))")
    controller.sidebars.handlePanelMouseEvent(mouse(.rightMouseDown, point))
    controller.sidebars.handlePanelMouseEvent(mouse(.rightMouseDragged, NSPoint(x: point.x + 10, y: point.y)))
    controller.sidebars.handlePanelMouseEvent(mouse(.rightMouseUp, point))
    check(index(osc) > index(panel.view), "secondary header drag retains depth (\(kind))")
    leftClick(point)
    check(index(panel.view) > index(osc), "shared header action works for every sidebar type (\(kind))")
    let titlebarPoint = controller.titleBarView.convert(NSPoint(x: 20, y: 10), to: nil)
    let order = content.subviews
    leftClick(titlebarPoint)
    check(content.subviews == order, "player titlebar is not a sidebar header (\(kind))")
    controller.sidebars.hide(kind, animate: false); pump()
  }
  controller.sidebars.show(sidebar: .settings); pump()
  let settingsPanel = controller.sidebars.sideBars.first { $0.status == .settings }!
  let settingsHeader = controller.sidebars.quickSettingView.tabHeader
  let settingsPoint = settingsHeader.convert(NSPoint(x: 20, y: 8), to: nil)
  for clicks in [2, 3, 0, 1, 2] {
    controller.sidebars.bringPanelToFront(osc)
    leftClick(settingsPoint, clicks: clicks)
    check(index(settingsPanel.view) > index(osc), "primary activation accepts repeat click count \(clicks)")
  }
  controller.sidebars.bringPanelToFront(osc)
  controller.sidebars.show(sidebar: .playlist)
  let playlistPanel = controller.sidebars.sideBars.first { $0.status == .playlist }!
  check(index(settingsPanel.view) < index(osc) && index(playlistPanel.view) > index(osc),
        "opening a second sidebar leaves the first below OSC")
  pump()
  controller.sidebars.bringPanelToFront(osc)
  check(index(osc) > index(settingsPanel.view) && index(osc) > index(playlistPanel.view),
        "OSC promotion raises it above both independent sidebars")
  leftClick(settingsPoint)
  check(index(settingsPanel.view) > index(osc) && index(osc) > index(playlistPanel.view),
        "primary settings activation creates settings-OSC-playlist depth")
  let independentOrder = content.subviews
  leftClick(settingsPoint, clicks: 2)
  check(content.subviews == independentOrder, "repeated primary activation is idempotent")
  controller.sidebars.bringPanelToFront(osc)
  controller.sidebars.hide(.playlist, animate: false); pump()
  check(index(osc) > index(settingsPanel.view), "closing one sidebar preserves its peer's depth")
  controller.sidebars.show(sidebar: .playlist); pump()
  check(index(settingsPanel.view) < index(osc) && index(playlistPanel.view) > index(osc),
        "reopening a sidebar does not raise its peer")
  Preference.set(Preference.bool(for: .settingsLeading), for: .pluginsLeading)
  controller.sidebars.bringPanelToFront(osc)
  controller.sidebars.show(sidebar: .plugins); pump()
  let pluginPanel = controller.sidebars.sideBars.first { $0.status == .plugins }!
  check(index(pluginPanel.view) > index(osc) && index(playlistPanel.view) < index(osc),
        "replacing settings with plugins raises only the replaced side")
  controller.sidebars.hide(.plugins, animate: false); pump()
  controller.sidebars.show(sidebar: .settings); pump()
  content.addSubview(settingsPanel.view, positioned: .below, relativeTo: osc)
  content.addSubview(playlistPanel.view, positioned: .above, relativeTo: osc)
  let playlistHeader = controller.sidebars.playlistView.tabHeader
  leftClick(playlistHeader.convert(NSPoint(x: 20, y: 8), to: nil))
  check(index(settingsPanel.view) < index(osc) && index(playlistPanel.view) > index(osc),
        "clicking the front sidebar preserves the independent mixed order")
  check(osc.frame == initial, "two sidebars cannot squeeze OSC")
  drag(to: NSPoint(x: 0, y: 150))
  check(abs(osc.frame.minX - 16) < 0.51, "OSC may be manually dragged into a sidebar's area")
  let manual = osc.frame
  let manualIntent = osc.currentPosition
  controller.sidebars.bringPanelToFront(osc); pump()
  controller.sidebars.hideAllSideBars(animate: false); pump()
  check(osc.frame == manual && osc.currentPosition == manualIntent, "layer and visibility changes preserve a genuine manual placement")
  Preference.set(false, for: .disableAnimations)
  osc.resetPosition()
  check(osc.isReturningToDefault, "reset still uses the existing smooth motion")
  controller.sidebars.show(sidebar: .settings)
  check(controller.sidebars.isShowing(.settings), "sidebar opens immediately during OSC reset without deferral")
  pump(1.5)
  check(!osc.isReturningToDefault && osc.currentPosition == initialIntent && abs(osc.frame.minX - initial.minX) < 0.51,
        "reset completes at its default position through sidebar overlap")
  controller.sidebars.hideAllSideBars(animate: false); pump()
  osc.endWindowSession()
  controller.hideControlTimer?.invalidate()
  window.close()
}
