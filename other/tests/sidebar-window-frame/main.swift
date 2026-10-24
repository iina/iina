import Cocoa
import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS: \(message)")
}
var expectedFrame: NSRect?
if CommandLine.arguments.contains("--panel-depth-only") {
  print("Completed \(checks) native panel-depth checks.")
  exit(0)
}
var settlingSidebars: SidebarController?
var settlingUI: MainWindowController?
var settlingDuration: TimeInterval = 0.02
func settle(_ window: NSWindow, duration: TimeInterval? = nil) {
  let deadline = Date().addingTimeInterval(duration ?? settlingDuration)
  let transitionDeadline = deadline.addingTimeInterval(2)
  repeat {
    window.contentView?.layoutSubtreeIfNeeded()
    if let expectedFrame { precondition(window.frame == expectedFrame, "Window frame changed during sidebar animation") }
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
  } while Date() < deadline || (Date() < transitionDeadline &&
    ((settlingSidebars?.sideBars.contains { $0.animationState == .willShow || $0.animationState == .willHide } ?? false) ||
     settlingUI?.animationState == .willShow || settlingUI?.animationState == .willHide))
  window.contentView?.layoutSubtreeIfNeeded()
}
// The common header retains its geometry when a sidebar opens.
func descendants(_ view: NSView) -> [NSView] {
  view.subviews.flatMap { [$0] + descendants($0) }
}
// Advance only part of an animation so later requests can interrupt it.
func advanceSidebarAnimation(_ window: NSWindow, duration: TimeInterval) {
  let deadline = Date().addingTimeInterval(duration)
  repeat {
    window.contentView?.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
  } while Date() < deadline
}

if !CommandLine.arguments.contains("--osc-return-only") {
  runSeekPreviewHoverChecks()
  if CommandLine.arguments.contains("--seek-preview-only") {
    print("Completed \(checks) native seek-preview hover checks.")
    exit(0)
  }
}

if CommandLine.arguments.contains("--osc-return-only") {
  print("Completed \(checks) native concurrent OSC return checks.")
  exit(0)
}

// A queued correction must not access a released window controller, even when
// another owner retains its SidebarController through the next run-loop turn.
var retainedSidebars: SidebarController?
weak var releasedController: MainWindowController?
do {
  let controller = MainWindowController()
  releasedController = controller
  let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 900, height: 600),
                        styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  controller.window = window
  let content = window.contentView!
  controller.sidebars.installSubviews(in: content)
  let osc = controller.oscFloatingView
  content.addSubview(osc)
  osc.setupConstraints()
  osc.oscTopView.heightAnchor.constraint(equalToConstant: 24).isActive = true
  osc.oscBottomView.heightAnchor.constraint(equalToConstant: 28).isActive = true
  osc.updatePosition()
  retainedSidebars = controller.sidebars
  let panel = controller.sidebars.leadingSidebar
  panel.view.isHidden = false
  panel.view.setFrameOrigin(NSPoint(x: 1, y: 0))
  window.close()
}
check(releasedController == nil, "queued sidebar correction does not retain the window controller")
RunLoop.main.run(until: Date().addingTimeInterval(0.02))
check(releasedController == nil, "queued sidebar correction tolerates its released owner")
retainedSidebars = nil

for motion in ["disabled", "slide", "fade"] {
  AccessibilityPreferences.motionReductionEnabled = motion == "fade"
  Preference.values = [.disableAnimations: motion == "disabled", .playlistLeading: true,
                       .pluginsLeading: true]
  let controller = MainWindowController()
  let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 720, height: 405),
                        styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  controller.window = window
  let content = window.contentView!
  controller.titleBarView = ChromeFixture(minimumWidth: 180, titlebar: true)
  controller.oscBottomView = ChromeFixture(minimumWidth: 28, titlebar: false)
  content.addSubview(controller.titleBarView)
  controller.titleBarView.padding(.horizontal, .top)
  content.addSubview(controller.oscBottomView)
  controller.oscBottomView.padding(.horizontal, .bottom)
  controller.sidebars.installSubviews(in: content)
  settlingSidebars = controller.sidebars
  let leading = controller.sidebars.leadingSidebar
  let trailing = controller.sidebars.trailingSidebar
  controller.sidebars.show(sidebar: .settings)
  advanceSidebarAnimation(window, duration: 0.02)
  controller.sidebars.hideSideBar(side: .trailing)
  settle(window, duration: 0.32)
  check(trailing.status == .hidden && trailing.animationState == .hidden && trailing.view.isHidden,
        "hide during reveal reaches hidden state (\(motion))")
  check(trailing.view.subviews.isEmpty && trailing.view.alphaValue == 1,
        "interrupted reveal removes content and restores opacity (\(motion))")

  controller.sidebars.show(sidebar: .plugins)
  settle(window, duration: 0.32)
  controller.sidebars.hide(.plugins)
  advanceSidebarAnimation(window, duration: 0.02)
  controller.sidebars.show(sidebar: .plugins, force: true, hideIfAlreadyShown: false)
  settle(window, duration: 0.32)
  check(leading.status == .plugins && leading.animationState == .shown && !leading.view.isHidden,
        "forced reveal interrupts hide without losing selected panel (\(motion))")
  check(leading.view.alphaValue == 1 && leading.view.subviews.count == 1,
        "reopened panel restores visible opacity and content (\(motion))")
  controller.sidebars.hideAllSideBars(animate: false)
  settle(window)

  controller.sidebars.show(sidebar: .playlist)
  controller.sidebars.hideSideBar(side: .leading, animate: false)
  controller.sidebars.show(sidebar: .playlist, force: true, hideIfAlreadyShown: false)
  settle(window, duration: 0.32)
  check(leading.status == .playlist && leading.animationState == .shown && !leading.view.isHidden && leading.view.alphaValue == 1,
        "rapid show/hide/show ignores stale completions after nonanimated hide (\(motion))")
  controller.sidebars.hideAllSideBars(animate: false)
  settle(window)

  controller.sidebars.show(sidebar: .settings)
  controller.sidebars.show(sidebar: .playlist)
  controller.sidebars.hideAllSideBars(animate: false)
  settle(window, duration: 0.32)
  check(controller.sidebars.sideBars.allSatisfy {
    $0.status == .hidden && $0.animationState == .hidden && $0.view.isHidden && $0.view.subviews.isEmpty
  }, "both panels can hide immediately during reveal (\(motion))")

  controller.sidebars.show(sidebar: .plugins)
  advanceSidebarAnimation(window, duration: 0.02)
  Preference.set(false, for: .pluginsLeading)
  settle(window, duration: 0.32)
  check(leading.status == .hidden && leading.animationState == .hidden && leading.view.isHidden &&
        trailing.status == .plugins && trailing.animationState == .shown && !trailing.view.isHidden && trailing.view.alphaValue == 1,
        "side change during reveal leaves only the new side visible (\(motion))")
  controller.sidebars.hideAllSideBars(animate: false)
  settle(window)
  if motion != "disabled" {
    Preference.set(true, for: .pluginsLeading)
    controller.sidebars.show(sidebar: .plugins)
    controller.sidebars.show(sidebar: .playlist, force: true)
    settle(window, duration: 0.32)
    check(leading.status == .playlist && leading.animationState == .shown &&
          controller.sidebars.playlistView.view.isDescendant(of: leading.view),
          "reveal completion retains replacement content (\(motion))")
    controller.sidebars.hideAllSideBars(animate: false)
    settle(window)
  }
  settlingSidebars = nil
  window.close()
}
for motion in ["disabled", "slide", "fade"] {
  AccessibilityPreferences.motionReductionEnabled = motion == "fade"
  Preference.values = [.disableAnimations: motion == "disabled", .alwaysShowOnTopIcon: true,
                       .playlistLeading: true]
  let controller = MainWindowController()
  let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 720, height: 405),
                        styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.title = String(repeating: "A long movie title ", count: 12)
  controller.window = window
  let content = window.contentView!
  let header = Titlebar(mainWindow: controller)
  controller.titleBarView = header
  controller.oscBottomView = ChromeFixture(minimumWidth: 28, titlebar: false)
  content.addSubview(controller.oscBottomView)
  controller.oscBottomView.padding(.horizontal, .bottom)
  content.addSubview(header)
  header.padding(.horizontal)
  header.update(hasOSC: false, inFullScreen: false)
  controller.sidebars.installSubviews(in: content)
  settlingSidebars = controller.sidebars
  settle(window)
  expectedFrame = window.frame
  let title = descendants(header).compactMap { $0 as? NSTextField }.first!
  let buttons = descendants(header).compactMap { $0 as? NSButton }.filter { !$0.isHidden }
  let originalButtonFrames = buttons.map { content.convert($0.bounds, from: $0) }
  for kind in [SidebarController.ViewType.settings, .playlist] {
    controller.sidebars.show(sidebar: kind)
    settle(window, duration: motion == "disabled" ? 0.02 : 0.28)
    let panel = controller.sidebars.sideBars.first { $0.status == kind }!
    let frame = content.convert(title.bounds, from: title)
    let buttonFrames = buttons.map { content.convert($0.bounds, from: $0) }
    check(zip(buttonFrames, originalButtonFrames).allSatisfy { $0 == $1 },
          "header accessories stay fixed above sidebar (\(motion))")
    check(frame.minY >= panel.view.frame.minY && frame.maxY <= content.bounds.maxY,
          "title stays in shared header (\(motion))")
    check(title.frame.width < title.intrinsicContentSize.width, "long title truncates within shared header (\(motion))")
    controller.sidebars.hideAllSideBars(animate: false)
    settle(window)
    check(zip(buttons, originalButtonFrames).allSatisfy { abs(content.convert($0.0.bounds, from: $0.0).maxX - $0.1.maxX) < 0.001 },
          "header accessories return after hide (\(motion))")
  }
  expectedFrame = nil
  settlingSidebars = nil
  window.close()
}
AccessibilityPreferences.motionReductionEnabled = false
// Actual header + full-height panels must not leave a reserved strip when UI hides.
for hasOSC in [false, true] {
  let controller = MainWindowController()
  let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 720, height: 405),
                        styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  controller.window = window
  let content = window.contentView!
  let header = Titlebar(mainWindow: controller)
  controller.titleBarView = header
  controller.oscBottomView = ChromeFixture(minimumWidth: 28, titlebar: false)
  content.addSubview(controller.oscBottomView)
  controller.oscBottomView.padding(.horizontal, .bottom)
  content.addSubview(header)
  header.padding(.horizontal)
  header.update(hasOSC: hasOSC, inFullScreen: false)
  controller.sidebars.installSubviews(in: content)
  settlingSidebars = controller.sidebars
  Preference.values = [.edgeToEdgeVideo: true, .disableAnimations: true, .playlistLeading: true]
  settle(window)
  let original = window.frame
  expectedFrame = original
  for hidden in [true, false] {
    header.setRevealed(!hidden, animated: false)
    controller.sidebars.show(sidebar: .settings)
    controller.sidebars.show(sidebar: .playlist)
    settle(window)
    for panel in controller.sidebars.sideBars {
      check(abs(panel.view.frame.maxY - content.bounds.maxY) < 0.001 && abs(panel.view.frame.minY) < 0.001,
            "actual sidebar fills entire window despite hidden header (hidden=\(hidden), top OSC=\(hasOSC))")
    }
    check(window.frame == original, "actual header insets preserve native window frame (hidden=\(hidden), top OSC=\(hasOSC))")
    controller.sidebars.hideAllSideBars(animate: false)
    settle(window)
  }
  settlingSidebars = nil
  expectedFrame = nil
  window.close()
}
if !CommandLine.arguments.contains("--top-only") {
for edgeToEdge in [true, false] {
  for rtl in [false, true] {
    for glass in [false, true] {
      for motion in (CommandLine.arguments.contains("--no-animation") ? ["disabled"] : ["disabled", "slide", "fade"]) {
      expectedFrame = nil
      settlingDuration = motion == "disabled" ? 0.02 : 0.28
      AccessibilityPreferences.motionReductionEnabled = motion == "fade"
      Preference.values = [.edgeToEdgeVideo: edgeToEdge, .disableAnimations: motion == "disabled",
                           .useLiquidGlassSidebar: glass, .playlistLeading: true]
      let controller = MainWindowController()
      let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 390, height: 220),
                            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 390, height: 220)
      controller.window = window
      let content = window.contentView!
      let direction: NSUserInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
      content.userInterfaceLayoutDirection = direction
      controller.videoView.userInterfaceLayoutDirection = direction
      controller.videoViewContainer.userInterfaceLayoutDirection = direction
      let header = ChromeFixture(minimumWidth: 180, titlebar: true)
      controller.titleBarView = header
      controller.oscBottomView = ChromeFixture(minimumWidth: 28, titlebar: false)
      for (index, view) in [controller.titleBarView!, controller.oscBottomView!].enumerated() {
        view.userInterfaceLayoutDirection = direction
        content.addSubview(view)
        view.padding(.horizontal)
        if index == 0 { view.topAnchor.constraint(equalTo: content.topAnchor).isActive = true }
        else { view.bottomAnchor.constraint(equalTo: content.bottomAnchor).isActive = true }
      }
      content.addSubview(controller.videoViewContainer)
      controller.videoViewContainer.translatesAutoresizingMaskIntoConstraints = false
      controller.sidebars.installSubviews(in: content)
      settlingSidebars = controller.sidebars
      controller.sidebars.sideBars.forEach { $0.view.userInterfaceLayoutDirection = direction }
      controller.installVideoConstraints()
      for view in [controller.osdView, controller.additionalInfoView] {
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        view.widthAnchor.constraint(equalToConstant: 180).isActive = true
        view.heightAnchor.constraint(equalToConstant: 30).isActive = true
        view.isHidden = true
      }
      controller.installAccessoryConstraints()
      settle(window)
      let original = window.frame
      expectedFrame = original
      let label = "edge=\(edgeToEdge), RTL=\(rtl), glass=\(glass), motion=\(motion)"
      controller.sidebars.show(sidebar: .settings)
      settle(window)
      check(window.frame == original, "opening settings retains exact frame (\(label))")
      check(controller.sidebars.isShowing(.settings),
            "settings remains visible without reserving OSC space (\(label))")
      controller.sidebars.show(sidebar: .playlist)
      settle(window)
      for panel in controller.sidebars.sideBars {
        check(abs(panel.view.frame.maxY - content.bounds.maxY) < 0.001 && abs(panel.view.frame.minY) < 0.001,
              "sidebar fills the entire window height (\(label), \(panel.side))")
        check(content.subviews.firstIndex(of: panel.view)! < content.subviews.firstIndex(of: controller.titleBarView)!,
              "sidebar background stays below shared header (\(label), \(panel.side))")
        let handle = controller.sidebars.resizeHandleRect(for: panel.side)
        check(abs(handle.maxY - content.bounds.maxY) < 0.001,
              "sidebar resize handle spans full height (\(label), \(panel.side))")
      }
      check(window.frame == original, "two simultaneous sidebars retain exact frame (\(label))")
      controller.sidebars.hideAllSideBars(animate: false)
      settle(window)
      check(window.frame == original, "hiding both sidebars retains exact frame (\(label))")
      controller.sidebars.show(sidebar: .settings)
      settle(window)
      Preference.set(true, for: .settingsLeading)
      settle(window)
      check(window.frame == original, "switching configured sidebar side retains exact frame (\(label))")
      let panel = controller.sidebars.leadingSidebar
      check(panel.status == .settings, "settings moved to configured side (\(label))")
      controller.sidebars.resizingSidebarSide = .leading
      let event = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 1000, y: 100),
                                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
      check(controller.sidebars.handleMouseDragged(event), "sidebar resize routed (\(label))")
      settle(window)
      check(window.frame == original && panel.widthConstraint.constant <= content.bounds.width * 0.8,
            "sidebar resize retains frame and physical width cap (\(label))")
      controller.sidebars.resizingSidebarSide = nil
      controller.sidebars.hideAllSideBars(animate: false)
      settle(window)
      expectedFrame = nil
      settlingSidebars = nil
      window.close()
      }
    }
  }
}
}
expectedFrame = nil
settlingDuration = 0.02
for rtl in [false, true] {
  let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 390, height: 220),
                        styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  let content = window.contentView!
  let direction: NSUserInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
  content.userInterfaceLayoutDirection = direction
  let fixture = TopOSCFixture(direction: direction)
  content.addSubview(fixture)
  fixture.padding(.horizontal, .top)
  settle(window)
  check(fixture.oscView.frame.minX >= -0.001 && fixture.oscView.frame.maxX <= fixture.oscContainer.bounds.width + 0.001,
        "native top OSC stays within both physical container edges at 390pt (RTL=\(rtl))")
  check(abs(fixture.oscView.frame.width - 378) < 0.01,
        "native top OSC preserves full available width without sidebar (RTL=\(rtl))")
  check(!fixture.oscView.detachedViews.isEmpty,
        "native top OSC detaches secondary groups in minimum window (RTL=\(rtl))")
  check(fixture.oscSliderView.isDescendant(of: fixture.oscView),
        "native top OSC preserves required timeline group (RTL=\(rtl))")
  window.setContentSize(NSSize(width: 1000, height: 220))
  settle(window)
  check(fixture.oscView.detachedViews.isEmpty,
        "native top OSC restores secondary groups when window expands (RTL=\(rtl))")
  window.close()
}
class HeaderTrackingEvent: NSEvent {
  var area: NSTrackingArea?
  var point = NSPoint.zero
  override var locationInWindow: NSPoint { point }
  override var trackingArea: NSTrackingArea? { area }
}

// Real header, native window buttons and extracted production show/hide methods.
for reducedMotion in [false, true] {
  for disabled in [false, true] {
    Preference.values = [.enableControlBarAutoHide: true, .disableAnimations: disabled,
                         .edgeToEdgeVideo: true, .playlistLeading: true]
    AccessibilityPreferences.motionReductionEnabled = reducedMotion
    let controller = MainWindowController()
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 720, height: 405),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.toolbar = NSToolbar(); window.toolbarStyle = .unifiedCompact
    controller.window = window
    let content = window.contentView!
    content.wantsLayer = true
    let header = Titlebar(mainWindow: controller)
    controller.titleBarView = header
    controller.oscBottomView = ChromeFixture(minimumWidth: 28, titlebar: false)
    content.addSubview(controller.oscBottomView)
    controller.oscBottomView.padding(.horizontal, .bottom)
    content.addSubview(header); header.padding(.horizontal)
    header.update(hasOSC: false, inFullScreen: false)
    let nativeButtons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { window.standardWindowButton($0)! }
    let nativeHosts = nativeButtons.map { $0.superview! }
    let nativeActions = nativeButtons.map { $0.action }
    header.trackWindowButtons()
    controller.sidebars.installSubviews(in: content)
    settlingSidebars = controller.sidebars
    settlingUI = controller
    controller.installHeaderVisibility()
    let osc = NSView(frame: NSRect(x: 100, y: 16, width: 460, height: 80))
    content.addSubview(osc, positioned: .below, relativeTo: header)
    osc.isHidden = true
    osc.addSubview(controller.playSlider)
    controller.osdView.isHidden = true
    controller.fadeableViews.add(osc) { .auto }
    if let proxy = window.standardWindowButton(.documentIconButton) {
      controller.fadeableViews.add(proxy) { .auto }
    }
    controller.fadeableViews.update()
    controller.showUI()
    window.orderFrontRegardless()
    window.setTitleWithRepresentedFilename("/tmp/Header animation verification.mp4")
    content.layoutSubtreeIfNeeded()
    header.trackWindowButtons()
    controller.sidebars.show(sidebar: .settings)
    controller.sidebars.show(sidebar: .playlist)
    settle(window, duration: 0.3)
    let label = "reduced=\(reducedMotion), disabled=\(disabled)"
    check(!osc.isHidden && osc.alphaValue == 1, "initial show includes controls registered after header setup (\(label))")
    let shownHeight = header.frame.height
    let buttonFrames = nativeButtons.map { content.convert($0.bounds, from: $0) }
    check(header.tracksWindowButtons && zip(nativeButtons, nativeHosts).allSatisfy { $0.superview === $1 }, "native traffic lights keep AppKit hosts while following common header (\(label))")
    check(nativeButtons.map { $0.action } == nativeActions, "native window actions remain intact (\(label))")
    let framesBeforeHide = window.frame
    controller.hideUI(force: true)
    if !disabled {
      advanceSidebarAnimation(window, duration: 0.1)
      check(!header.isHidden && !osc.isHidden, "header and OSC remain present while hiding (\(label))")
      if !reducedMotion {
        check(header.frame.minY > content.bounds.maxY - shownHeight && header.frame.minY < content.bounds.maxY,
              "header slides upward through intermediate frames (\(label))")
        check(nativeButtons.allSatisfy {
          $0.alphaValue == 1 && $0.layer?.animation(forKey: "headerSlide") != nil &&
          abs($0.layer?.presentation()?.transform.m42 ?? 0) > 0 &&
          abs($0.layer?.presentation()?.transform.m42 ?? shownHeight) < shownHeight
        }, "native traffic lights follow the intermediate header slide (\(label))")
        check(header.alphaValue == 1 && (osc.layer?.presentation()?.opacity ?? 0) > 0 && (osc.layer?.presentation()?.opacity ?? 1) < 1,
              "header stays opaque while OSC fades (\(label))")
      }
    }
    settle(window, duration: 0.3)
    check(header.isHidden && osc.isHidden && controller.animationState == .hidden, "header and OSC finish hiding together (\(label))")
    if let proxy = window.standardWindowButton(.documentIconButton) {
      check(!proxy.isHidden && proxy.alphaValue < 1e-90, "native document proxy stays registered while hidden (\(label))")
    }
    check(nativeButtons.allSatisfy { $0.alphaValue < 1e-90 }, "traffic lights disappear with header (\(label))")
    check(controller.sidebars.quickSettingView.topConstraint.constant == 0 && controller.sidebars.playlistView.topConstraint.constant == 0,
          "both panel contents fill vacated header space (\(label))")
    controller.showUI()
    if !disabled && !reducedMotion {
      advanceSidebarAnimation(window, duration: 0.08)
      window.setTitleWithRepresentedFilename("/tmp/Native layout during reveal.mp4")
      header.trackWindowButtons()
      check(nativeButtons.allSatisfy {
        $0.alphaValue == 1 && $0.layer?.animation(forKey: "headerSlide") != nil
      }, "native relayout preserves the active button slide (\(label))")
    }
    settle(window, duration: 0.3)
    check(nativeButtons.allSatisfy { $0.alphaValue == 1 }, "traffic lights appear after reveal completion (\(label))")
    check(!header.isHidden && header.alphaValue == 1 && osc.alphaValue == 1 && controller.animationState == .shown,
          "header and OSC finish revealing together (\(label))")
    check(nativeButtons.map { content.convert($0.bounds, from: $0) } == buttonFrames,
          "native traffic lights return to identical coordinates (\(label))")
    check(controller.sidebars.quickSettingView.topConstraint.constant == shownHeight && controller.sidebars.playlistView.topConstraint.constant == shownHeight,
          "both panel contents reserve visible header height (\(label))")
    check(controller.sidebars.resizeHandleRect(for: .trailing).maxY == content.bounds.maxY - shownHeight,
          "sidebar resize handle excludes shared header (\(label))")
    if !disabled {
      controller.hideUI(force: true); advanceSidebarAnimation(window, duration: 0.05)
      controller.showUI(); advanceSidebarAnimation(window, duration: 0.05)
      controller.hideUI(force: true); advanceSidebarAnimation(window, duration: 0.16)
      check(controller.animationState == .willHide && !header.isHidden,
            "stale first hide cannot finish a newer hide (\(label))")
      controller.showUI(); settle(window, duration: 0.3)
      check(controller.animationState == .shown && !header.isHidden && header.alphaValue == 1,
            "rapid hide/show reversals settle visible (\(label))")
    }
    Preference.set(false, for: .enableControlBarAutoHide)
    controller.hideUI(); settle(window, duration: 0.3)
    check(controller.animationState == .shown && nativeButtons.allSatisfy { $0.alphaValue == 1 },
          "disabled auto-hide retains shared header and traffic lights (\(label))")
    controller.hideUI(force: true); settle(window, duration: 0.3)
    controller.player.disableUI = true; controller.showUI()
    check(controller.animationState == .hidden, "disabled UI cannot reveal shared header (\(label))")
    controller.player.disableUI = false; controller.showUI(); settle(window, duration: 0.3)
    Preference.set(true, for: .enableControlBarAutoHide)
    controller.pipStatus = .inPIP; controller.hideUI()
    check(controller.animationState == .shown, "PiP preserves existing UI hide guard (\(label))")
    controller.pipStatus = .notInPIP
    Preference.set(false, for: .edgeToEdgeVideo); Preference.set(true, for: .dockedControlBarAndTitlebar)
    controller.fadeableViews.update(); controller.hideUI(force: true); settle(window, duration: 0.3)
    check(!header.isHidden && nativeButtons.allSatisfy { $0.alphaValue == 1 } && osc.isHidden,
          "docked header remains visible while floating controls hide (\(label))")
    Preference.set(true, for: .edgeToEdgeVideo); controller.fadeableViews.update(); controller.showUI()
    settle(window, duration: 0.3)
    // Return the real AppKit buttons before fullscreen; reacquire after returning.
    header.update(hasOSC: false, inFullScreen: true)
    controller.fsState = .fullscreen; controller.fadeableViews.update()
    check(!header.tracksWindowButtons && zip(nativeButtons, nativeHosts).allSatisfy { $0.superview === $1 },
          "fullscreen returns native buttons to AppKit hosts (\(label))")
    check(header.isHidden && controller.sidebars.quickSettingView.topConstraint.constant == 0,
          "fullscreen without top OSC releases header inset (\(label))")
    header.update(hasOSC: true, inFullScreen: true); controller.oscPosition = .top
    controller.fadeableViews.update(); controller.showUI(); settle(window, duration: 0.3)
    check(!header.isHidden && header.frame.height == 42,
          "fullscreen top OSC reveals its own compact row (\(label))")
    header.update(hasOSC: false, inFullScreen: false); controller.fsState = .windowed
    header.trackWindowButtons(); controller.fadeableViews.update(); controller.showUI()
    settle(window, duration: 0.3)
    check(header.tracksWindowButtons && zip(nativeButtons, nativeHosts).allSatisfy { $0.superview === $1 },
          "windowed restore tracks original native buttons (\(label))")
    check(window.frame == framesBeforeHide, "shared header transitions never resize the window (\(label))")
    controller.hideUI()
    controller.hideUIAndCursor()
    settle(window, duration: 0.3)
    check(controller.animationState == .shown && !header.isHidden && !osc.isHidden,
          "two open sidebars prevent idle and mouse-exit hiding (\(label))")
    controller.updateTimer()
    check(controller.hideControlTimer == nil, "open panels suppress auto-hide timer (\(label))")
    controller.sidebars.hideSideBar(side: .leading)
    settle(window, duration: 0.3)
    controller.hideUI()
    check(controller.animationState == .shown && controller.hideControlTimer == nil,
          "closing one of two panels keeps header and OSC pinned (\(label))")
    controller.sidebars.hideSideBar(side: .trailing)
    if !disabled {
      advanceSidebarAnimation(window, duration: 0.08)
      controller.hideUI()
      check(controller.animationState == .shown && controller.hideControlTimer == nil,
            "last closing panel keeps UI visible until completion (\(label))")
    }
    settle(window, duration: 0.3)
    check(controller.hideControlTimer?.isValid == true,
          "closing last panel restarts the normal idle timeout (\(label))")
    controller.hideControlTimer?.fire()
    settle(window, duration: 0.3)
    check(controller.animationState == .hidden, "auto-hide resumes after last panel closes (\(label))")
    controller.sidebars.show(sidebar: .settings)
    settle(window, duration: 0.3)
    check(controller.animationState == .shown && !header.isHidden && !osc.isHidden && nativeButtons.allSatisfy { $0.alphaValue == 1 },
          "opening a panel reveals previously hidden header and OSC (\(label))")
    let hover = HeaderTrackingEvent()
    hover.area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways],
      owner: controller, userInfo: ["obj": 1])
    hover.point = controller.playSlider.convert(NSPoint(x: 200, y: 10), to: nil)
    controller.mouseEntered(with: hover)
    settle(window, duration: SeekPreviewHoverController.showDelay + 0.03)
    check(!controller.thumbnailPeekView.isHidden && !controller.timePreviewView.isHidden,
          "visible timeline can show seek previews (\(label))")
    controller.hideUIFromOSC()
    check(controller.thumbnailPeekView.isHidden && controller.timePreviewView.isHidden,
          "manual hide clears existing previews before animation (\(label))")
    controller.mouseEntered(with: hover)
    check(controller.thumbnailPeekView.isHidden && controller.timePreviewView.isHidden,
          "hiding timeline rejects new seek previews (\(label))")
    settle(window, duration: 0.3)
    controller.mouseEntered(with: hover)
    controller.mouseMoved(with: hover)
    check(controller.thumbnailPeekView.isHidden && controller.timePreviewView.isHidden,
          "invisible timeline hover cannot revive seek previews (\(label))")
    check(controller.animationState == .hidden && !controller.sidebars.trailingSidebar.view.isHidden,
          "explicit OSC hide preserves an open panel (\(label))")
    for point in [NSPoint(x: 100, y: 200), NSPoint(x: 650, y: 200), NSPoint(x: 350, y: 100)] {
      let movement = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
      controller.mouseMoved(with: movement)
    }
    settle(window, duration: 0.3)
    check(controller.animationState == .hidden && header.isHidden && osc.isHidden,
          "video and sidebar movement cannot undo explicit OSC hiding (\(label))")
    let menuEvent = HeaderTrackingEvent()
    menuEvent.area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways],
      owner: controller, userInfo: ["obj": 0])
    menuEvent.point = NSPoint(x: 100, y: 100)
    controller.mouseExited(with: menuEvent)
    controller.mouseEntered(with: menuEvent)
    settle(window, duration: 0.3)
    check(controller.animationState == .hidden && header.isHidden && osc.isHidden && controller.isMouseInWindow,
          "popup exit/entry inside player preserves manual hiding (\(label))")
    controller.trackPluginMenu {
      controller.isMouseInWindow = false
      controller.mouseEntered(with: menuEvent)
      controller.showUI()
    }
    settle(window, duration: 0.3)
    check(controller.animationState == .hidden && header.isHidden && osc.isHidden,
          "plugin menu tracking blocks re-entry and direct auto reveal (\(label))")
    menuEvent.point = NSPoint(x: -20, y: 100)
    controller.mouseExited(with: menuEvent)
    check(!controller.isMouseInWindow, "genuine pointer exit is tracked after manual hiding (\(label))")
    let entry = HeaderTrackingEvent()
    entry.area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways],
      owner: controller, userInfo: ["obj": 0])
    controller.mouseEntered(with: entry)
    settle(window, duration: 0.3)
    check(controller.animationState == .shown && controller.isMouseInWindow,
          "re-entering the player restores manually hidden controls (\(label))")
    controller.sidebars.show(sidebar: .playlist)
    settle(window, duration: 0.3)
    controller.hideUIFromOSC(); settle(window, duration: 0.3)
    controller.sidebars.hideSideBar(side: .leading, animate: false); settle(window)
    let movement = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 100, y: 200),
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, eventNumber: 42, clickCount: 0, pressure: 0)!
    controller.mouseMoved(with: movement); settle(window, duration: 0.3)
    check(controller.animationState == .hidden,
          "closing one of two panels preserves manual hiding (\(label))")
    controller.sidebars.hideSideBar(side: .trailing, animate: false); settle(window)
    check(controller.animationState == .shown,
          "closing last panel immediately reveals manually hidden UI (\(label))")
    controller.mouseMoved(with: movement); settle(window, duration: 0.3)
    check(controller.animationState == .shown,
          "first movement after last panel closes reveals UI (\(label))")
    controller.hideUIFromOSC(); settle(window, duration: 0.3)
    controller.mouseMoved(with: movement); settle(window, duration: 0.3)
    check(controller.animationState == .shown, "no-sidebar OSC miss resumes ordinary mouse reveal (\(label))")
    controller.hideUIFromOSC(); settle(window, duration: 0.3)
    let click = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 350, y: 200),
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, eventNumber: 43, clickCount: 1, pressure: 0)!
    controller.videoView.lastEventId = click.eventNumber
    check(controller.restoreUIFromVideoClick(click), "left video click consumes ordinary hiding (\(label))")
    settle(window, duration: 0.3)
    check(controller.animationState == .shown && !header.isHidden && !osc.isHidden,
          "left video click restores OSC and header (\(label))")
    check(!controller.restoreUIFromVideoClick(click), "ordinary clicks retain configured behavior (\(label))")
    controller.sidebars.show(sidebar: .settings); settle(window, duration: 0.3)
    controller.hideUIFromOSC(); settle(window, duration: 0.3)
    controller.restoreUIFromSidebarBackground(); settle(window, duration: 0.3)
    check(controller.animationState == .shown && controller.sidebars.isAnyVisible,
          "sidebar background restores OSC without closing panels (\(label))")
    controller.hideUIFromOSC(); settle(window, duration: 0.3)
    check(!controller.restoreUIFromVideoClick(click), "open panel takes priority over manual UI restore (\(label))")
    check(controller.sidebars.handleMouseUp(click), "video click dismisses open panels (\(label))")
    check(!controller.restoreUIFromVideoClick(click), "sidebar dismissal click cannot also restore UI (\(label))")
    settle(window, duration: 0.3)
    check(controller.animationState == .shown && !controller.sidebars.isAnyVisible,
          "left click closes panels and reveals UI (\(label))")
    check(!controller.restoreUIFromVideoClick(click), "last panel clears manual mode after revealing (\(label))")
    controller.mouseMoved(with: movement); settle(window, duration: 0.3)
    check(controller.animationState == .shown,
          "movement after click dismissal reveals OSC and header (\(label), state=\(controller.animationState), inside=\(controller.isMouseInWindow))")
    controller.hideUI(); settle(window, duration: 0.3)
    controller.mouseEntered(with: hover)
    check(controller.thumbnailPeekView.isHidden && controller.timePreviewView.isHidden,
          "auto-hidden timeline rejects seek previews (\(label))")
    controller.showUI(); settle(window, duration: 0.3)
    osc.isHidden = true
    controller.mouseEntered(with: hover)
    check(controller.thumbnailPeekView.isHidden && controller.timePreviewView.isHidden,
          "hidden slider ancestor rejects previews even with shown UI state (\(label))")
    controller.sidebars.hideAllSideBars(animate: false); settle(window)
    controller.hideControlTimer?.invalidate()
    header.restoreWindowButtons()
    window.close()
    settlingSidebars = nil
    settlingUI = nil
  }
}
AccessibilityPreferences.motionReductionEnabled = false
print("Completed \(checks) native sidebar-window-frame checks; player/sidebar content/chrome internals are fixtures.")
