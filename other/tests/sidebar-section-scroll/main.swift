import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS: \(message)")
}
var eventTime: TimeInterval = 0
func wheel(_ x: CGFloat, _ y: CGFloat = 0, phase: NSEvent.Phase = [],
           momentum: NSEvent.Phase = [], precise: Bool = false) -> WheelEvent {
  let event = WheelEvent()
  event.x = x; event.y = y; event.inputPhase = phase; event.momentum = momentum
  event.precise = precise; eventTime += 0.01; event.time = eventTime
  return event
}
class PaneFixture: NSView, SidebarPane {
  let scrollView = SidebarSectionScrollView()
  var horizontalScroll: ((NSEvent) -> Bool)? {
    didSet { scrollView.horizontalScroll = horizontalScroll }
  }
  override init(frame: NSRect) {
    super.init(frame: frame)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    addSubview(scrollView)
    scrollView.padding(.all)
    let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 360, height: 2000))
    scrollView.documentView = document
  }
  required init?(coder: NSCoder) { fatalError() }
}
class TableRows: NSObject, NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int { 50 }
  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { "Row \(row)" }
}
class RoutingTableView: NSTableView {
  var wheelEvents = 0
  override func scrollWheel(with event: NSEvent) {
    wheelEvents += 1
    super.scrollWheel(with: event)
  }
}
class ControllerFixture: SidebarViewController {
  let count: Int
  var panes: [PaneFixture] = []
  init(_ count: Int, mainWindow: MainWindowController) { self.count = count; super.init(mainWindow: mainWindow) }
  required init?(coder: NSCoder) { fatalError() }
  override var sidebarType: SidebarController.ViewType { .playlist }
  override var leadingPrefKey: Preference.Key { .sidebarPlaylistDisplayAtLeading }
  override var allTabs: [TabType] { (0..<count).map { TabType($0, "tab\($0)", .sf("list.bullet")!) } }
  override var defaultTab: TabType { allTabs[0] }
  override func getTabView(for tab: TabType) -> SidebarPane {
    let pane = PaneFixture(frame: .zero); panes.append(pane); return pane
  }
}

for tabCount in [2, 4] {
  let owner = MainWindowController()
  let controller = ControllerFixture(tabCount, mainWindow: owner)
  let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 600),
                        styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView!.addSubview(controller.view)
  controller.view.padding(.all)
  window.contentView!.layoutSubtreeIfNeeded()
  window.orderFrontRegardless()
  func selected() -> Int { controller.currentTab.tag }
  func scroll(_ event: WheelEvent) {
    let pane = controller.panes[selected()]
    event.point = pane.scrollView.convert(NSPoint(x: 180, y: 200), to: nil)
    pane.scrollView.scrollWheel(with: event)
  }
  scroll(wheel(-1))
  check(selected() == 1 && controller.tabButtonsSegmentControl.selectedSegment == 1,
        "native side wheel selects the next \(tabCount)-section pane and updates the capsule")
  scroll(wheel(1))
  check(selected() == 0, "native side wheel selects the previous section")
  scroll(wheel(1))
  check(selected() == 0, "first section remains bounded")
  for _ in 0..<tabCount + 2 { scroll(wheel(-1)) }
  check(selected() == tabCount - 1, "last section remains bounded")
  controller.switchToTab(controller.allTabs[0])
  scroll(wheel(-10, phase: .began, precise: true))
  scroll(wheel(-75, phase: .changed, precise: true))
  check(selected() == 0, "trackpad preserves release-to-switch behavior")
  scroll(wheel(0, phase: .ended, precise: true))
  check(selected() == 1, "trackpad release switches one section")
  for _ in 0..<5 { scroll(wheel(-100, momentum: .changed, precise: true)) }
  check(selected() == 1, "trackpad momentum cannot skip sections after a pane change")
  scroll(wheel(90, phase: .began, precise: true))
  scroll(wheel(0, phase: .ended, precise: true))
  check(selected() == 0, "first trackpad sample is counted for a reverse gesture")
  scroll(wheel(-100, phase: .began, precise: true))
  scroll(wheel(0, phase: .cancelled, precise: true))
  check(selected() == 0, "cancelled gesture leaves selection unchanged")
  scroll(wheel(-20, phase: .began, precise: true))
  scroll(wheel(0, phase: .ended, precise: true))
  check(selected() == 0, "small horizontal gesture does not switch")
  let pane = controller.panes[0]
  let scrollBefore = pane.scrollView.contentView.bounds.origin
  // Native NSScrollView reads the underlying scroll data, unlike our classifier fixtures.
  let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                   wheel1: -60, wheel2: 0, wheel3: 0)!
  pane.scrollView.scrollWheel(with: NSEvent(cgEvent: cg)!)
  let verticalDeadline = Date().addingTimeInterval(0.5)
  while pane.scrollView.contentView.bounds.origin == scrollBefore && Date() < verticalDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
  }
  check(selected() == 0 && pane.scrollView.contentView.bounds.origin != scrollBefore,
        "vertical scrolling still moves native content without switching sections")
  scroll(wheel(-10, -80, phase: .began, precise: true))
  scroll(wheel(-100, -5, phase: .changed, precise: true))
  scroll(wheel(0, phase: .ended, precise: true))
  check(selected() == 0, "vertical gesture cannot turn into tab navigation halfway through")
  eventTime += 0.3
  scroll(wheel(-6, precise: true)); scroll(wheel(-6, precise: true))
  check(selected() == 1, "precise side wheel without phases accumulates a small threshold")
  for _ in 0..<5 { scroll(wheel(-30, precise: true)) }
  check(selected() == 1, "phase-free precise burst switches only once across different panes")
  scroll(wheel(12, precise: true))
  check(selected() == 0, "reversing precise side wheel starts a new intentional step")
  let header = controller.tabButtonsSegmentControl as! SidebarTabSelectorControl
  header.scrollWheel(with: wheel(-1))
  check(selected() == 1, "horizontal wheel over the capsule also navigates")
  (controller.view as! SidebarSectionView).scrollWheel(with: wheel(1))
  check(selected() == 0, "horizontal wheel over header background shares the navigation")
  let duplicate = wheel(-1)
  pane.scrollView.scrollWheel(with: duplicate)
  (controller.view as! SidebarSectionView).scrollWheel(with: duplicate)
  check(selected() == 1, "the same bubbling event cannot navigate twice")
  let nested = NSScrollView(frame: NSRect(x: 10, y: 100, width: 200, height: 40))
  nested.hasHorizontalScroller = true
  nested.documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: 40))
  controller.panes[selected()].addSubview(nested)
  let stripEvent = wheel(-1)
  stripEvent.point = nested.convert(NSPoint(x: 50, y: 20), to: nil)
  controller.panes[selected()].scrollView.scrollWheel(with: stripEvent)
  check(selected() == 1, "nested horizontal strips retain their own scrolling at an edge")
  nested.removeFromSuperview()
  controller.switchToTab(controller.allTabs[0])
  header.scrollWheel(with: wheel(-10, phase: .began, precise: true))
  scroll(wheel(-80, phase: .changed, precise: true))
  header.scrollWheel(with: wheel(0, phase: .ended, precise: true))
  check(selected() == 1, "a gesture crossing header and content uses one shared state")
  eventTime += 0.3
  scroll(wheel(-12, precise: true))
  let burstSelection = selected()
  scroll(wheel(-12, precise: true))
  check(selected() == burstSelection, "same precise burst remains limited to one step")
  eventTime += 0.3
  scroll(wheel(-12, precise: true))
  check(selected() == min(burstSelection + 1, tabCount - 1), "a separate precise wheel burst can advance again")
  Preference.animationsDisabled = false
  controller.switchToTab(controller.allTabs[0])
  scroll(wheel(-1)); scroll(wheel(-1))
  RunLoop.main.run(until: Date().addingTimeInterval(0.35))
  let animatedSelection = min(2, tabCount - 1)
  check(selected() == animatedSelection && controller.tabViewController.selectedTabViewItemIndex == animatedSelection &&
        !controller.panes[animatedSelection].isHiddenOrHasHiddenAncestor,
        "rapid native wheel steps keep animated content and capsule selection aligned")
  Preference.animationsDisabled = true
  controller.switchToTab(controller.allTabs[0])
  let nativeTable = RoutingTableView(frame: NSRect(x: 0, y: 0, width: 360, height: 2000))
  let rows = TableRows()
  nativeTable.dataSource = rows
  nativeTable.addTableColumn(NSTableColumn(identifier: .init("test")))
  nativeTable.headerView = nil
  controller.panes[0].scrollView.documentView = nativeTable
  nativeTable.reloadData()
  window.contentView!.layoutSubtreeIfNeeded()
  let nativeWheel = wheel(-1)
  nativeWheel.targetWindow = window
  nativeWheel.backingEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                    wheel1: 0, wheel2: -1, wheel3: 0)
  nativeWheel.point = controller.panes[0].scrollView.convert(NSPoint(x: 150, y: 250), to: nil)
  window.sendEvent(nativeWheel)
  check(nativeTable.wheelEvents > 0 && selected() == 1,
        "native window dispatch through a real table reaches the section handler")
  window.close()
}

// Track lists are nested scroll views inside settings, unlike the outer playlist table.
// Dispatch through the real production table, clip view and track selector.
for trackType in [MPVTrack.TrackType.video, .audio, .sub, .secondSub] {
  let owner = MainWindowController()
  let controller = ControllerFixture(4, mainWindow: owner)
  let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 600),
                        styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView!.addSubview(controller.view)
  controller.view.padding(.all)
  controller.switchToTab(controller.allTabs[2])
  let outer = controller.panes[2].scrollView
  let tracks = TrackSelector(trackType, player: owner.player, observedKeys: [])
  let container = SidebarScrollView.Container(tracks) { $0.padding(.all) }
  outer.documentView!.addSubview(container)
  container.padding(.top(40), .leading(15), .trailing(15))
  let table = tracks.documentView as! NSTableView
  table.reloadData()
  window.contentView!.layoutSubtreeIfNeeded()
  window.orderFrontRegardless()
  func selected() -> Int { controller.currentTab.tag }
  func dispatch(_ event: WheelEvent) {
    event.targetWindow = window
    event.point = tracks.convert(NSPoint(x: tracks.bounds.midX, y: tracks.bounds.midY), to: nil)
    event.backingEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                wheel1: Int32(event.y), wheel2: Int32(event.x), wheel3: 0)
    window.sendEvent(event)
  }
  dispatch(wheel(1))
  check(selected() == 1, "\(trackType) nested track list forwards native side wheel to its section")
  controller.switchToTab(controller.allTabs[2])
  let horizontalOrigin = tracks.contentView.bounds.origin
  dispatch(wheel(15, phase: .began, precise: true))
  dispatch(wheel(70, phase: .changed, precise: true))
  check(selected() == 2 && tracks.contentView.bounds.origin == horizontalOrigin,
        "\(trackType) nested track list consumes horizontal swipe until release")
  dispatch(wheel(0, phase: .ended, precise: true))
  check(selected() == 1, "\(trackType) nested track list forwards the zero-delta gesture release")
  // Momentum is delivered to the newly visible pane after the section switch.
  let momentum = wheel(100, momentum: .changed, precise: true)
  momentum.point = controller.panes[1].scrollView.convert(NSPoint(x: 100, y: 100), to: nil)
  controller.panes[1].scrollView.scrollWheel(with: momentum)
  check(selected() == 1, "\(trackType) nested gesture does not switch again during momentum")
  controller.switchToTab(controller.allTabs[2])
  dispatch(wheel(90, phase: .began, precise: true))
  dispatch(wheel(0, phase: .cancelled, precise: true))
  check(selected() == 2, "\(trackType) cancelled nested swipe preserves the section")
  let verticalOrigin = tracks.contentView.bounds.origin
  let outerOrigin = outer.contentView.bounds.origin
  dispatch(wheel(0, -60))
  let deadline = Date().addingTimeInterval(0.5)
  while tracks.contentView.bounds.origin == verticalOrigin && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
  }
  check(selected() == 2 && tracks.contentView.bounds.origin != verticalOrigin &&
        outer.contentView.bounds.origin == outerOrigin,
        "\(trackType) vertical wheel scrolls the nested native list rather than its parent")
  // Minor table overflow must not classify a vertical list as an Aspect/Crop strip.
  table.setFrameSize(NSSize(width: tracks.contentView.bounds.width + 4, height: table.frame.height))
  dispatch(wheel(1))
  check(selected() == 1, "\(trackType) a slightly wider table still permits section navigation")
  check(owner.player.trackChanges == 0, "\(trackType) section gestures do not select another media track")
  controller.switchToTab(controller.allTabs[2])
  // Resize inside the real NSBox and scrolled sidebar, without changing section/playback.
  let resizeHandle = tracks.subviews.compactMap { $0 as? TrackListResizeHandle }.first!
  let start = resizeHandle.convert(NSPoint(x:resizeHandle.bounds.midX,y:resizeHandle.bounds.midY),to:nil)
  let end = NSPoint(x:start.x,y:start.y-55)
  func resizeEvent(_ type:NSEvent.EventType,_ point:NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:eventTime,
                      windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  }
  check(window.contentView!.hitTest(window.contentView!.convert(start,from:nil)) === resizeHandle,
        "\(trackType) boxed list exposes its bottom resize edge")
  NSApp.postEvent(resizeEvent(.leftMouseUp,end),atStart:true)
  NSApp.postEvent(resizeEvent(.leftMouseDragged,end),atStart:true)
  window.sendEvent(resizeEvent(.leftMouseDown,start))
  window.contentView!.layoutSubtreeIfNeeded()
  check(abs(tracks.frame.height-182)<0.1 && selected()==2 && owner.player.trackChanges==0,
        "\(trackType) nested resizing grows the list without a tab or playback action")
  owner.player.info.tracks = []
  owner.player.postNotification(.iinaTracklistChanged)
  window.contentView!.layoutSubtreeIfNeeded()
  dispatch(wheel(1))
  check(selected() == 1, "\(trackType) a list containing only None still forwards horizontal scrolling")
  controller.switchToTab(controller.allTabs[2])
  for count in [0, 2, 6] {
    owner.player.info.tracks = (0..<count).map { MPVTrack(id:$0+1) }
    owner.player.postNotification(.iinaTracklistChanged)
    window.contentView!.layoutSubtreeIfNeeded()
    outer.contentView.scroll(to:.zero);outer.reflectScrolledClipView(outer.contentView)
    let before = outer.contentView.bounds.origin
    let innerBefore = tracks.contentView.bounds.origin
    dispatch(wheel(0,-35))
    let deadline = Date().addingTimeInterval(0.5)
    while outer.contentView.bounds.origin == before && Date() < deadline {
      RunLoop.main.run(until:Date().addingTimeInterval(0.005))
    }
    check(outer.contentView.bounds.origin != before && tracks.contentView.bounds.origin == innerBefore && selected() == 2,
          "\(trackType) \(count) fitting rows forward vertical wheel to the sidebar without a track or section action")
  }
  window.close()
}

// Aspect Ratio and Crop use this exact production horizontal viewport.
let stripOwner = MainWindowController()
let stripController = ControllerFixture(4,mainWindow:stripOwner)
let stripWindow = NSWindow(contentRect:NSRect(x:100,y:100,width:360,height:600),styleMask:[.borderless],backing:.buffered,defer:false)
stripWindow.isReleasedWhenClosed = false
stripWindow.contentView!.addSubview(stripController.view);stripController.view.padding(.all)
stripController.switchToTab(stripController.allTabs[1])
let stripOuter = stripController.panes[1].scrollView
private let strip = HorizontalScrollViewWithIndicator()
stripOuter.documentView!.addSubview(strip)
strip.padding(.top(40),.leading(15)).size(width:260,height:32)
strip.scrollView.documentView = FlippedView(frame:NSRect(x:0,y:0,width:800,height:40))
stripWindow.contentView!.layoutSubtreeIfNeeded();stripWindow.orderFrontRegardless()
func dispatchStrip(_ event:WheelEvent) {
  event.targetWindow = stripWindow
  event.point = strip.scrollView.convert(NSPoint(x:70,y:15),to:nil)
  event.backingEvent = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,
                              wheel1:Int32(event.y),wheel2:Int32(event.x),wheel3:0)
  stripWindow.sendEvent(event)
}
let beforeStrip = strip.scrollView.contentView.bounds.origin
let beforeSidebar = stripOuter.contentView.bounds.origin
dispatchStrip(wheel(0,-40))
let stripDeadline = Date().addingTimeInterval(0.5)
while stripOuter.contentView.bounds.origin == beforeSidebar && Date() < stripDeadline {
  RunLoop.main.run(until:Date().addingTimeInterval(0.005))
}
check(stripOuter.contentView.bounds.origin != beforeSidebar && strip.scrollView.contentView.bounds.origin == beforeStrip && stripController.currentTab.tag == 1,
      "vertical wheel over the real Aspect/Crop viewport moves the sidebar, not its horizontal contents or section")
stripOuter.contentView.scroll(to:.zero);stripOuter.reflectScrolledClipView(stripOuter.contentView)
let horizontalBefore = strip.scrollView.contentView.bounds.origin
let sidebarBeforeHorizontal = stripOuter.contentView.bounds.origin
dispatchStrip(wheel(-50))
let horizontalDeadline = Date().addingTimeInterval(0.5)
while strip.scrollView.contentView.bounds.origin == horizontalBefore && Date() < horizontalDeadline {
  RunLoop.main.run(until:Date().addingTimeInterval(0.005))
}
check(strip.scrollView.contentView.bounds.origin != horizontalBefore && stripOuter.contentView.bounds.origin == sidebarBeforeHorizontal && stripController.currentTab.tag == 1,
      "horizontal wheel still scrolls Aspect/Crop contents without moving the sidebar or switching sections")
stripOuter.contentView.scroll(to:.zero);stripOuter.reflectScrolledClipView(stripOuter.contentView)
let diagonalBefore = stripOuter.contentView.bounds.origin
dispatchStrip(wheel(1,-40))
let diagonalDeadline = Date().addingTimeInterval(0.5)
while stripOuter.contentView.bounds.origin == diagonalBefore && Date() < diagonalDeadline {
  RunLoop.main.run(until:Date().addingTimeInterval(0.005))
}
check(stripOuter.contentView.bounds.origin != diagonalBefore && stripController.currentTab.tag == 1,
      "vertical scrolling with slight horizontal drift still moves the sidebar")
let diagonalTrackpad = wheel(1,-40,phase:.changed,precise:true)
diagonalTrackpad.targetWindow = stripWindow
diagonalTrackpad.point = strip.scrollView.convert(NSPoint(x:70,y:15),to:nil)
check(stripOuter.horizontalScroll?(diagonalTrackpad) == false,
      "the shared section handler passes a vertical trackpad gesture over Aspect/Crop instead of consuming its slight horizontal drift")
stripWindow.close()
print("Completed \(checks) native sidebar section scrolling checks.")

// The production transition must share the row/selector motion policy.
for reducedMotion in [false, true] {
  Preference.animationsDisabled = false
  AccessibilityPreferences.motionReductionEnabled = reducedMotion
  let controller = SidebarTabViewController()
  let first = NSViewController(), second = NSViewController()
  first.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
  second.view = NSView(frame: first.view.frame)
  controller.addTabViewItem(NSTabViewItem(viewController: first))
  controller.addTabViewItem(NSTabViewItem(viewController: second))
  _ = controller.view
  controller.selectedTabViewItemIndex = 0
  controller.previousIndex = 0
  let container = first.view.superview!
  controller.selectedTabViewItemIndex = 1
  check((container.layer?.animation(forKey: kCATransition) == nil) == reducedMotion,
        "sidebar content push follows Reduce Motion = \(reducedMotion)")
  container.layer?.removeAllAnimations()
}
AccessibilityPreferences.motionReductionEnabled = false
Preference.animationsDisabled = true
print("Sidebar content motion checks complete: \(checks) total checks.")

func sameCurve(_ lhs: CAMediaTimingFunction?, _ rhs: CAMediaTimingFunction?) -> Bool {
  guard let lhs, let rhs else { return false }
  for index in 0...3 {
    var a: [Float] = [0, 0], b: [Float] = [0, 0]
    lhs.getControlPoint(at: index, values: &a)
    rhs.getControlPoint(at: index, values: &b)
    if a != b { return false }
  }
  return true
}

// Inspect the actual attached CA animations, not copies of timing constants.
for count in [2, 4] {
  Preference.animationsDisabled = false
  let owner = MainWindowController()
  let controller = ControllerFixture(count, mainWindow: owner)
  let host = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 600),
                      styleMask: [.titled], backing: .buffered, defer: false)
  host.isReleasedWhenClosed = false
  host.contentView!.addSubview(controller.view)
  controller.view.padding(.all)
  host.orderFrontRegardless()
  host.contentView!.layoutSubtreeIfNeeded()
  CATransaction.flush()
  let selector = controller.tabButtonsSegmentControl as! SidebarTabSelectorControl
  let overlay = selector.subviews.last!
  let capsule = overlay.subviews.first!
  let labels = overlay.subviews.compactMap { $0 as? NSTextField }
  let movingHeader = [capsule] + overlay.subviews.filter { $0 is NSImageView || $0 is NSTextField }
  let container = controller.panes[0].superview!

  for target in [count - 1, 0, 1] {
    let previous = controller.currentTab.tag
    controller.switchToTab(controller.allTabs[target])
    CATransaction.flush()
    let push = container.layer?.animation(forKey: kCATransition) as? CATransition
    check(push?.duration == 0.3 && push?.subtype == (target > previous ? .fromRight : .fromLeft),
          "\(count) tabs: section push keeps its duration and direction, including rapid reversal")
    let animations = movingHeader.flatMap { view in
      (view.layer?.animationKeys() ?? []).compactMap { key in view.layer?.animation(forKey: key) }
    }
    check(!(capsule.layer?.animationKeys() ?? []).isEmpty &&
          labels.contains { ($0.layer?.animationKeys() ?? []).contains("opacity") },
          "\(count) tabs: actual capsule and title fades animate with the section")
    check(animations.allSatisfy { abs($0.duration - push!.duration) < 0.000001 },
          "\(count) tabs: capsule, icon, title frame and opacity finish with the section")
    check(animations.allSatisfy { sameCurve($0.timingFunction, push!.timingFunction) },
          "\(count) tabs: all header components use the section's easing curve")
    check(animations.allSatisfy { abs($0.beginTime - push!.beginTime) < 1.0 / 240 },
          "\(count) tabs: header and section start in the same display transaction")
    let start = capsule.layer?.animation(forKey: "position")?.beginTime
    selector.layoutSubtreeIfNeeded()
    CATransaction.flush()
    check(capsule.layer?.animation(forKey: "position")?.beginTime == start &&
          controller.currentTab.tag == target && selector.selectedSegment == target,
          "\(count) tabs: layout preserves in-flight synchronization and the latest selection")
  }
  host.close()
}

for (disabled, reduced) in [(true, false), (false, true)] {
  Preference.animationsDisabled = disabled
  AccessibilityPreferences.motionReductionEnabled = reduced
  let owner = MainWindowController()
  let controller = ControllerFixture(4, mainWindow: owner)
  let host = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 600),
                      styleMask: [.titled], backing: .buffered, defer: false)
  host.isReleasedWhenClosed = false
  host.contentView!.addSubview(controller.view)
  controller.view.padding(.all)
  host.orderFrontRegardless()
  host.contentView!.layoutSubtreeIfNeeded()
  CATransaction.flush()
  let selector = controller.tabButtonsSegmentControl as! SidebarTabSelectorControl
  let overlay = selector.subviews.last!
  let container = controller.panes[0].superview!
  controller.switchToTab(controller.allTabs[3])
  CATransaction.flush()
  check(container.layer?.animation(forKey: kCATransition) == nil &&
        overlay.subviews.allSatisfy { ($0.layer?.animationKeys() ?? []).isEmpty },
        "Disable animations = \(disabled), Reduce Motion = \(reduced): header and section both switch immediately")
  let labels = overlay.subviews.compactMap { $0 as? NSTextField }
  check(controller.currentTab.tag == 3 && selector.selectedSegment == 3 && labels[3].alphaValue == 1,
        "motion accessibility settings preserve the final selection and visible title")
  host.close()
}
AccessibilityPreferences.motionReductionEnabled = false
Preference.animationsDisabled = true
print("Synchronized sidebar motion checks complete: \(checks) total checks.")
