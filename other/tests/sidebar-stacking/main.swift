import Cocoa
import WebKit
import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  guard value() else { print("FAIL: \(message)"); exit(1) }
  checks += 1; print("PASS: \(message)")
}
func wait(_ duration: TimeInterval) {
  let end = Date().addingTimeInterval(duration)
  while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
}
protocol InitializingFromKey { init?(key: Preference.Key) }
enum Preference {
  enum Key { case oscLeftClickAction, oscRightClickAction, oscDoubleClickAction }
  static var doubleAction = 0
  static var leftAction = 1
  static var rightAction = 3
  static func integer(for key: Key) -> Int { key == .oscLeftClickAction ? leftAction : key == .oscRightClickAction ? rightAction : doubleAction }
// PRODUCTION_OSC_CLICK_ACTION
}
class PlayerWindowController: NSWindowController {
  var scrollActions = 0
  override func scrollWheel(with event: NSEvent) { scrollActions += 1 }
}
extension NSEvent {
  func inAnyOf(_ views: [NSView?]) -> Bool {
    views.compactMap { $0 }.contains { !$0.isHidden && $0.bounds.contains($0.convert(locationInWindow, from: nil)) }
  }
}
extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
class MainWindowController: PlayerWindowController {
  func cancelWindowDrag() {}
  enum UIAnimationState { case hidden, shown, willHide, willShow }
  struct InteractiveMode { var isActive = false }
  var interactiveMode = InteractiveMode()
  var isMomentumScrollingAllowed = false
  var isMouseInWindow = true
  var seekOverride = false
  var volumeOverride = false
  var hideRequests = 0
  var isUIHiddenByOSCClick = false
  func destroyTimer() {}
  func hideUI(force: Bool) { hideRequests += 1 }
// PRODUCTION_HIDE_UI_FROM_OSC
  var secondaryRequests = 0
  override func rightMouseUp(with event: NSEvent) { if !sidebars.isEventTargetingVisibleSidebar(event) { secondaryRequests += 1 } }
  var restoreRequests = 0
  func restoreUIFromSidebarBackground() { restoreRequests += 1 }
  func handleDefaultEscape(with event: NSEvent) -> Bool { false }
  var headerDowns = 0, headerDrags = 0, headerUps = 0
  override func mouseDown(with event: NSEvent) { headerDowns += 1 }
  override func mouseDragged(with event: NSEvent) { headerDrags += 1 }
  override func mouseUp(with event: NSEvent) { headerUps += 1 }
  let playSlider = NSSlider(frame: NSRect(x: 0, y: 0, width: 70, height: 40))
  let volumeSlider = NSSlider(frame: NSRect(x: 70, y: 0, width: 70, height: 40))
  let videoView = NSView()
  var titleBarView: Titlebar!
  var currentControlBar: NSView? { oscFloatingView }
// PRODUCTION_SCROLL_ROUTING
  enum OSCPosition { case floating, bottom }
  var oscPosition = OSCPosition.floating
  var oscFloatingView: OSCFloatingView! = OSCFloatingView()
  lazy var sidebars = SidebarController(mainWindow: self)
}
class MainWindow: NSWindow {
// PRODUCTION_WINDOW_DISPATCH
}
class HeaderFixture {
  let view: NSView
  var tabButtonsStackView: NSView?
  init(_ view: NSView) {
    self.view = view
    let header = NSView(frame: NSRect(x: 0, y: 218, width: 300, height: 52))
    view.addSubview(header, positioned: .below, relativeTo: view.subviews.first)
    tabButtonsStackView = header
  }
}
class SidebarController {
  enum Side { case leading, trailing }
  enum ViewType { case hidden, settings, plugins }
  class Panel {
    let side: Side
    let view = NSView()
    var status: ViewType = .hidden
    var animationState = MainWindowController.UIAnimationState.shown
    let visibleEdgeMargin: CGFloat = 0
    lazy var widthConstraint = view.widthAnchor.constraint(equalToConstant: 300)
    init(_ side: Side) { self.side = side }
  }
  unowned let mainWindow: MainWindowController
  let leadingSidebar = Panel(.leading)
  let trailingSidebar = Panel(.trailing)
  var sideBars: [Panel] { [leadingSidebar, trailingSidebar] }
  var isAnyVisibleOrTransitioning: Bool {
    sideBars.contains { $0.status != .hidden || $0.animationState == .willHide }
  }
  var useFadeForSidebar = false
  init(mainWindow: MainWindowController) { self.mainWindow = mainWindow }
  func sideBar(for side: Side) -> Panel { side == .leading ? leadingSidebar : trailingSidebar }
  func resizeHandleRect(for side: Side) -> NSRect {
    let view = sideBar(for: side).view
    return NSRect(x: side == .leading ? view.frame.maxX : view.frame.minX - 4,
                  y: view.frame.minY, width: 4, height: view.frame.height)
  }
  private var headers: [ObjectIdentifier: HeaderFixture] = [:]
  private func viewController(for type: ViewType) -> HeaderFixture? {
    guard let panel = sideBars.first(where: { $0.status == type }) else { return nil }
    let key = ObjectIdentifier(panel.view)
    if headers[key] == nil { headers[key] = HeaderFixture(panel.view) }
    return headers[key]
  }
// PRODUCTION_SIDEBAR_STACKING
}
class PluginSidebarView: NSView {}
class VolumeButton: NSView {}
class OSCFloatingView: ClickView {
  weak var mainWindow: MainWindowController!
  private var backgroundClickTimer: Timer?
  var windowSessionEnded = false, isDragging = false
  // Keep the production drag lifetime while exercising native window dispatch.
  override func mouseDown(with event: NSEvent) {
    isDragging = true
    super.mouseDown(with: event)
  }
  override func mouseUp(with event: NSEvent) {
    isDragging = false
    super.mouseUp(with: event)
  }
  func resetPosition() {}
// PRODUCTION_OSC_BACKGROUND_CLICK
// PRODUCTION_OSC_SECONDARY_CLICK
  var isReturningToDefault = false
  var preservedPositions = 0
  func preservePositionAfterPanelReordering() { preservedPositions += 1 }
  func updatePosition() {}
}
class Titlebar: ClickView {
  weak var mainWindow: MainWindowController!
  var isRevealed = true
  private var backgroundPressOrigin: NSPoint?
  private var backgroundPressDidDrag = false
  private var backgroundClickTimer: Timer?
  private var titlebarContainer: NSView { self }
  let docIcon = NSImageView(frame: NSRect(x: 90, y: 4, width: 16, height: 20))
  let titleTextField = NSTextField(frame: NSRect(x: 110, y: 4, width: 100, height: 20))
// PRODUCTION_TITLEBAR_BACKGROUND
}
class ClickView: NSView {
  var clicks = 0, ups = 0, drags = 0
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { clicks += 1 }
  override func mouseUp(with event: NSEvent) { ups += 1 }
  override func mouseDragged(with event: NSEvent) { drags += 1 }
}
class WheelEvent: NSEvent {
  var point = NSPoint.zero
  override var type: NSEvent.EventType { .scrollWheel }
  override var phase: NSEvent.Phase { [] }
  override var momentumPhase: NSEvent.Phase { [] }
  override var locationInWindow: NSPoint { point }
}
class ActionCounter: NSObject {
  var count = 0
  @objc func clicked(_ sender: Any?) { count += 1 }
}
final class PlaylistRows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int { 2 }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    NSTextField(labelWithString: "Playlist item \(row)")
  }
}
let window = MainWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 300),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let controller = MainWindowController(window: window)
window.windowController = controller
let content = window.contentView!
let sidebars = controller.sidebars
let left = sidebars.leadingSidebar.view, right = sidebars.trailingSidebar.view
let video = ClickView(frame: content.bounds)
let header = Titlebar(frame: NSRect(x: 0, y: 270, width: 480, height: 30))
header.mainWindow = controller
controller.titleBarView = header
let osc: OSCFloatingView = controller.oscFloatingView
osc.mainWindow = controller
osc.frame = NSRect(x: 40, y: 10, width: 270, height: 40)
for view in [video, osc, right, left, header] { content.addSubview(view) }
left.frame = NSRect(x: 0, y: 0, width: 300, height: 270)
right.frame = NSRect(x: 180, y: 0, width: 300, height: 270)
sidebars.leadingSidebar.status = .plugins
sidebars.trailingSidebar.status = .settings
let leftContent = ClickView(frame: left.bounds), rightContent = ClickView(frame: right.bounds)
left.addSubview(leftContent); right.addSubview(rightContent)
let width = left.widthAnchor.constraint(equalToConstant: 300); width.isActive = true
window.orderFrontRegardless()
func mouse(_ type: NSEvent.EventType, _ point: NSPoint, count: Int = 1) -> NSEvent {
  NSEvent.mouseEvent(with: type, location: content.convert(point, to: nil), modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
    context: nil, eventNumber: checks + 1, clickCount: count, pressure: 1)!
}
func click(_ point: NSPoint, count: Int = 1) {
  window.sendEvent(mouse(.leftMouseDown, point, count: count))
  window.sendEvent(mouse(.leftMouseUp, point, count: count))
}
func rightClick(_ point: NSPoint) {
  window.sendEvent(mouse(.rightMouseDown, point))
  window.sendEvent(mouse(.rightMouseUp, point))
}
func hit(_ point: NSPoint) -> NSView? {
  content.hitTest(content.superview!.convert(content.convert(point, to: nil), from: nil))
}
func index(_ view: NSView) -> Int { content.subviews.firstIndex(of: view)! }
let overlap = NSPoint(x: 240, y: 170)
let rightPoint = NSPoint(x: 440, y: 170)
let leftPoint = NSPoint(x: 40, y: 170)
check(hit(overlap) === leftContent, "initial left-over-right order")
let initialOrder = content.subviews
rightClick(rightPoint)
check(content.subviews == initialOrder && controller.secondaryRequests == 0,
      "sidebar secondary click preserves depth and stays out of video actions")
window.sendEvent(mouse(.leftMouseDown, rightPoint))
check(hit(overlap) === rightContent && rightContent.clicks == 1,
      "primary press promotes its actual sidebar immediately and reaches its content")
window.sendEvent(mouse(.leftMouseUp, rightPoint))
check(rightContent.ups == 1 && controller.restoreRequests == 0,
      "primary release retains its action without revealing manually hidden OSC")
click(leftPoint)
check(hit(overlap) === leftContent, "primary left-sidebar press promotes only the left sidebar")
window.sendEvent(mouse(.leftMouseDown, rightPoint))
window.sendEvent(mouse(.leftMouseDragged, NSPoint(x: 450, y: 175)))
window.sendEvent(mouse(.leftMouseUp, NSPoint(x: 450, y: 175)))
check(hit(overlap) === rightContent && rightContent.drags == 1,
      "a primary drag promotes its owner and retains the drag")
check(width.isActive && left.constraints.contains(width), "reordering preserves layout constraints")
let counter = ActionCounter()
let button = NSButton(frame: NSRect(x: 230, y: 90, width: 60, height: 30))
button.target = counter; button.action = #selector(ActionCounter.clicked(_:)); button.sendAction(on: [.leftMouseDown])
rightContent.addSubview(button)
click(leftPoint)
let buttonPoint = NSPoint(x: 440, y: 105)
app.postEvent(mouse(.leftMouseUp, buttonPoint), atStart: true)
window.sendEvent(mouse(.leftMouseDown, buttonPoint))
check(counter.count == 1 && hit(overlap) === rightContent,
      "first native button press both promotes its sidebar and performs its action exactly once")
let slider = NSSlider(frame: NSRect(x: 230, y: 150, width: 60, height: 20))
rightContent.addSubview(slider)
click(leftPoint)
check(!sidebars.handlePanelMouseEvent(mouse(.leftMouseDown, NSPoint(x: 440, y: 160))) && hit(overlap) === rightContent,
      "slider press promotes its sidebar without consuming slider tracking")
sidebars.handlePanelMouseEvent(mouse(.leftMouseUp, NSPoint(x: 440, y: 160)))
let field = NSTextField(frame: NSRect(x: 230, y: 210, width: 60, height: 25))
rightContent.addSubview(field)
click(leftPoint)
check(!sidebars.handlePanelMouseEvent(mouse(.leftMouseDown, NSPoint(x: 440, y: 220))) && hit(overlap) === rightContent,
      "editable field press promotes its sidebar without consuming editing input")
sidebars.handlePanelMouseEvent(mouse(.leftMouseUp, NSPoint(x: 440, y: 220)))
let webRoot = PluginSidebarView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
let webChild = ClickView(frame: webRoot.bounds); webRoot.addSubview(webChild); leftContent.addSubview(webRoot)
click(NSPoint(x: 20, y: 70))
check(hit(overlap) === leftContent && webChild.clicks == 1,
      "plugin descendants promote their native sidebar without waiting for DOM background classification")
webRoot.removeFromSuperview()
let nativeScroll = NSScrollView(frame: rightContent.bounds)
let playlistTable = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
let playlistRows = PlaylistRows()
playlistTable.style = .fullWidth; playlistTable.headerView = nil
playlistTable.rowHeight = 30; playlistTable.allowsEmptySelection = true
playlistTable.addTableColumn(NSTableColumn(identifier: .init("trackName")))
playlistTable.dataSource = playlistRows; playlistTable.delegate = playlistRows
nativeScroll.documentView = playlistTable; rightContent.addSubview(nativeScroll)
playlistTable.reloadData(); content.layoutSubtreeIfNeeded()
for y: CGFloat in [15, 150] {
  click(leftPoint)
  let point = content.convert(playlistTable.convert(NSPoint(x: 250, y: y), to: nil), from: nil)
  check(!sidebars.handlePanelMouseEvent(mouse(.leftMouseDown, point)) && index(right) > index(left),
        "populated and empty playlist rows both promote their sidebar without swallowing input (y=\(y))")
  sidebars.handlePanelMouseEvent(mouse(.leftMouseUp, point))
}
nativeScroll.removeFromSuperview(); slider.removeFromSuperview(); field.removeFromSuperview()
let wheel = WheelEvent(); wheel.point = content.convert(leftPoint, to: nil)
let beforeWheel = content.subviews
window.sendEvent(wheel)
check(content.subviews == beforeWheel, "scrolling alone preserves depth")
for count in [2, 3, 0, 1] {
  sidebars.bringPanelToFront(left)
  click(rightPoint, count: count)
  check(index(right) > index(left), "every primary click count promotes its sidebar (count=\(count))")
}
left.isHidden = true
let oscPoint = NSPoint(x: 100, y: 30)
check(hit(oscPoint) === osc, "OSC has an exposed background area")
let beforeOSC = content.subviews
let hides = controller.hideRequests
click(oscPoint)
check(controller.hideRequests == hides + 1 && content.subviews == beforeOSC,
      "primary OSC click with no double action waits for mouseUp to finish dragging before hiding")
rightClick(oscPoint)
check(index(osc) > index(right), "secondary OSC background click raises it over the covering sidebar")
click(rightPoint)
check(index(right) > index(osc), "primary sidebar click raises it above OSC again")
let beforeCovered = controller.hideRequests
click(NSPoint(x: 240, y: 30))
check(controller.hideRequests == beforeCovered && hit(NSPoint(x: 240, y: 30)) === rightContent,
      "covered OSC cannot steal a sidebar click")
left.isHidden = false
content.addSubview(left, positioned: .below, relativeTo: osc)
click(rightPoint)
check(index(left) < index(osc) && index(osc) < index(right),
      "independent sidebars retain a left-OSC-right staircase")
left.isHidden = true
let frames = [left.frame, right.frame, osc.frame]
rightClick(oscPoint)
check([left.frame, right.frame, osc.frame] == frames, "OSC promotion preserves every panel position")
check(content.subviews.last === header, "titlebar stays above all panels")
osc.addSubview(controller.playSlider); osc.addSubview(controller.volumeSlider)
controller.playSlider.frame.origin.x = 150; controller.volumeSlider.frame.origin.x = 220
click(rightPoint)
func scroll(_ x: CGFloat) {
  let event = WheelEvent(); event.point = osc.convert(NSPoint(x: x, y: 20), to: nil)
  controller.scrollWheel(with: event)
}
let initialScrolls = controller.scrollActions
scroll(180); scroll(250)
check(controller.scrollActions == initialScrolls, "covered OSC sliders reject wheel actions")
rightClick(oscPoint)
scroll(180); scroll(250)
check(controller.scrollActions == initialScrolls + 2, "raised OSC sliders retain wheel input")
click(rightPoint)
let oscButton = NSButton(frame: NSRect(x: 10, y: 5, width: 40, height: 30))
oscButton.target = counter; oscButton.action = #selector(ActionCounter.clicked(_:)); oscButton.sendAction(on: [.leftMouseDown])
osc.addSubview(oscButton)
let exposedButton = NSPoint(x: 70, y: 30)
app.postEvent(mouse(.leftMouseUp, exposedButton), atStart: true)
window.sendEvent(mouse(.leftMouseDown, exposedButton))
check(counter.count == 2 && index(right) > index(osc), "OSC button acts without primary-click promotion")
oscButton.removeFromSuperview(); controller.playSlider.removeFromSuperview(); controller.volumeSlider.removeFromSuperview()
check(controller.restoreRequests == 0, "sidebar interactions never cancel persistent OSC hiding")
controller.hideRequests = 0
// Primary titlebar clicks hide only after the double-click window; events pass through.
let titlePoint = NSPoint(x: 420, y: 285)
let orderBeforeTitleClick = content.subviews
click(titlePoint)
check(controller.hideRequests == 0, "primary titlebar click waits for a possible double click")
wait(NSEvent.doubleClickInterval + 0.05)
check(controller.hideRequests == 1, "completed primary titlebar click hides UI")
click(titlePoint); click(titlePoint, count: 2)
wait(NSEvent.doubleClickInterval + 0.05)
check(controller.hideRequests == 1, "double click cancels background hiding")
check(!header.handleBackgroundMouseEvent(mouse(.leftMouseDown, titlePoint, count: 2)),
      "double-click remains available to AppKit")
window.sendEvent(mouse(.rightMouseDown, titlePoint))
window.sendEvent(mouse(.rightMouseUp, titlePoint))
check(controller.hideRequests == 1, "secondary titlebar click does not hide UI")
check(content.subviews == orderBeforeTitleClick, "titlebar clicks retain panel layers")
window.sendEvent(mouse(.leftMouseDown, titlePoint))
window.sendEvent(mouse(.leftMouseDragged, NSPoint(x: 430, y: 285)))
window.sendEvent(mouse(.leftMouseDragged, titlePoint))
window.sendEvent(mouse(.leftMouseUp, titlePoint))
wait(NSEvent.doubleClickInterval + 0.05)
check(controller.hideRequests == 1, "titlebar drag never hides UI even after returning to origin")
let titleButton = NSButton(frame: NSRect(x: 360, y: 2, width: 40, height: 26))
header.addSubview(titleButton)
check(!header.handleBackgroundMouseEvent(mouse(.leftMouseDown, NSPoint(x: 380, y: 285))),
      "titlebar control retains primary clicks")
_ = header.handleBackgroundMouseEvent(mouse(.leftMouseUp, NSPoint(x: 380, y: 285)))
wait(NSEvent.doubleClickInterval + 0.05)
check(controller.hideRequests == 1, "titlebar control cannot hide UI")
titleButton.removeFromSuperview()
controller.interactiveMode.isActive = true
click(titlePoint)
wait(NSEvent.doubleClickInterval + 0.05)
check(controller.hideRequests == 1, "interactive mode excludes titlebar hide")
controller.interactiveMode.isActive = false
header.isRevealed = false
click(titlePoint)
wait(NSEvent.doubleClickInterval + 0.05)
check(controller.hideRequests == 1, "unrevealed titlebar cannot request another hide")
header.isRevealed = true
// PRODUCTION_WEB_BACKGROUND_SCRIPT
class WebMessageRecorder: NSObject, WKScriptMessageHandler {
  var clicks = 0
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { clicks += 1 }
}
let recorder = WebMessageRecorder()
let webConfiguration = WKWebViewConfiguration()
webConfiguration.userContentController.add(recorder, name: "iinaPanelBackground")
webConfiguration.userContentController.addUserScript(WKUserScript(source: backgroundScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 250), configuration: webConfiguration)
content.addSubview(web)
web.loadHTMLString("""
<html><body><div id='bg' style='height:100px'>Panel caption</div><button id='button'><span id='child'>Action</span></button>
<input id='range' type='range'><input id='text'><div role='button' id='role'>Custom</div><div id='pointer' style='cursor:pointer'>Custom action</div>
<canvas id='canvas'></canvas><div id='cancel'>Handled by plugin</div><script>
document.getElementById('cancel').addEventListener('click', e => e.preventDefault());
window.testClick = (id, drag = false, detail = 1) => {
 const e = document.getElementById(id);
 e.dispatchEvent(new PointerEvent('pointerdown', { bubbles:true, composed:true, button:0, clientX:20, clientY:20 }));
 if (drag) e.dispatchEvent(new PointerEvent('pointermove', { bubbles:true, composed:true, clientX:40, clientY:20 }));
 e.dispatchEvent(new MouseEvent('click', { bubbles:true, composed:true, cancelable:true, button:0, detail, clientX:20, clientY:20 }));
};
</script></body></html>
""", baseURL: nil)
let webDeadline = Date().addingTimeInterval(5)
while web.isLoading && Date() < webDeadline { wait(0.01) }
func javascript(_ code: String) {
  var done = false
  web.evaluateJavaScript(code) { _, error in check(error == nil, "WebKit script executes"); done = true }
  let deadline = Date().addingTimeInterval(5)
  while !done && Date() < deadline { wait(0.01) }
  check(done, "WebKit response arrives"); wait(0.03)
}
javascript("testClick('bg')")
check(recorder.clicks == 1, "plugin DOM background reports activation")
for id in ["button", "child", "range", "text", "role", "pointer", "canvas", "cancel"] {
  javascript("testClick('\(id)')")
  check(recorder.clicks == 1, "plugin interactive element \(id) preserves panel order")
}
javascript("testClick('bg', true)")
check(recorder.clicks == 1, "plugin background drag does not activate")
javascript("testClick('bg', false, 2)")
check(recorder.clicks == 1, "plugin background double click does not activate")
javascript("""
window.rightClick = (id, drag = false) => {
 const e = document.getElementById(id);
 e.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true, composed:true, button:2, clientX:20, clientY:20}));
 if (drag) e.dispatchEvent(new PointerEvent('pointermove', {bubbles:true, composed:true, clientX:40, clientY:20}));
 e.dispatchEvent(new PointerEvent('pointerup', {bubbles:true, composed:true, button:2, clientX:20, clientY:20}));
};
rightClick('bg');
""")
check(recorder.clicks == 1, "plugin secondary background click stays entirely inside the web view")
for id in ["button", "range", "role", "pointer", "canvas"] {
  javascript("rightClick('\(id)')")
  check(recorder.clicks == 1, "plugin secondary control click preserves depth: \(id)")
}
javascript("rightClick('bg', true)")
check(recorder.clicks == 1, "plugin secondary drag cannot raise its sidebar")
javascript("""
let ownedMenus = 0;
document.getElementById('bg').addEventListener('contextmenu', event => {
  ownedMenus++; event.preventDefault();
});
const menuEvent = new MouseEvent('contextmenu', {bubbles:true, cancelable:true, button:2});
document.getElementById('bg').dispatchEvent(menuEvent);
if (ownedMenus !== 1 || !menuEvent.defaultPrevented) throw new Error('Plugin context menu was intercepted');
""")
check(recorder.clicks == 1, "plugin keeps its context-menu handler without host layer activation")
webConfiguration.userContentController.removeScriptMessageHandler(forName: "iinaPanelBackground")
window.close()
print("Completed \(checks) background panel, titlebar and WebKit checks.")
