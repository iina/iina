import Cocoa
import Darwin
setbuf(stdout, nil)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let verifyingFreshProcess = CommandLine.arguments.contains("--verify-persistence")
if !verifyingFreshProcess {
  Preference.Key.allCases.forEach { Preference.defaults.removeObject(forKey: $0.rawValue) }
  // Old persisted manual placement must no longer override the saved default.
  Preference.set(FloatingOSCPosition.percentages(0, 1).dictionary, for: .controlBarCurrentPlacement)
  Preference.set(true, for: .controlBarPositionIsUserDefined)
  // Geometry/input checks below deliberately use immediate motion.
  Preference.set(true, for: .disableAnimations)
}
let controller = MainWindowController()
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
final class LayoutCountingContentView: EventSinkView {
  var layoutRequests = 0
  override func layoutSubtreeIfNeeded() {
    layoutRequests += 1
    super.layoutSubtreeIfNeeded()
  }
}
let video = LayoutCountingContentView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
window.contentView = video
controller.window = window
controller.videoViewContainer = video
window.orderFrontRegardless()
let osc = OSCFloatingView(mainWindow: controller)
video.addSubview(osc)
osc.setupConstraints()
// Native wrapper constraints and deterministic row heights replace the player
// controls. The scale callback adjusts these heights just as real controls do.
controller.topRowHeight = osc.oscTopView.heightAnchor.constraint(equalToConstant: 45)
controller.bottomRowHeight = osc.oscBottomView.heightAnchor.constraint(equalToConstant: 35)
controller.topRowHeight!.isActive = true
controller.bottomRowHeight!.isActive = true
func position(animated: Bool = false) {
  osc.updatePosition(animated: animated)
  video.layoutSubtreeIfNeeded()
}
position()

let xConstraint = video.constraints.first {
  $0.firstItem as? NSView === osc && $0.firstAttribute == .centerX
}!
let yConstraint = video.constraints.first {
  $0.secondItem as? NSView === osc && $0.secondAttribute == .bottom && $0.relation == .equal
}!
var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  count += 1
  print("PASS: \(message)")
}
func near(_ actual: CGFloat, _ expected: CGFloat) -> Bool { abs(actual - expected) < 0.01 }
func event(_ type: NSEvent.EventType, point: NSPoint, clicks: Int = 2) -> NSEvent {
  NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: count, clickCount: clicks, pressure: 1)!
}

func backgroundPoint() -> NSPoint {
  video.layoutSubtreeIfNeeded()
  return osc.convert(NSPoint(x: 4, y: osc.bounds.height - 4), to: nil)
}
func dragTo(_ origin: CGPoint) {
  osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint(), clicks: 1))
  guard let offset = osc.mousePosRelatedToView else { preconditionFailure("Missing drag offset") }
  let point = CGPoint(x: origin.x + offset.x, y: origin.y + offset.y)
  osc.mouseDragged(with: event(.leftMouseDragged, point: point, clicks: 1))
  osc.mouseUp(with: event(.leftMouseUp, point: point, clicks: 1))
}
let header = NSView()
video.addSubview(header)
controller.titleBarView = header
func resize(_ size: NSSize) {
  window.setContentSize(size)
  video.frame.size = size
  header.frame = NSRect(x: 0, y: size.height - 40, width: size.width, height: 40)
  position()
}
func hasPendingLayout(_ view: NSView) -> Bool {
  view.needsLayout || view.needsUpdateConstraints || view.subviews.contains { hasPendingLayout($0) }
}
func setNativeFrame(_ requestedSize: NSSize) -> NSSize {
  window.setFrame(NSRect(origin: window.frame.origin, size: requestedSize), display: true)
  let actual = video.bounds.size
  header.frame = NSRect(x: 0, y: actual.height - 40, width: actual.width, height: 40)
  return actual
}
func invalidateCompletionControls() {
  // MainWindowController invalidates its floating controls before the final
  // normal position update. This fixture replaces those controls with this row.
  osc.oscTopView.needsUpdateConstraints = true
  osc.oscTopView.needsLayout = true
}
func checkRoundedPreparedResize(_ requested: NSSize) {
  // Use actual NSWindow rounding, without assigning a fractional content frame.
  resize(NSSize(width: 1000, height: 600))
  let expectedSize = setNativeFrame(requested)
  invalidateCompletionControls()
  position()
  let firstImmediate = osc.frame
  invalidateCompletionControls()
  position()
  // A repeated ordinary update can round an anchored row's height by one
  // backing pixel even without preparation; use the settled normal reference.
  check(abs(osc.frame.minX - firstImmediate.minX) <= 0.51 &&
        abs(osc.frame.minY - firstImmediate.minY) <= 0.51 &&
        abs(osc.frame.width - firstImmediate.width) <= 0.51 &&
        abs(osc.frame.height - firstImmediate.height) <= 0.51,
        "ordinary native position updates converge within one backing pixel at unchanged actual size")
  let immediate = osc.frame
  let immediateScale = controller.floatingOSCScale
  let intent = osc.currentPosition

  resize(NSSize(width: 1000, height: 600))
  osc.prepareForResize(to: requested)
  let preparedScale = controller.floatingOSCScale
  let actual = setNativeFrame(requested)
  video.layoutSubtreeIfNeeded()
  check(actual == expectedSize && abs(actual.width - requested.width) <= 1 &&
        abs(actual.height - requested.height) <= 1 && actual != requested,
        "native window applies the verified one-point rounding bound to fractional resize")
  check(!video.needsLayout && !video.needsUpdateConstraints && !hasPendingLayout(osc),
        "prepared native window layout has actually cleared parent and OSC descendant dirty flags")
  let expectedPlacement = FloatingOSCPlacement.frame(position: intent!, size: osc.frame.size,
    contentSize: actual, titlebarBottom: header.frame.minY + 1)
  let measuredRequests = video.layoutRequests
  osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
  check(video.layoutRequests == measuredRequests && controller.floatingOSCScale == preparedScale &&
        !hasPendingLayout(osc),
        "rounded prepared placement reuses measured metrics without redirtying controls or premeasuring")
  check(near(xConstraint.constant, expectedPlacement.midX) && near(yConstraint.constant, expectedPlacement.minY),
        "rounded prepared placement uses actual measured panel dimensions and content bounds for unit and edge clamping")
  video.layoutSubtreeIfNeeded()
  check(abs(osc.frame.minX - immediate.minX) <= 1.01 && abs(osc.frame.minY - immediate.minY) <= 1.01 &&
        abs(osc.frame.width - immediate.width) <= 1.01 && abs(osc.frame.height - immediate.height) <= 1.01 &&
        osc.currentPosition == intent,
        "rounded prepared placement stays within one native point of immediate geometry and preserves intent")
  invalidateCompletionControls()
  position()
  let preferredWidth = osc.constraints.first {
    $0.firstAttribute == .width && $0.secondItem == nil && $0.priority.rawValue == 300
  }!
  check(controller.floatingOSCScale == immediateScale &&
        preferredWidth.constant == FloatingOSCMetrics.preferredWidth * immediateScale &&
        controller.topRowHeight!.constant == 45 * immediateScale &&
        controller.bottomRowHeight!.constant == 35 * immediateScale && osc.currentPosition == intent &&
        osc.frame == immediate,
        "normal completion restores exact actual-size metrics and settled immediate native geometry")
  let consumedRequests = video.layoutRequests
  osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
  check(video.layoutRequests > consumedRequests,
        "a consumed preparation cannot suppress measurement on a later placement attempt")
  video.layoutSubtreeIfNeeded()
}
let sizes = [NSSize(width: 1000, height: 600), NSSize(width: 400, height: 225),
             NSSize(width: 1512, height: 982), NSSize(width: 1920, height: 1080),
             NSSize(width: 2560, height: 1080), NSSize(width: 800, height: 800)]
if verifyingFreshProcess {
  check(osc.currentPosition == Preference.floatingOSCDefaultPosition && osc.currentPosition == .initial,
        "a second process starts from saved default and ignores old manual placement")
  check(abs(osc.frame.minY - 16) <= 0.51, "fresh process starts sixteen points from bottom")
  exit(0)
}
check(osc.currentPosition == .initial, "untouched legacy initial position migrates to fixed factory gap")
for size in sizes {
  resize(size)
  check(abs(osc.frame.minY - 16) <= 0.51 && abs(osc.frame.midX - size.width / 2) <= 0.51,
        "untouched initial position stays centered sixteen points above bottom through resize")
}
// The crop tick owns the final layout, while the OSC still measures its new
// native dimensions before computing placement. Compare with immediate layout
// across changing scales, constant-scale minimum widths and portrait content.
for size in [NSSize(width: 900, height: 500), NSSize(width: 450, height: 250),
             NSSize(width: 420, height: 225), NSSize(width: 400, height: 225),
             NSSize(width: 405, height: 225), NSSize(width: 600, height: 400),
             NSSize(width: 400, height: 800)] {
  resize(size)
  let immediate = osc.frame
  let immediateScale = controller.floatingOSCScale
  let intent = osc.currentPosition
  resize(NSSize(width: 1000, height: 600))
  window.setContentSize(size)
  video.frame.size = size
  header.frame = NSRect(x: 0, y: size.height - 40, width: size.width, height: 40)
  osc.updatePosition(deferringFinalLayout: true)
  check(video.needsLayout, "crop placement leaves its final layout to the owning geometry tick")
  video.layoutSubtreeIfNeeded()
  check(abs(osc.frame.minX - immediate.minX) <= 0.51 && abs(osc.frame.minY - immediate.minY) <= 0.51 &&
        abs(osc.frame.width - immediate.width) <= 0.51 && abs(osc.frame.height - immediate.height) <= 0.51,
        "batched crop placement matches immediate native OSC geometry")
  check(controller.floatingOSCScale == immediateScale && osc.currentPosition == intent,
        "batched crop placement preserves adaptive scale and placement intent")

  resize(NSSize(width: 1000, height: 600))
  osc.prepareForResize(to: size)
  window.setContentSize(size)
  video.frame.size = size
  header.frame = NSRect(x: 0, y: size.height - 40, width: size.width, height: 40)
  // Represent the layout performed by AppKit during setFrame(display: true).
  video.layoutSubtreeIfNeeded()
  let measuredRequests = video.layoutRequests
  osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
  check(video.layoutRequests == measuredRequests,
        "prepared resize reuses settled native dimensions without another whole-content measurement")
  video.layoutSubtreeIfNeeded()
  check(abs(osc.frame.minX - immediate.minX) <= 0.51 && abs(osc.frame.minY - immediate.minY) <= 0.51 &&
        abs(osc.frame.width - immediate.width) <= 0.51 && abs(osc.frame.height - immediate.height) <= 0.51 &&
        controller.floatingOSCScale == immediateScale && osc.currentPosition == intent,
        "prepared minimum, scale-floor and portrait resize matches immediate native geometry and placement")

  // Unchanged metrics cannot suppress a genuinely dirty anchored child.
  osc.oscTopView.needsLayout = true
  let dirtyRequests = video.layoutRequests
  osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
  check(video.layoutRequests > dirtyRequests,
        "prepared resize still measures dirty anchored controls at unchanged scale")
  video.layoutSubtreeIfNeeded()

  // AppKit may constrain a proposed frame to a different actual content size.
  osc.prepareForResize(to: immediateScale == FloatingOSCScale.minimum
    ? NSSize(width: 1500, height: 1000) : NSSize(width: 400, height: 225))
  let correctedRequests = video.layoutRequests
  osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
  check(video.layoutRequests > correctedRequests && controller.floatingOSCScale == immediateScale,
        "actual size metrics override an incorrect prediction before measuring placement")
  video.layoutSubtreeIfNeeded()
}
var preparedStyles: [TranslucentView.Style] = [.visualEffect]
if #available(macOS 26, *) { preparedStyles.append(.liquidGlass) }
for style in preparedStyles {
  osc.setStyle(style)
  for compact in [false, true] {
    Preference.set(compact, for: .compactUI)
    for requested in [NSSize(width: 774.1865, height: 435.4803),
                      NSSize(width: 721.1285, height: 407.1865),
                      NSSize(width: 400.1865, height: 225.4803),
                      NSSize(width: 400.1865, height: 800.4803)] {
      checkRoundedPreparedResize(requested)
    }
  }
}
Preference.set(false, for: .compactUI)
resize(NSSize(width: 775, height: 436))
func prepareSettledMetrics(_ predicted: NSSize = NSSize(width: 774.1865, height: 435.4803)) {
  osc.prepareForResize(to: predicted)
  video.layoutSubtreeIfNeeded()
}
// These fallbacks start with a real, otherwise reusable preparation.
prepareSettledMetrics()
osc.oscTopView.needsLayout = true
let dirtyPreparedRequests = video.layoutRequests
osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
check(video.layoutRequests > dirtyPreparedRequests &&
      controller.floatingOSCScale == FloatingOSCScale.factor(for: video.bounds.size),
      "dirty OSC child forces exact metrics and measurement even with a matching prepared token")
video.layoutSubtreeIfNeeded()
prepareSettledMetrics()
let parentWidth = osc.widthAnchor.constraint(equalTo: video.widthAnchor, multiplier: 0.4)
parentWidth.priority = .init(500)
parentWidth.isActive = true
video.needsUpdateConstraints = true
let parentPreparedRequests = video.layoutRequests
osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
check(video.layoutRequests > parentPreparedRequests && abs(osc.frame.width - video.bounds.width * 0.4) <= 0.51,
      "dirty parent constraints force measurement of the actually assigned panel width")
parentWidth.isActive = false
position()
prepareSettledMetrics()
osc.setStyle(osc.style, force: true)
video.layoutSubtreeIfNeeded()
let rebuiltStyleRequests = video.layoutRequests
osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
check(video.layoutRequests > rebuiltStyleRequests,
      "a rebuilt native wrapper invalidates preparation even when its style and dirty flags match")
video.layoutSubtreeIfNeeded()
prepareSettledMetrics()
Preference.set(true, for: .compactUI)
let compactPreparedRequests = video.layoutRequests
osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
check(video.layoutRequests > compactPreparedRequests,
      "changed compact inputs invalidate prepared metrics before measuring native placement")
video.layoutSubtreeIfNeeded()
Preference.set(false, for: .compactUI)
position()
prepareSettledMetrics()
position()
let normalConsumedRequests = video.layoutRequests
osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
check(video.layoutRequests > normalConsumedRequests,
      "a normal update consumes an unused preparation before a later owned resize attempt")
video.layoutSubtreeIfNeeded()
prepareSettledMetrics()
osc.isDragging = true
osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
osc.isDragging = false
let guardedConsumedRequests = video.layoutRequests
osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
check(video.layoutRequests > guardedConsumedRequests,
      "a guarded placement attempt consumes preparation instead of leaking it into a later update")
video.layoutSubtreeIfNeeded()
prepareSettledMetrics(NSSize(width: 773.9, height: 435.4803))
let outsideBoundRequests = video.layoutRequests
osc.updatePosition(deferringFinalLayout: true, afterPreparedResize: true)
check(video.layoutRequests > outsideBoundRequests &&
      controller.floatingOSCScale == FloatingOSCScale.factor(for: video.bounds.size),
      "a prediction outside the one-point bound falls back to exact actual metrics and measurement")
video.layoutSubtreeIfNeeded()
Preference.set(false, for: .controlBarDefaultPositionIsCustomized)
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint()))
check(near(yConstraint.constant, 16), "reset to untouched default retains fixed sixteen-point gap")
var styles: [TranslucentView.Style] = [.visualEffect]
if #available(macOS 26, *) { styles.append(.liquidGlass) }
Preference.set(true, for: .controlBarDefaultPositionIsCustomized)
for style in styles {
  osc.setStyle(style)
  for direction: NSUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft] {
    osc.userInterfaceLayoutDirection = direction
    for h: Float in [0, 25, 50, 75, 100] {
      for v: Float in [0, 25, 50, 75, 100] {
        resize(NSSize(width: 1000, height: 600))
        Preference.set(h, for: .controlBarDefaultPositionHorizontal)
        Preference.set(v, for: .controlBarDefaultPositionVertical)
        osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint()))
        let initial = NSPoint(x: xConstraint.constant - osc.frame.width / 2, y: yConstraint.constant)
        var defaultFrames: [NSRect] = []
        for size in sizes {
          resize(size)
          let availableX = max(0, size.width - osc.frame.width - 32)
          let availableY = max(0, header.frame.minY + 1 - osc.frame.height)
          check(abs(xConstraint.constant - osc.frame.width / 2 - 16 - availableX * CGFloat(h / 100)) < 0.01,
                "numeric horizontal percentage divides physical travel with sixteen-point side gaps")
          check(abs(yConstraint.constant - availableY * (1 - CGFloat(v / 100))) < 0.01,
                "numeric vertical percentage divides travel below the header without vertical gaps")
          defaultFrames.append(NSRect(x: xConstraint.constant, y: yConstraint.constant, width: osc.frame.width, height: osc.frame.height))
        }
        resize(NSSize(width: 1000, height: 600))
        // Same physical placement via drag must follow the same resize trajectory.
        dragTo(NSPoint(x: initial.x + (h == 100 ? -1 : 1), y: initial.y))
        dragTo(initial)
        check(abs(Float(osc.currentPosition!.horizontal.value) - h / 100) < 0.0001 &&
              abs(Float(osc.currentPosition!.vertical.value) - v / 100) < 0.0001,
              "manual placement saves the same physical fractions as numeric placement in LTR and RTL")
        for (index, size) in sizes.enumerated() {
          resize(size)
          check(abs(xConstraint.constant - defaultFrames[index].minX) < 0.01 &&
                abs(yConstraint.constant - defaultFrames[index].minY) < 0.01,
                "manual and default placement have identical resize trajectories")
        }
      }
    }
  }
}
// Fixed point anchors and mixed units must retain the same resize contract.
for hUnit in [FloatingOSCPosition.Unit.percent, .point] {
  for vUnit in [FloatingOSCPosition.Unit.percent, .point] {
    for hEdge in [FloatingOSCPosition.Edge.near, .far] {
      for vEdge in [FloatingOSCPosition.Edge.near, .far] {
        let intent = FloatingOSCPosition(horizontal: .init(value: hUnit == .percent ? 0.25 : 24, unit: hUnit, edge: hEdge),
          vertical: .init(value: vUnit == .percent ? 0.75 : 16, unit: vUnit, edge: vEdge))
        Preference.saveFloatingOSCDefaultPosition(intent)
        resize(NSSize(width: 1000, height: 600))
        osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint()))
        checkRoundedPreparedResize(NSSize(width: 774.1865, height: 435.4803))
        for size in sizes {
          resize(size)
          let expected = FloatingOSCPlacement.frame(position: intent, size: osc.frame.size, contentSize: size, titlebarBottom: header.frame.minY + 1)
          check(near(xConstraint.constant, expected.midX) && near(yConstraint.constant, expected.minY), "all unit/edge combinations use the common model after native resize")
          check(osc.currentPosition == intent, "resize preserves intent without converting units")
        }
        resize(NSSize(width: 1000, height: 600))
        dragTo(NSPoint(x: 80, y: 100))
        let captured = osc.currentPosition!
        check(captured.horizontal.unit == .percent && captured.vertical.unit == .percent && captured.horizontal.edge == .near && captured.vertical.edge == .near,
              "live drag converts both temporary axes to physical left/top percentages")
        check(Preference.floatingOSCDefaultPosition == intent, "live drag leaves configured default units and values untouched")
        for size in sizes {
          resize(size)
          let expected = FloatingOSCPlacement.frame(position: captured, size: osc.frame.size, contentSize: size, titlebarBottom: header.frame.minY + 1)
          // AppKit rounds adaptive panel dimensions to backing pixels.
          check(abs(xConstraint.constant - expected.midX) <= 0.51 && abs(yConstraint.constant - expected.minY) <= 0.51, "converted live position follows relative travel across window shapes")
          check(osc.currentPosition == captured, "resize retains temporary percentage intent")
        }
        osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint()))
        check(osc.currentPosition == intent, "double-click restores the original default units after relative dragging")
      }
    }
  }
}
// Regression: a point-based default must not pull a dragged center upward.
Preference.saveFloatingOSCDefaultPosition(.initial)
resize(NSSize(width: 1000, height: 600))
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint()))
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint(), clicks: 1))
osc.mouseUp(with: event(.leftMouseUp, point: backgroundPoint(), clicks: 1))
check(osc.currentPosition == .initial, "background click without movement keeps default units")
dragTo(NSPoint(x: 16, y: (header.frame.minY + 1 - osc.frame.height) / 2))
check(near(osc.currentPosition!.vertical.value, 0.5), "dragging to vertical center captures fifty percent")
for size in sizes {
  resize(size)
  check(abs(osc.frame.midY - (header.frame.minY + 1) / 2) <= 0.51,
        "live left-center stays vertically centered across sizes and aspect ratios")
}
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint()))
check(osc.currentPosition == .initial && abs(osc.frame.minY - 16) <= 0.51,
      "double-click restores fixed sixteen-point default after centered drag")
Preference.saveFloatingOSCDefaultPosition(.percentages(0.6, 0.7))
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint()))
resize(NSSize(width: 1000, height: 600))
dragTo(NSPoint(x: 450, y: 150))
let saved = osc.currentPosition!
controller.sidebars.right = 300
position()
check(abs(osc.frame.minX - 450) <= 0.51, "sidebar cannot displace the manually placed OSC")
check(osc.currentPosition == saved, "sidebar visibility does not rewrite per-axis intent")
controller.sidebars.right = 0
position()
check(abs(osc.frame.minX - 450) <= 0.51 && abs(osc.frame.minY - 150) <= 0.51, "closing sidebar restores requested physical placement")
Preference.set(0.123, for: .controlBarPositionLeading)
Preference.set(0.456, for: .controlBarPositionTop)
dragTo(NSPoint(x: 16, y: 0))
check(Preference.float(for: .controlBarPositionLeading) == 0.123 && Preference.float(for: .controlBarPositionTop) == 0.456, "new drags leave legacy coordinate formats untouched")
let previous = osc.currentPosition!.horizontal
resize(NSSize(width: 300, height: 600))
dragTo(NSPoint(x: 0, y: 160))
check(osc.currentPosition!.horizontal == previous, "collapsed axis preserves previous intent")
resize(NSSize(width: 1000, height: 600))
dragTo(NSPoint(x: 16, y: 0))
for size in sizes {
  resize(size)
  check(near(yConstraint.constant, 0), "explicit bottom placement remains flush during resizing")
}
// A second window owns its own state and does not inherit this window's drag.
let otherController = MainWindowController()
let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
otherWindow.isReleasedWhenClosed = false
let otherVideo = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
otherWindow.contentView = otherVideo
otherController.window = otherWindow
otherController.videoViewContainer = otherVideo
let otherOSC = OSCFloatingView(mainWindow: otherController)
otherVideo.addSubview(otherOSC)
otherOSC.setupConstraints()
otherController.topRowHeight = otherOSC.oscTopView.heightAnchor.constraint(equalToConstant: 45)
otherController.bottomRowHeight = otherOSC.oscBottomView.heightAnchor.constraint(equalToConstant: 35)
otherController.topRowHeight!.isActive = true
otherController.bottomRowHeight!.isActive = true
otherOSC.updatePosition()
check(otherOSC.currentPosition == Preference.floatingOSCDefaultPosition && otherOSC.currentPosition != osc.currentPosition,
      "new window starts at default independently of another window's manual position")
let otherSaved = otherOSC.currentPosition
resize(NSSize(width: 1000, height: 600))
dragTo(NSPoint(x: 100, y: 200))
otherOSC.updatePosition()
check(otherOSC.currentPosition == otherSaved, "dragging one window leaves another window's position unchanged")
let manual = osc.currentPosition
osc.beginWindowSession()
check(osc.currentPosition == manual, "showing an active window preserves its manual placement")
osc.updatePosition()
check(osc.currentPosition == manual, "reinitializing controls for the same window retains session intent")
Preference.saveFloatingOSCDefaultPosition(.initial)
position()
check(osc.currentPosition == manual, "saving a default does not replace active session placement")
osc.endWindowSession()
check(osc.currentPosition == nil && !osc.isDragging && osc.mousePosRelatedToView == nil,
      "closing a window clears placement and pending drag state")
position()
check(osc.currentPosition == nil, "late layout callbacks after close leave the session ended")
osc.beginWindowSession()
position()
check(osc.currentPosition == .initial && near(yConstraint.constant, 16),
      "reusing a closed player window begins with the latest saved default")
let persistenceBeforeDrag = Preference.defaults.dictionaryRepresentation()
dragTo(NSPoint(x: 100, y: 200))
check(NSDictionary(dictionary: Preference.defaults.dictionaryRepresentation()).isEqual(to: persistenceBeforeDrag),
      "manual dragging writes no persistent preferences")
check(Preference.dictionary(for: .controlBarCurrentPlacement) != nil,
      "historical manual settings are ignored without deleting unrelated stored data")
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint()))
check(osc.currentPosition == .initial, "double-click still restores saved default within session")
Preference.defaults.synchronize()
// OSC gestures read preferences on each event and ignore controls.
Preference.set(1, for: .oscRightClickAction)
Preference.set(2, for: .oscDoubleClickAction)
let hidesBefore = controller.hideRequests
osc.rightMouseUp(with: event(.rightMouseUp, point: backgroundPoint(), clicks: 1))
check(controller.hideRequests == hidesBefore + 1, "right background click requests explicit UI hiding")
Preference.set(0, for: .oscRightClickAction)
osc.rightMouseUp(with: event(.rightMouseUp, point: backgroundPoint(), clicks: 1))
check(controller.hideRequests == hidesBefore + 1, "disabled right background click has no action")
Preference.set(2, for: .oscRightClickAction)
osc.rightMouseUp(with: event(.rightMouseUp, point: backgroundPoint(), clicks: 1))
check(osc.currentPosition == Preference.floatingOSCDefaultPosition, "right click can reset the saved default position")
Preference.set(1, for: .oscDoubleClickAction)
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint(), clicks: 2))
check(controller.hideRequests == hidesBefore + 2, "double background click uses its own configured action")
Preference.set(2, for: .oscDoubleClickAction)
Preference.set(1, for: .oscRightClickAction)
let control = NSButton(frame: NSRect(x: 40, y: 5, width: 24, height: 24))
osc.addSubview(control)
let controlPoint = control.convert(NSPoint(x: 12, y: 12), to: nil)
let hidesBeforeControl = controller.hideRequests
osc.rightMouseUp(with: event(.rightMouseUp, point: controlPoint, clicks: 1))
check(controller.hideRequests == hidesBeforeControl, "right click on an OSC control cannot hide the UI")
control.removeFromSuperview()
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint(), clicks: 1))
osc.rightMouseUp(with: event(.rightMouseUp, point: backgroundPoint(), clicks: 1))
check(controller.hideRequests == hidesBeforeControl, "right click cannot hide OSC during a left drag")
osc.mouseUp(with: event(.leftMouseUp, point: backgroundPoint(), clicks: 1))
dragTo(NSPoint(x: 90, y: 150))
let positionBeforeDisabledReset = osc.currentPosition
Preference.set(0, for: .oscDoubleClickAction)
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint(), clicks: 2))
check(osc.currentPosition == positionBeforeDisabledReset, "disabled double click retains manual placement")
Preference.set(2, for: .oscDoubleClickAction)
// The new left-click preference shares action meanings and existing numeric
// right/double bindings; no double action means no artificial delay.
Preference.set(0, for: .oscDoubleClickAction)
Preference.set(1, for: .oscLeftClickAction)
let hidesBeforeLeft = controller.hideRequests
osc.performSingleBackgroundClick()
check(controller.hideRequests == hidesBeforeLeft + 1, "configured OSC left click can hide UI immediately without a double action")
Preference.set(0, for: .oscLeftClickAction)
osc.performSingleBackgroundClick()
check(controller.hideRequests == hidesBeforeLeft + 1, "OSC left click None does nothing")
Preference.set(2, for: .oscLeftClickAction)
osc.performSingleBackgroundClick()
check(osc.currentPosition == Preference.floatingOSCDefaultPosition, "OSC left click can reset position")
Preference.set(3, for: .oscLeftClickAction)
let frontBeforeLeft = controller.sidebars.frontRequests
osc.performSingleBackgroundClick()
check(controller.sidebars.frontRequests == frontBeforeLeft + 1, "OSC left click can bring its panel to front")
Preference.set(2, for: .oscDoubleClickAction)
osc.resetPosition()
resize(NSSize(width: 1000, height: 600))
Preference.saveFloatingOSCDefaultPosition(.percentages(0.5, 0))
osc.resetPosition()
let visibleHeaderPosition = osc.frame
header.isHidden = true
header.frame.origin.y = video.bounds.maxY
position()
check(osc.frame == visibleHeaderPosition, "hidden header retains the top OSC's reserved space")
header.isHidden = false
header.frame.origin.y = video.bounds.maxY - 40
position()
check(osc.frame.maxY <= header.frame.minY + 1, "header reveal contains OSC below its visible background edge")
controller.fsState.isFullscreen = true
header.isHidden = true
header.frame.origin.y = video.bounds.maxY
position()
check(near(osc.frame.maxY, video.bounds.maxY), "fullscreen releases the windowed header reservation")
controller.fsState.isFullscreen = false
Preference.saveFloatingOSCDefaultPosition(.initial)
osc.resetPosition()
// A bottom-edge constraint must not suppress a roomy horizontal rebound.
Preference.set(true, for: .disableAnimations)
resize(NSSize(width: 1800, height: 800))
Preference.saveFloatingOSCDefaultPosition(.initial)
osc.resetPosition()
let diagonalTarget = CGPoint(x: xConstraint.constant, y: yConstraint.constant)
dragTo(CGPoint(x: 70, y: 480))
Preference.set(false, for: .disableAnimations)
osc.resetPosition()
var diagonalExtraX: CGFloat = 0
var diagonalMinimumY = yConstraint.constant
let diagonalDeadline = ProcessInfo.processInfo.systemUptime + 1
while osc.isReturningToDefault && ProcessInfo.processInfo.systemUptime < diagonalDeadline {
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
  diagonalExtraX = max(diagonalExtraX, xConstraint.constant - diagonalTarget.x)
  diagonalMinimumY = min(diagonalMinimumY, yConstraint.constant)
}
check(!osc.isReturningToDefault && diagonalExtraX > 65 && diagonalMinimumY >= 15.49,
      "bottom-edge diagonal return keeps a visible horizontal stretch without a tiny vertical bounce")
Preference.set(true, for: .disableAnimations)
resize(NSSize(width: 1000, height: 600))
osc.resetPosition()
// Sample the production curve deterministically, independent of AppKit timer load.
let stretchCurve = FloatingOSCReturnCurve(overshootRatio: 0.20)
let curveSamples = (0...1000).map { stretchCurve.value(at: CGFloat($0) / 1000) }
let turningIndex = curveSamples.indices.max { curveSamples[$0] < curveSamples[$1] }!
let crossingIndex = curveSamples.firstIndex { $0 >= 1 }!
let speeds = zip(curveSamples.dropFirst(), curveSamples).map { $0 - $1 }
let stretchSpeeds = Array(speeds[crossingIndex..<turningIndex])
check(curveSamples.first == 0 && curveSamples.last == 1 &&
      abs(curveSamples[turningIndex] - 1.20) < 0.0001,
      "return curve stretches twenty percent and lands exactly at rest")
check(curveSamples[80] > 0.027 && curveSamples[150] > 0.115,
      "spring release gains speed immediately and travels farther early in the return")
check(turningIndex - crossingIndex > 50 &&
      zip(stretchSpeeds.dropFirst(), stretchSpeeds).allSatisfy { $0 <= $1 + 0.000001 },
      "stretch continuously slows from crossing the default through its turning point")
let visibleStretchTime = TimeInterval(turningIndex - crossingIndex) / 1000
  * FloatingOSCReturnCurve.duration(for: 500)
check(visibleStretchTime > 0.12 && visibleStretchTime < 0.15,
      "stretch spends longer braking toward the same peak without a pause or a farther overshoot")
check(speeds[..<turningIndex].allSatisfy { $0 > 0 } &&
      speeds[turningIndex...].allSatisfy { $0 < 0 },
      "return has one continuous reversal without secondary oscillations")
check(abs(speeds.min()!) < speeds.max()! * 0.5 &&
      abs(speeds.first!) < 0.00001 && abs(speeds.last!) < 0.000001,
      "rebound is gentler than travel and both endpoints settle smoothly")
let reboundSpeeds = speeds[turningIndex...].map { -$0 }
let reboundMaximumSpeedIndex = reboundSpeeds.indices.max { reboundSpeeds[$0] < reboundSpeeds[$1] }!
let reboundBrakingStart = CGFloat(reboundMaximumSpeedIndex) / CGFloat(reboundSpeeds.count)
check(reboundBrakingStart < 0.36 &&
      zip(reboundSpeeds.dropFirst(reboundMaximumSpeedIndex + 1),
          reboundSpeeds.dropFirst(reboundMaximumSpeedIndex)).allSatisfy { $0 <= $1 + 0.000001 },
      "rebound spends at least the last two thirds progressively slowing toward the saved position")
let originalDuration: TimeInterval = 0.44045454545454543
let timingScale = CGFloat(FloatingOSCReturnCurve.duration(for: 500) / originalDuration)
for (elapsed, expected) in [(CGFloat(0.08), CGFloat(0.032277059310750006)),
                            (0.15, 0.1346141743944883), (0.30, 0.5530400134963989)] {
  check(abs(stretchCurve.value(at: elapsed / timingScale) - expected) < 0.000001,
        "launch retains its pre-change position at the same elapsed time (phase=\(elapsed))")
}
for (elapsed, expected) in [(CGFloat(0.75), CGFloat(1.137886004635734)),
                            (0.85, 1.0578078733404142), (0.95, 1.0101880111678303),
                            (1.05, 1.0000627160347915)] {
  check(abs(stretchCurve.value(at: (elapsed + 0.12) / timingScale) - expected) < 0.000001,
        "soft rebound retains its previous trajectory after the added stretch time (phase=\(elapsed))")
}
let reboundSpeedPerOriginalDuration = reboundSpeeds.max()! * 1000 / timingScale
check(reboundSpeedPerOriginalDuration < 0.88 &&
      abs(stretchCurve.value(at: 1.12 / timingScale) - 1) < 0.003,
      "rebound is slower than before and the extra settling tail contains only the final small approach")
for ratio in [CGFloat(0.0001), 0.005, 0.03, 0.20] {
  let curve = FloatingOSCReturnCurve(overshootRatio: ratio)
  let samples = (0...2000).map { curve.value(at: CGFloat($0) / 2000) }
  let peak = samples.indices.max { samples[$0] < samples[$1] }!
  check(samples.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 + ratio + 0.00001 } &&
        zip(samples[1...peak], samples[..<peak]).allSatisfy { $0 >= $1 - 0.000001 } &&
        zip(samples[(peak + 1)...], samples[peak..<samples.count - 1]).allSatisfy { $0 <= $1 + 0.000001 },
        "stretch retiming remains bounded and has one reversal across small and large amplitudes (ratio=\(ratio))")
}
for (distance, room, expectedExtra) in [(CGFloat(50), CGFloat(1), CGFloat(0)), (500, 1, 96),
                                        (1600, 1, 96), (500, 0.016, 0), (500, 0.08, 40), (500, 0, 0)] {
  let path = FloatingOSCReturnPath(from: .zero, to: CGPoint(x: distance, y: 0),
    horizontalRange: 0...(distance * (1 + room)), verticalRange: 0...0)
  let points = (0...1000).map { path.position(at: CGFloat($0) / 1000) }
  let extra = points.map { $0.x - distance }.max()!
  check(abs(extra - expectedExtra) < 0.01 && points.allSatisfy { $0.y == 0 },
        "stretch scales with travel, skips tiny excursions and respects room (distance=\(distance), extra=\(expectedExtra))")
}
let stopCurve = FloatingOSCReturnCurve(overshootRatio: 0)
let stopSamples = (0...1000).map { stopCurve.value(at: CGFloat($0) / 1000) }
check(stopSamples[150] > 0.08 && zip(stopSamples.dropFirst(), stopSamples).allSatisfy { $0 >= $1 } &&
      stopSamples.allSatisfy { (0...1).contains($0) },
      "a crowded axis retains a quick launch and settles monotonically without clipping or oscillation")
for direction in [CGFloat(-1), CGFloat(1)] {
  for constrainedAxis in [0, 1] {
    let end = CGPoint(x: 600 * direction, y: 500 * direction)
    let xRoom: CGFloat = constrainedAxis == 0 ? 16 : 200
    let yRoom: CGFloat = constrainedAxis == 1 ? 16 : 200
    let xBounds = min(0, end.x - xRoom)...max(0, end.x + xRoom)
    let yBounds = min(0, end.y - yRoom)...max(0, end.y + yRoom)
    let path = FloatingOSCReturnPath(from: .zero, to: end,
      horizontalRange: xBounds, verticalRange: yBounds)
    let points = (0...1000).map { path.position(at: CGFloat($0) / 1000) }
    let extraX = points.map { direction * ($0.x - end.x) }.max()!
    let extraY = points.map { direction * ($0.y - end.y) }.max()!
    let freeExtra = constrainedAxis == 0 ? extraY : extraX
    let constrainedExtra = constrainedAxis == 0 ? extraX : extraY
    check(freeExtra > 60 && abs(constrainedExtra) < 0.001 &&
          points.allSatisfy { xBounds.contains($0.x) && yBounds.contains($0.y) } &&
          points.first == .zero && points.last == end,
          "each axis keeps its own smooth contained stretch in either direction (constrained=\(constrainedAxis), direction=\(direction))")
  }
}
check(FloatingOSCReturnCurve.duration(for: 800) > FloatingOSCReturnCurve.duration(for: 50) &&
      abs(FloatingOSCReturnCurve.duration(for: 0) - 0.324) < 0.000001 &&
      FloatingOSCReturnCurve.duration(for: 2000) <= 0.594001,
      "only stretch and settling gain time while the original fast launch timing is preserved")
// A reset traverses intermediate frames, overshoots within bounds, then settles.
Preference.set(false, for: .disableAnimations)
resize(NSSize(width: 1000, height: 600))
dragTo(NSPoint(x: 50, y: 250))
let motionStart = osc.frame
osc.resetPosition()
check(osc.frame == motionStart, "reset starts at the current frame instead of teleporting")
let motionDeadline = ProcessInfo.processInfo.systemUptime + 0.15
while osc.frame == motionStart && ProcessInfo.processInfo.systemUptime < motionDeadline {
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
}
check(osc.frame != motionStart && osc.frame.minY > 16,
      "reset visits an intermediate frame before reaching the default")
func pumpUntil(_ condition: () -> Bool, timeout: TimeInterval = 1) -> Bool {
  let deadline = ProcessInfo.processInfo.systemUptime + timeout
  while !condition() && ProcessInfo.processInfo.systemUptime < deadline {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
  }
  return condition()
}
var returnMinimumY = yConstraint.constant
var returnExtraX: CGFloat = 0
var reversedAfterOvershoot = false
check(pumpUntil {
  returnMinimumY = min(returnMinimumY, yConstraint.constant)
  returnExtraX = max(returnExtraX, xConstraint.constant - 500)
  if returnExtraX > 30 && xConstraint.constant < 500 + returnExtraX - 0.5 { reversedAfterOvershoot = true }
  return !osc.isReturningToDefault
}, "unobstructed reset completes and releases interaction")
check(returnMinimumY >= 15.49 && returnExtraX > 30 && reversedAfterOvershoot,
      "return visibly rebounds along the roomy axis and settles without a crowded-axis twitch")
check(near(xConstraint.constant, 500) && near(yConstraint.constant, 16), "animated reset lands exactly on saved default")
check(pumpUntil { !osc.isReturningToDefault }, "there is no lingering return after completion")

// Observe the larger stretch in native geometry in both horizontal directions.
Preference.set(true, for: .disableAnimations)
resize(NSSize(width: 1800, height: 800))
Preference.saveFloatingOSCDefaultPosition(.percentages(0.5, 0.5))
osc.resetPosition()
let stretchTarget = CGPoint(x: xConstraint.constant, y: yConstraint.constant)
Preference.set(false, for: .disableAnimations)
var nativeStretch: [CGFloat] = []
for originX in [CGFloat(100), CGFloat(1240), stretchTarget.x - osc.frame.width / 2 - 50] {
  dragTo(CGPoint(x: originX, y: stretchTarget.y))
  let direction: CGFloat = osc.frame.midX < stretchTarget.x ? 1 : -1
  let distance = abs(osc.frame.midX - stretchTarget.x)
  osc.resetPosition()
  var extra: CGFloat = 0
  var staysOnPath = true
  check(pumpUntil {
    extra = max(extra, direction * (osc.frame.midX - stretchTarget.x))
    staysOnPath = staysOnPath && abs(osc.frame.minY - stretchTarget.y) <= 0.51
    return !osc.isReturningToDefault
  }, "native stretch completes in either direction")
  let desiredExtra = min(96, distance * 0.20)
  let expectedExtra = desiredExtra >= 12 ? desiredExtra : 0
  check(abs(extra - expectedExtra) < 1 && staysOnPath &&
        near(xConstraint.constant, stretchTarget.x) && near(yConstraint.constant, stretchTarget.y),
        "native stretch is visible, bounded and settles exactly without sideways drift")
  nativeStretch.append(extra)
}
check(nativeStretch[0] > nativeStretch[2] * 5 && abs(nativeStretch[0] - nativeStretch[1]) < 1,
      "long returns stretch farther than short returns, symmetrically in both directions")

// Sample the actual material and OSC frames throughout edge/corner returns.
for style in styles {
  osc.setStyle(style)
  for size in [NSSize(width: 1000, height: 600), NSSize(width: 400, height: 225)] {
    for (index, corner) in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1),
                            CGPoint(x: 1, y: 1), CGPoint(x: 0.03, y: 0.03), CGPoint(x: 0.97, y: 0.97)].enumerated() {
      osc.userInterfaceLayoutDirection = index.isMultiple(of: 2) ? .leftToRight : .rightToLeft
      Preference.set(true, for: .disableAnimations)
      resize(size)
      Preference.saveFloatingOSCDefaultPosition(.percentages(corner.x, corner.y))
      osc.resetPosition()
      let destination = osc.frame
      dragTo(CGPoint(x: corner.x < 0.5 ? size.width : 0,
                     y: corner.y < 0.5 ? 0 : size.height))
      Preference.set(false, for: .disableAnimations)
      osc.resetPosition()
      var contained = true
      check(pumpUntil {
        let material = osc.container.map { video.convert($0.bounds, from: $0) } ?? osc.frame
        for rect in [osc.frame, material] {
          contained = contained && rect.minX >= -0.51 && rect.maxX <= size.width + 0.51 &&
            rect.minY >= -0.51 && rect.maxY <= header.frame.minY + 1.51
        }
        return !osc.isReturningToDefault
      }, "edge return completes (corner=\(corner), size=\(size), style=\(style))")
      check(contained && abs(osc.frame.minX - destination.minX) <= 0.51 &&
            abs(osc.frame.minY - destination.minY) <= 0.51,
            "every sampled OSC/material frame remains inside the window and below the header")
    }
  }
}
Preference.set(true, for: .disableAnimations)
Preference.saveFloatingOSCDefaultPosition(.initial)
osc.resetPosition()
resize(NSSize(width: 1000, height: 600))
Preference.set(false, for: .disableAnimations)

// Actual native hit routing must shield buttons, sliders and the non-control volume view.
let button = NSButton(frame: NSRect(x: 40, y: 5, width: 24, height: 24))
let slider = NSSlider(frame: NSRect(x: 80, y: 5, width: 80, height: 24))
let volume = VolumeButton(frame: NSRect(x: 170, y: 5, width: 24, height: 24))
for child in [button, slider, volume] as [NSView] { osc.addSubview(child) }
dragTo(NSPoint(x: 50, y: 250))
osc.resetPosition()
check(osc.isReturningToDefault && !osc.mouseDownCanMoveWindow, "reset prevents native window dragging")
for child in [button, slider, volume] as [NSView] {
  let point = child.convert(NSPoint(x: child.bounds.midX, y: child.bounds.midY), to: video)
  check(video.hitTest(point) === osc, "moving OSC absorbs native control hits")
}
let frameBeforeInput = osc.frame
let hidesBeforeMotion = controller.hideRequests
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint(), clicks: 1))
osc.mouseDragged(with: event(.leftMouseDragged, point: NSPoint(x: 800, y: 400), clicks: 1))
osc.mouseUp(with: event(.leftMouseUp, point: backgroundPoint(), clicks: 1))
osc.mouseDown(with: event(.leftMouseDown, point: backgroundPoint(), clicks: 2))
osc.rightMouseUp(with: event(.rightMouseUp, point: backgroundPoint(), clicks: 1))
osc.resetPosition()
check(!osc.isDragging && osc.frame == frameBeforeInput && controller.hideRequests == hidesBeforeMotion,
      "drag, repeated reset, double click and hide cannot interrupt return")
let videoEventsBefore = video.downEvents + video.upEvents
window.sendEvent(event(.leftMouseDown, point: button.convert(NSPoint(x: 12, y: 12), to: nil), clicks: 1))
window.sendEvent(event(.leftMouseUp, point: button.convert(NSPoint(x: 12, y: 12), to: nil), clicks: 1))
check(video.downEvents + video.upEvents == videoEventsBefore, "blocked button clicks do not fall through to the video")

check(pumpUntil { !osc.isReturningToDefault }, "protected return releases controls after its rebound")
check(video.hitTest(button.convert(NSPoint(x: 12, y: 12), to: video)) === button,
      "native button hit routing is restored after the return")
for child in [button, slider, volume] as [NSView] { child.removeFromSuperview() }

// Sidebar overlap never rejects a reset or limits a manual drag.
controller.sidebars.left = 360
controller.sidebars.right = 360
position()
dragTo(NSPoint(x: 450, y: 230))
let resetPreferences = Preference.defaults.dictionaryRepresentation()
osc.resetPosition()
check(osc.currentPosition == .initial, "reset adopts its saved destination even with both sidebars open")
check(pumpUntil { !osc.isReturningToDefault } && near(xConstraint.constant, 500),
      "reset completes normally through sidebar overlap")
check(NSDictionary(dictionary: Preference.defaults.dictionaryRepresentation()).isEqual(to: resetPreferences),
      "reset with sidebars leaves saved preferences unchanged")
for left in [true, false] {
  controller.sidebars.left = left ? 300 : 0
  controller.sidebars.right = left ? 0 : 300
  position()
  dragTo(NSPoint(x: left ? -1000 : 2000, y: 220))
  check(left ? abs(osc.frame.minX - 16) <= 0.51 : abs(osc.frame.maxX - 984) <= 0.51,
        "manual drag reaches the physical window edge through either sidebar")
}
controller.sidebars.left = 300
controller.sidebars.right = 300
resize(NSSize(width: 400, height: 300))
for requestedX in [CGFloat(-1000), CGFloat(2000)] {
  dragTo(NSPoint(x: requestedX, y: 60))
  let overlappingFrame = osc.frame
  controller.sidebars.left = 0; controller.sidebars.right = 0
  position(); dragTo(NSPoint(x: requestedX, y: 60))
  check(osc.frame == overlappingFrame, "small-window placement is identical with or without sidebars")
  controller.sidebars.left = 300; controller.sidebars.right = 300
}
controller.sidebars.left = 0
controller.sidebars.right = 0
resize(NSSize(width: 1000, height: 600))

// Common-mode timer must continue while AppKit tracks pointer input elsewhere.
dragTo(NSPoint(x: 50, y: 250))
osc.resetPosition()
let trackingStart = osc.frame
let trackingDeadline = ProcessInfo.processInfo.systemUptime + 0.1
while osc.frame == trackingStart && ProcessInfo.processInfo.systemUptime < trackingDeadline {
  RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.002))
}
check(osc.frame != trackingStart, "return advances during native event tracking")
check(pumpUntil { !osc.isReturningToDefault }, "return finishes after native tracking")

// Resize may update containment but cannot rewrite the saved placement.
dragTo(NSPoint(x: 500, y: 450))
osc.resetPosition()
resize(NSSize(width: 400, height: 225))
check(osc.frame.minX >= -0.51 && osc.frame.maxX <= 400.51 && osc.frame.minY >= -0.51 &&
      osc.frame.maxY <= header.frame.minY + 1.51,
      "resize contains the moving OSC immediately, before the next animation tick")
var containedDuringResize = true
check(pumpUntil {
  containedDuringResize = containedDuringResize && osc.frame.minX >= -0.51 && osc.frame.maxX <= 400.51 &&
    osc.frame.minY >= -0.51 && osc.frame.maxY <= header.frame.minY + 1.51
  return !osc.isReturningToDefault
}, "return survives resizing to the native minimum")
check(containedDuringResize, "resized return stays contained through every sampled frame")
check(osc.frame.minX >= 0 && osc.frame.maxX <= 400.51 && osc.frame.minY >= 0,
      "reset remains contained after a minimum-size resize")
resize(NSSize(width: 1000, height: 600))

for reduced in [false, true] {
  Preference.set(!reduced, for: .disableAnimations)
  AccessibilityPreferences.motionReductionEnabled = reduced
  dragTo(NSPoint(x: 50, y: 250))
  osc.resetPosition()
  check(!osc.isReturningToDefault && near(yConstraint.constant, 16),
        "disabled animations and Reduce Motion settle without an interaction lock")
}
for reduced in [false, true] {
  Preference.set(!reduced, for: .disableAnimations)
  AccessibilityPreferences.motionReductionEnabled = reduced
  controller.sidebars.left = 360
  position()
  dragTo(NSPoint(x: 450, y: 230))
  osc.resetPosition()
  check(!osc.isReturningToDefault && osc.currentPosition == .initial && near(xConstraint.constant, 500) && near(yConstraint.constant, 16),
        "reduced motion and disabled animations reset immediately through sidebar overlap")
  controller.sidebars.left = 0
  position()
}
Preference.set(false, for: .disableAnimations)
AccessibilityPreferences.motionReductionEnabled = false
for interruption in ["close", "hide", "detach", "layout"] {
  dragTo(NSPoint(x: 50, y: 250))
  osc.resetPosition()
  switch interruption {
  case "close": osc.endWindowSession()
  case "hide": osc.isHidden = true
  case "detach": osc.removeFromSuperview()
  default: osc.cancelPositionAnimation()
  }
  let interruptedFrame = osc.frame
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
  check(!osc.isReturningToDefault && osc.frame == interruptedFrame,
        "\(interruption) cancels the timer without stale position writes")
  osc.isHidden = false
  if osc.superview == nil { video.addSubview(osc); osc.setupConstraints() }
  osc.beginWindowSession()
  position()
}
print("Completed \(count) window-session AppKit position checks; synthetic input.")
window.orderOut(nil)
otherWindow.orderOut(nil)
