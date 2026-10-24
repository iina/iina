import Cocoa

// Fixture boundaries only: the production constants, geometry parser, sizing
// extensions and controller methods are inserted by run.sh without reimplementing them.
enum Preference {
  enum OSCPosition { case floating, top, bottom }
  enum Key { case compactUI }
  static var unlockWindowAspectRatio = false
  static var compactUI = false
  static func bool(for key: Key) -> Bool { compactUI }
}
final class ToolbarSidebarStub {
  enum Status { case hidden, settings }
  final class Panel { var status: Status = .hidden }
  let leadingSidebar = Panel()
}
enum FullscreenState {
  case windowed, fullscreen
  var isFullscreen: Bool { self == .fullscreen }
}
struct InteractiveMode { var isActive = false }
final class LiveTextStub { func clearAnalysis() {} }
final class PlayerStub {
  var videoSizeForDisplay = (1920, 1080)
  func getGeometry() -> GeometryDef? { nil }
}
final class RecordingWindow: NSWindow {
  var requestedFrames: [NSRect] = []
  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    requestedFrames.append(frameRect)
    super.setFrame(frameRect, display: flag)
  }
  override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
    // Record the final requested rectangle without running an asynchronous animation.
    setFrame(frameRect, display: flag)
  }
}

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
  precondition(condition(), label)
  checks += 1
  print("PASS: \(label)")
}
func near(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 1) -> Bool { abs(a - b) < tolerance }

// PRODUCTION_CONSTANTS
let floatingMinimum = AppData.floatingOSCWindowMinSize
let dockedMinimum = AppData.mainWindowMinSize
// PRODUCTION_EXTENSIONS

final class MinimumWindowHarness {
  var window: NSWindow?
  var oscPosition: Preference.OSCPosition = .floating
  var fsState: FullscreenState = .windowed
  var interactiveMode = InteractiveMode()
  var loaded = true
  var windowResizeSession: WindowResizeSession?
  var isCropTransitionInProgress = false
  var isApplyingVideoTransformWindowFrame = false
  var isFullscreenTransitionInProgress = false
  let liveText = LiveTextStub()
  let player = PlayerStub()
  var cachedGeometry: GeometryDef?
  let videoViewContainer = NSView()
  let sidebars = ToolbarSidebarStub()
  // Floating layout is validated by the separate full native controls fixture.
  private func invalidateFloatingOSCLayout() {}

  // Only Smaller/Bigger menu commands are in this harness's behavioral scope.
  func setUserWindowFrame(_ frame: NSRect) { window!.setFrame(frame, display: true) }
  func setWindowScale(_ scale: Double) { fatalError("Unexpected fixed-scale menu command: \(scale)") }

var titleBarView: TitlebarFixture?
  func updateWindowButtonLayout() {}
  class TitlebarFixture { func restoreWindowButtons() {} }
  // PRODUCTION_CONTROLLER_METHODS

  func reset(size: NSSize, aspect: NSSize = NSSize(width: 16, height: 9)) -> RecordingWindow {
    let testWindow = RecordingWindow(contentRect: NSRect(origin: NSPoint(x: 250, y: 250), size: size),
                                     styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
    testWindow.isReleasedWhenClosed = false
    testWindow.aspectRatio = aspect
    testWindow.requestedFrames = []
    window = testWindow
    Preference.unlockWindowAspectRatio = false
    fsState = .windowed
    interactiveMode.isActive = false
    oscPosition = .floating
    return testWindow
  }

  func verify() {
    var w = reset(size: NSSize(width: 320, height: 180))
    let original = w.frame
    updateMinimumWindowSize()
    check(w.minSize == floatingMinimum, "floating mode installs native \(Int(floatingMinimum.width))x\(Int(floatingMinimum.height)) minimum")
    check(w.frame.width >= floatingMinimum.width && w.frame.height >= floatingMinimum.height, "switching to floating expands an undersized window")
    check(near(w.frame.midX, original.midX) && near(w.frame.midY, original.midY), "expansion preserves window center")
    check(near(w.frame.width / w.frame.height, 16 / 9, tolerance: 0.01), "locked expansion preserves aspect ratio")
    let grown = w.frame
    for docked: Preference.OSCPosition in [.top, .bottom] {
      oscPosition = docked
      w.requestedFrames = []
      updateMinimumWindowSize()
      check(w.minSize == dockedMinimum, "docked mode restores original native minimum")
      check(w.frame == grown && w.requestedFrames.isEmpty, "switching to docked never shrinks window")
    }

    w = reset(size: NSSize(width: 900, height: 600))
    let sufficient = w.frame
    updateMinimumWindowSize()
    check(w.frame == sufficient && w.requestedFrames.isEmpty, "sufficient floating window keeps its frame")

    for blockedMode in ["fullscreen", "interactive"] {
      w = reset(size: NSSize(width: 320, height: 180))
      let before = w.frame
      if blockedMode == "fullscreen" { fsState = .fullscreen } else { interactiveMode.isActive = true }
      updateMinimumWindowSize()
      check(w.minSize == floatingMinimum, "\(blockedMode) updates native limit")
      check(w.frame == before && w.requestedFrames.isEmpty, "\(blockedMode) does not force expansion, including native minSize setter")
    }

    w = reset(size: NSSize(width: 320, height: 180))
    fsState = .fullscreen
    updateMinimumWindowSize()
    fsState = .windowed
    updateMinimumWindowSize()
    check(w.frame.width >= floatingMinimum.width && w.frame.height >= floatingMinimum.height && !w.requestedFrames.isEmpty, "restored undersized frame expands after returning from fullscreen")

    let display = NSRect(x: -1440, y: 100, width: 1440, height: 900)
    for candidate in [NSRect(x: -1500, y: 0, width: 320, height: 180),
                      NSRect(x: -100, y: 950, width: 320, height: 180)] {
      let contained = windowFrameConstrainedToScreen(candidate, screenFrame: display)
      check(display.contains(contained), "edge expansion remains fully contained on offset display")
      check(contained.width >= floatingMinimum.width && contained.height >= floatingMinimum.height, "edge containment retains both floating minima")
    }
    let wide = windowFrameConstrainedToScreen(NSRect(x: -1400, y: 200, width: floatingMinimum.height * 8, height: floatingMinimum.height), screenFrame: display)
    check(wide.width <= 1440 && wide.height >= floatingMinimum.height && display.contains(wide), "8:1 video keeps minimum height without exceeding 1440x900 display")
    let tall = windowFrameConstrainedToScreen(NSRect(x: -1400, y: 200, width: floatingMinimum.width, height: floatingMinimum.width * 8), screenFrame: display)
    check(tall.width >= floatingMinimum.width && tall.height <= 900 && display.contains(tall), "1:8 video keeps minimum width without exceeding display")
    let tinyDisplay = NSRect(x: 500, y: -100, width: 200, height: 100)
    let tiny = windowFrameConstrainedToScreen(NSRect(x: 400, y: -200, width: floatingMinimum.height * 8, height: floatingMinimum.height), screenFrame: tinyDisplay)
    check(tiny.size == tinyDisplay.size && tinyDisplay.contains(tiny), "physical display wins when floating minimum cannot fit")
    let unclamped = NSRect(x: 10, y: 20, width: 300, height: 100)
    check(windowFrameConstrainedToScreen(unclamped, screenFrame: nil) == unclamped, "missing screen preserves candidate frame")
    oscPosition = .bottom
    let dockedWide = windowFrameConstrainedToScreen(NSRect(x: -1400, y: 200, width: floatingMinimum.height * 8, height: floatingMinimum.height), screenFrame: display)
    check(dockedWide.height < floatingMinimum.height && display.contains(dockedWide), "docked containment keeps original aspect without floating reexpansion")

    w = reset(size: NSSize(width: 600, height: 300))
    Preference.unlockWindowAspectRatio = true
    videoViewContainer.frame = NSRect(origin: .zero, size: w.frame.size)
    player.videoSizeForDisplay = (8, 1)
    removeVideoViewBlackBars()
    check(w.frame.width >= floatingMinimum.width && w.frame.height >= floatingMinimum.height, "Fit Window to Video crop cannot shrink below floating minimum")
    check(!w.requestedFrames.isEmpty && w.requestedFrames.last!.height >= floatingMinimum.height, "fit-video production method requests a clamped final frame")

    let smaller = NSMenuItem()
    smaller.tag = 10
    let bigger = NSMenuItem()
    bigger.tag = 11
    w = reset(size: NSSize(width: 600, height: 337.5))
    updateMinimumWindowSize()
    for _ in 0..<30 {
      menuChangeWindowSize(smaller)
      precondition(w.frame.width >= floatingMinimum.width && w.frame.height >= floatingMinimum.height, "Repeated Smaller crossed floating minimum")
    }
    check(w.frame.width >= floatingMinimum.width && w.frame.height >= floatingMinimum.height, "30 Smaller menu commands cannot bypass floating minimum")
    let beforeBigger = w.frame
    menuChangeWindowSize(bigger)
    check(near(w.frame.width, beforeBigger.width + 25) && w.frame.height > beforeBigger.height, "Bigger menu grows window by its 25pt width step")
    check(w.requestedFrames.allSatisfy { $0.width.isFinite && $0.height.isFinite }, "locked menu requests remain finite")

    w = reset(size: NSSize(width: 600, height: 337.5))
    oscPosition = .bottom
    updateMinimumWindowSize()
    for _ in 0..<30 { menuChangeWindowSize(smaller) }
    check(w.frame.width >= dockedMinimum.width && w.frame.width < floatingMinimum.width && w.frame.height >= dockedMinimum.height, "docked Smaller commands retain legacy smaller window range")

    w = reset(size: NSSize(width: 600, height: 300))
    Preference.unlockWindowAspectRatio = true
    w.aspectRatio = .zero
    updateMinimumWindowSize()
    for _ in 0..<30 {
      menuChangeWindowSize(smaller)
      precondition(w.frame.width.isFinite && w.frame.height.isFinite, "Unlocked Smaller produced invalid dimensions")
      precondition(w.frame.width >= floatingMinimum.width && w.frame.height >= floatingMinimum.height, "Unlocked Smaller crossed minimum")
    }
    menuChangeWindowSize(bigger)
    check(w.frame.width >= floatingMinimum.width && w.frame.height >= floatingMinimum.height && w.requestedFrames.allSatisfy { $0.width.isFinite && $0.height.isFinite }, "unlocked Smaller/Bigger handles native zero aspect without NaN or undersizing")
    let beforeFullscreenMenu = w.frame
    w.requestedFrames = []
    fsState = .fullscreen
    menuChangeWindowSize(smaller)
    check(w.frame == beforeFullscreenMenu && w.requestedFrames.isEmpty, "Smaller menu leaves fullscreen untouched")

    w = reset(size: NSSize(width: 600, height: 180))
    Preference.unlockWindowAspectRatio = true
    let unlockedOriginal = w.frame
    updateMinimumWindowSize()
    check(w.frame.width == 600 && w.frame.height == floatingMinimum.height, "unlocked mode clamps only undersized height")
    check(near(w.frame.midX, unlockedOriginal.midX) && near(w.frame.midY, unlockedOriginal.midY), "unlocked expansion preserves center")
    w = reset(size: NSSize(width: 320, height: 600))
    Preference.unlockWindowAspectRatio = true
    updateMinimumWindowSize()
    check(w.frame.width == floatingMinimum.width && w.frame.height == 600, "unlocked mode clamps only undersized width")

    w = reset(size: NSSize(width: 900, height: 600))
    let clamped = windowWillResize(w, to: NSSize(width: 300, height: 100))
    check(clamped.width >= floatingMinimum.width && clamped.height >= floatingMinimum.height, "resize delegate enforces floating limits")
    check(near(clamped.width / clamped.height, 16 / 9, tolerance: 0.001), "resize delegate preserves locked aspect")
    Preference.unlockWindowAspectRatio = true
    check(windowWillResize(w, to: NSSize(width: 600, height: 100)) == NSSize(width: 600, height: floatingMinimum.height), "unlocked resize delegate preserves sufficient width")
    check(windowWillResize(w, to: NSSize(width: 100, height: 600)) == NSSize(width: floatingMinimum.width, height: 600), "unlocked resize delegate preserves sufficient height")
    interactiveMode.isActive = true
    check(windowWillResize(w, to: NSSize(width: 100, height: 100)) == floatingMinimum, "interactive resize respects the player minimum")
    check(windowWillResize(w, to: NSSize(width: 600, height: 225)) == NSSize(width: 600, height: 225), "interactive resize permits a wide window")
    check(windowWillResize(w, to: NSSize(width: 400, height: 700)) == NSSize(width: 400, height: 700), "interactive resize permits a tall window")
    Preference.unlockWindowAspectRatio = false
    let lockedInteractive = windowWillResize(w, to: NSSize(width: 100, height: 100))
    check(near(lockedInteractive.width / lockedInteractive.height, 16 / 9, tolerance: 0.001),
          "interactive minimum resizing respects Lock Window Aspect Ratio")
    interactiveMode.isActive = false
    Preference.unlockWindowAspectRatio = true
    oscPosition = .top
    check(windowWillResize(w, to: NSSize(width: 100, height: 100)) == dockedMinimum, "docked resize keeps original limits")

    guard let screen = NSScreen.main else { fatalError("Native geometry test needs an available screen") }
    Preference.unlockWindowAspectRatio = false
    oscPosition = .floating
    for raw in ["100", "x100", "100x100", "1%", "x1%", "1%x1%"] {
      cachedGeometry = GeometryDef.parse(raw)
      let frame = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
      check(frame.width >= floatingMinimum.width && frame.height >= floatingMinimum.height, "startup geometry \(raw) satisfies both floating minima")
      check(near(frame.width / frame.height, 16 / 9, tolerance: 0.001), "startup geometry \(raw) preserves video aspect")
      check(near(frame.midX, screen.visibleFrame.midX) && near(frame.midY, screen.visibleFrame.midY), "startup geometry \(raw) centers after final clamp")
    }
    cachedGeometry = GeometryDef.parse("100x900")
    let both = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
    check(both.height == 900 && both.width == floatingMinimum.width, "both explicit axes are respected while enforcing the minimum width")
    Preference.unlockWindowAspectRatio = true
    cachedGeometry = GeometryDef.parse("600x900+50%-50%")
    let free = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
    check(free.size == NSSize(width: 600, height: 900) && near(free.midX, screen.visibleFrame.midX) && near(free.midY, screen.visibleFrame.midY),
          "unlocked startup geometry applies both dimensions and centers the resulting shape")
    cachedGeometry = GeometryDef.parse("50%x300-20-30")
    let mixed = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
    check(near(mixed.width, screen.visibleFrame.width / 2) && mixed.height == 300 &&
          near(mixed.maxX, screen.visibleFrame.maxX - 20) && near(mixed.maxY, screen.visibleFrame.maxY - 30),
          "unlocked startup uses mixed size units and resolves edges after both axes")
    cachedGeometry = GeometryDef.parse("100x600")
    let minimumFree = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
    check(minimumFree.size == NSSize(width: floatingMinimum.width, height: 600), "unlocked startup expands only an undersized axis")
    cachedGeometry = GeometryDef.parse("100000x500")
    let maximumFree = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
    check(maximumFree.size == NSSize(width: screen.visibleFrame.width, height: 500),
          "oversized free width fits the display without shrinking the independent height")
    cachedGeometry = GeometryDef.parse("600")
    let legacy = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
    check(near(legacy.width / legacy.height, 16 / 9, tolerance: 0.001), "unlocked legacy single-axis geometry still derives media aspect")
    Preference.unlockWindowAspectRatio = false
    cachedGeometry = GeometryDef.parse("100-20-30")
    let offset = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
    check(near(offset.maxX, screen.visibleFrame.maxX - 20) && near(offset.maxY, screen.visibleFrame.maxY - 30), "geometry edge offsets use final expanded dimensions")
    for aspect in [NSSize(width: 1, height: 8), NSSize(width: 8, height: 1)] {
      cachedGeometry = GeometryDef.parse("100000+50%-50%")
      let centered = windowFrameConstrainedToScreen(windowFrameFromGeometry(newSize: aspect, screen: screen)!,
                                                    screenFrame: screen.visibleFrame)
      check(near(centered.midX, screen.visibleFrame.midX) && near(centered.midY, screen.visibleFrame.midY),
            "oversized extreme-aspect geometry remains centered after fitting the screen")
      cachedGeometry = GeometryDef.parse("100000-20-30")
      let edged = windowFrameConstrainedToScreen(windowFrameFromGeometry(newSize: aspect, screen: screen)!,
                                                 screenFrame: screen.visibleFrame)
      check(near(edged.maxX, screen.visibleFrame.maxX - min(20, screen.visibleFrame.width - edged.width)) &&
            near(edged.maxY, screen.visibleFrame.maxY - min(30, screen.visibleFrame.height - edged.height)),
            "oversized extreme-aspect geometry retains requested edge gaps where space allows")
      check(edged.width >= min(floatingMinimum.width, screen.visibleFrame.width) &&
            edged.height >= min(floatingMinimum.height, screen.visibleFrame.height),
            "fitting geometry before its anchors preserves both floating minimum axes")
    }
    oscPosition = .bottom
    cachedGeometry = GeometryDef.parse("100")
    let dockedFrame = windowFrameFromGeometry(newSize: NSSize(width: 1920, height: 1080), screen: screen)!
    check(near(dockedFrame.width, dockedMinimum.width) && dockedFrame.height >= dockedMinimum.height && dockedFrame.height < floatingMinimum.height, "docked startup geometry retains original minimum")
    verifyNativeToolbarMinimum()
    print("\(checks) production native minimum-window checks passed")
  }

  func verifyNativeToolbarMinimum() {
    for unlocked in [false, true] {
      let native = RecordingWindow(contentRect: NSRect(x: 100, y: 100, width: floatingMinimum.width + 2, height: floatingMinimum.height),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                   backing: .buffered, defer: false)
      native.isReleasedWhenClosed = false
      native.titlebarAppearsTransparent = true
      native.aspectRatio = unlocked ? .zero : NSSize(width: 16, height: 9)
      window = native
      oscPosition = .floating
      fsState = .windowed
      interactiveMode.isActive = false
      Preference.unlockWindowAspectRatio = unlocked
      Preference.compactUI = false
      sidebars.leadingSidebar.status = .hidden
      let original = native.frame
      applyNativeMinimumWindowSize()
      setWindowToolbar()
      check(native.minSize == floatingMinimum && native.contentMinSize == floatingMinimum, "actual titled full-size window has exact floating minimum with toolbar")
      check(native.frame == original && native.toolbarStyle == .unifiedCompact, "compact toolbar creation preserves minimum-plus-2pt frame")
      let existing = native.toolbar!
      for _ in 0..<10 { setWindowToolbar() }
      check(native.toolbar === existing && native.frame == original, "repeated right-sidebar toolbar callbacks reuse native instance and preserve exact frame")
      sidebars.leadingSidebar.status = .settings
      setWindowToolbar()
      check(native.toolbar === existing && native.toolbarStyle == .unifiedCompact && native.frame == original, "leading sidebar preserves compact toolbar, instance and frame")
      check(native.minSize == floatingMinimum, "unified toolbar does not add native minimum height")
      sidebars.leadingSidebar.status = .hidden
      setWindowToolbar()
      check(native.toolbar === existing && native.toolbarStyle == .unifiedCompact && native.frame == original, "closing leading sidebar retains compact style without window growth")
      Preference.compactUI = true
      setWindowToolbar()
      check(native.toolbar == nil && native.frame == original && native.minSize == floatingMinimum, "removing toolbar preserves exact frame and native minimum")
      Preference.compactUI = false
      setWindowToolbar()
      check(native.toolbar != nil && native.toolbar !== existing && native.frame == original, "restoring missing toolbar preserves frame")
      updateMinimumWindowSize()
      check(native.frame == original && native.minSize == floatingMinimum, "minimum refresh retains toolbar-independent \(Int(floatingMinimum.width))x\(Int(floatingMinimum.height)) limit")
      oscPosition = .bottom
      updateMinimumWindowSize()
      check(native.frame == original && native.minSize == dockedMinimum, "docked native minimum remains exact with actual toolbar")
      fsState = .fullscreen
      setWindowToolbar()
      check(native.toolbar == nil && native.frame == original, "fullscreen toolbar removal never forces the window frame")
    }
    Preference.compactUI = false
  }
}
MinimumWindowHarness().verify()
