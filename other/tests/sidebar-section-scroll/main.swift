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


print("PASS: \(checks) native sidebar navigation checks")
