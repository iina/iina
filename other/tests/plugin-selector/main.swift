import Darwin
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1; print("PASS: \(message)")
}
if CommandLine.arguments.contains("--write-selection") || CommandLine.arguments.contains("--read-selection") {
  let restarted = PluginViewController()
  restarted.player.plugins = [PluginInstance("alpha", "Alpha"), PluginInstance("beta", "Renamed Beta")]
  restarted.beginWindowSession()
  _ = restarted.view
  if CommandLine.arguments.contains("--write-selection") {
    restarted.selectPlugin(withIdentifier: "beta")
    check(Preference.string(for: .lastSelectedPlugin) == "beta", "explicit selection writes its stable identifier")
    check(Preference.ud.synchronize(), "isolated UserDefaults selection flushes to disk")
  } else {
    check(restarted.currentTab.name == "beta", "separate process restores the last selected plugin")
    check(restarted.tabButtonsSegmentControl.label(forSegment: 0) == "Renamed Beta",
          "restoration uses the current display name for the persisted identifier")
    check(restarted.player.plugins[1].sidebarTabView.superview != nil,
          "separate process installs the restored plugin content")
  }
  exit(0)
}
Preference.ud.removePersistentDomain(forName: Preference.domain)
let controller = PluginViewController()
let alpha = PluginInstance("alpha", "Alpha")
let beta = PluginInstance("beta", "Beta")
let gamma = PluginInstance("gamma", "Gamma")
controller.player.plugins = [alpha, PluginInstance("no-panel", nil), beta, gamma]
controller.beginWindowSession()
_ = controller.view
let selector = controller.tabButtonsSegmentControl as! ScrollSelectionControl
let originalCell = selector.cell!
check(type(of: originalCell) == type(of: NSSegmentedControl().cell!), "live control keeps AppKit's native action and accessibility cell")
check(selector.segmentCount == 1, "pill contains only one segment")
check(selector.image(forSegment: 0) != nil, "pill retains plugin icon")
check(controller.allTabs.dropFirst().map(\.name) == ["alpha", "beta", "gamma"], "only sidebar plugins participate, in menu order")
var time: TimeInterval = 1
func wheel(_ y: CGFloat, x: CGFloat = 0, precise: Bool = false, phase: NSEvent.Phase = [],
           momentum: NSEvent.Phase = [], gap: TimeInterval = 0.01) {
  time += gap
  let event = WheelEvent(); event.dy = y; event.dx = x; event.precise = precise
  event.gesturePhase = phase; event.inertia = momentum; event.time = time
  selector.scrollWheel(with: event)
}
check(controller.currentTab.name == "alpha", "first opening selects the first sidebar plugin")
check(selector.label(forSegment: 0) == "Alpha", "label follows selected plugin")
check(alpha.sidebarTabView.superview != nil, "selected plugin's content is installed")
wheel(-1)
check(controller.currentTab.name == "beta" && alpha.sidebarTabView.superview == nil, "wheel down selects next and removes old content")
check(Preference.string(for: .lastSelectedPlugin) == "beta", "wheel selection updates the shared preference")
wheel(1)
check(controller.currentTab.name == "alpha", "wheel up selects previous")
wheel(1)
check(controller.currentTab.name == "gamma", "scrolling above first wraps to last plugin")
controller.switchToTab(controller.allTabs.last!)
wheel(-1)
check(controller.currentTab.name == "alpha", "scrolling below last wraps to first plugin")
for expected in ["beta", "gamma", "alpha", "beta", "gamma", "alpha"] {
  wheel(-1)
  check(controller.currentTab.name == expected, "forward cycle selects \(expected)")
}
for expected in ["gamma", "beta", "alpha", "gamma", "beta", "alpha"] {
  wheel(1)
  check(controller.currentTab.name == expected, "reverse cycle selects \(expected)")
}
controller.switchToTab(controller.allTabs[1])
wheel(-5, precise: true, phase: .began)
check(controller.currentTab.name == "alpha", "small trackpad movement does not switch")
wheel(-8, precise: true, phase: .changed)
check(controller.currentTab.name == "beta", "trackpad accumulation selects next")
wheel(-60, precise: true, phase: .changed, gap: 1)
check(controller.currentTab.name == "beta", "long gesture switches only once")
wheel(-100, precise: true, momentum: .began)
wheel(-100, precise: true, momentum: .changed)
check(controller.currentTab.name == "beta", "momentum never changes selection")
wheel(0, precise: true, phase: .ended)
wheel(15, precise: true, phase: .began)
check(controller.currentTab.name == "alpha", "next gesture can select previous")
wheel(0, precise: true, phase: .cancelled)
wheel(-15, x: 40, precise: true, phase: .began)
check(controller.currentTab.name == "alpha", "horizontal swipe ignored")
wheel(0, precise: true, phase: .ended)
wheel(-15, precise: true, gap: 1)
check(controller.currentTab.name == "beta", "unphased precise wheel supports separate gestures")
wheel(-15, precise: true, gap: 1)
check(controller.currentTab.name == "gamma", "pause resets unphased precise gesture")
selector.isEnabled = false
wheel(1)
check(controller.currentTab.name == "gamma", "disabled selector ignores scroll")
selector.isEnabled = true
let oldBetaTab = controller.allTabs[2]
controller.switchToTab(oldBetaTab)
controller.player.plugins = [gamma, beta, alpha]
controller.updatePluginTabs()
check(controller.currentTab.name == "beta" && controller.currentTab.tag == 2, "reload preserves plugin identity")
wheel(-1)
check(controller.currentTab.name == "alpha", "scroll uses new order after reload")
controller.player.plugins = [alpha, gamma, beta]
controller.updatePluginTabs()
controller.switchToTab(oldBetaTab)
check(controller.currentTab.name == "beta" && controller.currentTab.tag == 3, "stale tab request resolves by identifier")
controller.removePluginTab(withIdentifier: "gamma")
wheel(1)
check(controller.currentTab.name == "alpha", "removing another plugin reindexes navigation")
controller.removePluginTab(withIdentifier: "alpha")
check(controller.currentTab.name == "beta" && selector.label(forSegment: 0) == "Beta", "removing active plugin selects first remaining plugin")
wheel(-1)
check(controller.currentTab.name == "beta", "removed plugin cannot be reselected by scrolling")
controller.player.plugins = []
controller.updatePluginTabs()
wheel(-1); wheel(1)
check(controller.currentTab.tag == 0, "empty plugin list safely ignores scrolling")
controller.player.plugins = [beta]
controller.updatePluginTabs(); wheel(1); wheel(-1); wheel(1)
check(controller.currentTab.name == "beta", "single plugin remains selected at both boundaries")
controller.player.plugins = [alpha, beta, gamma]
controller.updatePluginTabs()
let menu = NSMenu()
for id in ["alpha", "beta", "gamma"] {
  let item = NSMenuItem(title: id, action: nil, keyEquivalent: ""); item.representedObject = id; menu.addItem(item)
}
controller.menuWillOpen(menu)
check(menu.items.map { $0.representedObject as? String } == ["beta", "gamma", "alpha"], "popup starts with active plugin and wraps in original order")
check(menu.items[0].state == .on && menu.items.dropFirst().allSatisfy { $0.state == .off }, "popup checkmark tracks scroll selection")
controller.menuWillOpen(menu)
check(menu.items.map { $0.representedObject as? String } == ["beta", "gamma", "alpha"], "reopening popup preserves cyclic order")
check(controller.allTabs.dropFirst().map(\.name) == ["alpha", "beta", "gamma"], "popup rotation leaves scroll order unchanged")
controller.player.plugins = [alpha, beta, gamma]
controller.updatePluginTabs()
controller.switchToTab(controller.allTabs[2])
class ScaleWindow: NSWindow {
  var testScale: CGFloat = 2
  override var backingScaleFactor: CGFloat { testScale }
}
let window = ScaleWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                      styleMask: [.borderless], backing: .buffered, defer: false)
let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
window.contentView = root
root.autoresizingMask = [.width, .height]
root.addSubview(controller.view)
controller.view.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
  controller.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
  controller.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
  controller.view.topAnchor.constraint(equalTo: root.topAnchor),
  controller.view.bottomAnchor.constraint(equalTo: root.bottomAnchor)
])
controller.tabButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
  controller.tabButtonsStackView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 20),
  controller.tabButtonsStackView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -20),
  controller.tabButtonsStackView.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 20),
  controller.tabButtonsHeightConstraint
])
root.layoutSubtreeIfNeeded()
func run(for duration: TimeInterval) {
  let end = Date().addingTimeInterval(duration)
  while Date() < end {
    RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.005)))
    root.layoutSubtreeIfNeeded()
    CATransaction.flush()
  }
}
func finishAnimations() {
  run(for: 0.55)
  check(!selector.isRolling && !selector.isResizing, "title and width finish without queued work")
}
func overlay() -> NSView { selector.subviews.first { $0 is ScrollSelectionOverlay }! }
func icon() -> NSImageView { overlay().subviews.first { $0 is NSImageView } as! NSImageView }
func mask() -> CALayer { overlay().layer!.sublayers!.first { $0.masksToBounds && $0.isGeometryFlipped }! }
func iconOrigin() -> NSPoint { icon().convert(.zero, to: controller.view) }
func startRoll() {
  selector.roll(through: ["Previous", selector.label(forSegment: 0) ?? ""], direction: 1)
}
func settle(_ title: String) {
  AccessibilityPreferences.disableAnimations = true
  selector.setLabel(title, forSegment: 0)
  root.layoutSubtreeIfNeeded()
  AccessibilityPreferences.disableAnimations = false
}
let originalIcon = selector.image(forSegment: 0)
let originalOverlay = overlay()
let restingWidth = selector.bounds.width
let restingIcon = iconOrigin()
if #available(macOS 26.0, *) {
  let glass = selector.subviews.compactMap { $0 as? NSGlassEffectView }.first
  check(glass != nil && !originalCell.isBordered && !originalCell.isBezeled,
        "static native glass replaces the bezel that stretches on hover")
  if #available(macOS 27.0, *) {
    check(glass?.effectIsInteractive == false, "glass interaction cannot inflate the capsule")
  }
  check(glass?.hitTest(NSPoint(x: selector.bounds.midX, y: selector.bounds.midY)) == nil,
        "glass passes clicks and scrolling to the native control")
  let frame = selector.frame
  let glassFrame = glass!.frame
  wheel(0, precise: true, phase: .began)
  for delta: CGFloat in [-3, -3, 4, 2] {
    wheel(delta, precise: true, phase: .changed)
    run(for: 0.03)
    check(controller.currentTab.name == "beta" && selector.frame == frame &&
          glass!.frame == glassFrame && iconOrigin() == restingIcon &&
          !selector.isRolling && !selector.isResizing,
          "uncommitted swipe \(delta) leaves capsule, icon and plugin unchanged")
  }
  wheel(0, precise: true, phase: .cancelled)
  run(for: 0.35)
  check(selector.frame == frame && glass!.frame == glassFrame && !selector.isResizing,
        "cancelled swipe leaves no delayed capsule resize")
}
check(!selector.isRolling && !selector.isResizing, "populated selector keeps selector still")
run(for: 0.5)
check(!selector.isRolling && !selector.isResizing, "opening schedules no delayed roll or resize")
check(controller.currentTab.name == "beta" && beta.sidebarTabView.superview != nil &&
      alpha.sidebarTabView.superview == nil && gamma.sidebarTabView.superview == nil,
      "opening keeps actual plugin and content unchanged")
check(selector.label(forSegment: 0) == "Beta" && selector.accessibilityLabel() == "Beta",
      "logical and accessible labels retain actual selection on opening")
check((selector.cell?.accessibilityChildren()?.first as? NSAccessibilityProtocol)?.accessibilityLabel() == "Beta",
      "native accessibility button exposes the title instead of its invisible spacer")
check(selector.cell === originalCell && abs(selector.bounds.width - restingWidth) < 0.5,
      "native cell and capsule width remain stable on opening")
check(overlay().hitTest(NSPoint(x: 10, y: 10)) == nil,
      "foreground passes clicks to native pill")
check(icon().image === originalIcon && icon().image!.isTemplate,
      "persistent puzzle retains the template image")
check(mask().masksToBounds && overlay().layer!.masksToBounds,
      "text and rounded capsule both mask their foreground")
// Exercise the cylinder renderer independently from opening the sidebar.
selector.roll(through: ["Alpha", "Gamma", "Beta"], direction: 1, duration: 0.45)
let cylinder = mask().sublayers!.first!
check(cylinder.sublayerTransform.m34 < 0 && cylinder.sublayers!.count == 3,
      "explicit multi-step roll retains cylinder perspective")
let group = cylinder.sublayers!.first!.animation(forKey: "selectionCylinder") as! CAAnimationGroup
check(abs(group.duration - 0.45) < 0.001, "explicit roll respects requested duration")
let rotation = group.animations![0] as! CAKeyframeAnimation
let middleTransform = (rotation.values![12] as! NSValue).caTransform3DValue
check(abs(middleTransform.m22) < 0.9 && middleTransform.m43 < 0,
      "outgoing text foreshortens and recedes")
let middleGroup = cylinder.sublayers![1].animation(forKey: "selectionCylinder") as! CAAnimationGroup
let middleRotation = middleGroup.animations![0] as! CAKeyframeAnimation
check(CATransform3DIsIdentity((middleRotation.values![24] as! NSValue).caTransform3DValue),
      "neighbor faces viewer between the two turns")
let radius: CGFloat = 18
let quarter = ScrollSelectionCylinder.transform(angle: .pi / 4, radius: radius)
check(abs(quarter.m42) > radius / 2 && quarter.m43 < 0 && quarter.m23 < 0,
      "forward cylinder travels upward on a curved arc")
check(ScrollSelectionCylinder.opacity(angle: .pi) == 0 && ScrollSelectionCylinder.opacity(angle: -.pi) == 0,
      "back faces stay invisible in both directions")
for (i, face) in cylinder.sublayers!.enumerated() {
  let bitmap = NSBitmapImageRep(cgImage: face.contents as! CGImage)
  let path = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("face-\(i).png")
  try! bitmap.representation(using: .png, properties: [:])!.write(to: path)
  var visiblePixels = 0
  for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide where bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.1 { visiblePixels += 1 }
  }
  check(visiblePixels > 50, "face \(i) contains rendered title")
}
finishAnimations()
check(overlay() === originalOverlay && selector.image(forSegment: 0) === originalIcon &&
      iconOrigin() == restingIcon && selector.bounds.width == restingWidth,
      "completion keeps the same foreground, puzzle origin and capsule geometry")
wheel(-1)
check(selector.isRolling && controller.currentTab.name == "gamma" && gamma.sidebarTabView.superview != nil,
      "wheel changes real plugin and content exactly once")
wheel(1)
check(selector.isRolling && controller.currentTab.name == "beta", "opposite wheel interrupts prior text")
finishAnimations()
startRoll()
controller.player.plugins = [alpha, gamma]
controller.updatePluginTabs()
check(!selector.isRolling && controller.currentTab.name == "alpha", "removal cancels stale text and chooses remaining plugin")
finishAnimations()
startRoll()
window.setContentSize(NSSize(width: 320, height: 320))
root.layoutSubtreeIfNeeded()
check(selector.isRolling, "available width changes do not cancel text rotation")
finishAnimations()
check(selector.bounds.maxX <= selector.superview!.bounds.maxX + 0.5,
      "selector fits the available header width")
startRoll()
selector.removeFromSuperview()
check(!selector.isRolling && !selector.isResizing, "detaching cancels title, delayed work and width timer")
controller.updateTabButtonLayout()
root.layoutSubtreeIfNeeded()
AccessibilityPreferences.motionReductionEnabled = true
controller.switchToTab(controller.allTabs.last!)
wheel(-1)
check(!selector.isRolling && !selector.isResizing && controller.currentTab.name == "alpha",
      "Reduce Motion keeps navigation immediate without text or width motion")
AccessibilityPreferences.motionReductionEnabled = false
AccessibilityPreferences.disableAnimations = true
wheel(-1)
check(!selector.isRolling && !selector.isResizing && controller.currentTab.name == "gamma",
      "Disable animations suppresses both transitions")
AccessibilityPreferences.disableAnimations = false
startRoll()
selector.isEnabled = false
check(!selector.isRolling && !selector.isResizing, "disabling clears in-flight work")
selector.isEnabled = true
startRoll(); selector.finishRoll()
check(!selector.isRolling && selector.label(forSegment: 0) == "Gamma", "popup preparation preserves latest title")
controller.player.plugins = [alpha, gamma]
controller.updatePluginTabs(); controller.switchToTab(controller.allTabs.last!)
check(!selector.isRolling && controller.currentTab.name == "gamma",
      "selection with two plugins keeps the saved selection still")
selector.finishRoll()
controller.player.plugins = [gamma]
controller.updatePluginTabs()
check(!selector.isRolling, "selection with one plugin stays still")
controller.player.plugins = []
controller.updatePluginTabs()
check(!selector.isRolling, "selection with an empty plugin list stays still")
controller.player.plugins = [alpha, beta, gamma]
controller.updatePluginTabs(); controller.switchToTab(.pluginPlaceholder)
check(controller.currentTab.name == "alpha", "unspecified selection resolves to first actual plugin")
for expected in ["alpha", "gamma", "beta"] {
  controller.switchToTab(controller.allTabs.first { $0.name == expected }!)
    check(!selector.isRolling && controller.currentTab.name == expected, "selection preserves \(expected) without rotation")
  finishAnimations()
}
controller.selectPlugin(withIdentifier: "beta")
let freshController = PluginViewController()
freshController.player.plugins = [PluginInstance("alpha", "Alpha"), PluginInstance("beta", "Beta")]
freshController.beginWindowSession()
_ = freshController.view
check(freshController.currentTab.name == "beta" && controller.currentTab.name == "beta",
      "new player restores the last explicit selection without changing another player")
check(PluginScrollNavigation.destination(ids: ["alpha"], currentID: "alpha", direction: 1) == nil &&
      PluginScrollNavigation.destination(ids: ["alpha", "beta"], currentID: "alpha", direction: 0) == nil,
      "single plugin and zero direction are navigation no-ops")

window.setContentSize(NSSize(width: 480, height: 320))
root.layoutSubtreeIfNeeded()
settle("IInfo")
let narrowWidth = selector.bounds.width
let fixedIcon = iconOrigin()
selector.setLabel("A much longer plugin title", forSegment: 0)
selector.roll(through: ["IInfo", "A much longer plugin title"], direction: 1)
let uncutWidth = mask().sublayers!.first!.sublayers!.last!.bounds.width
check(abs(selector.bounds.width - narrowWidth) < 0.5 && selector.isResizing,
      "new title keeps the old capsule width until the delayed resize")
check(uncutWidth > mask().bounds.width,
      "long title exists at full width behind the current clipping mask")
run(for: 0.075)
check(abs(selector.bounds.width - narrowWidth) < 0.5 && iconOrigin() == fixedIcon,
      "first 75 ms retain old capsule and puzzle origin")
run(for: 0.13)
let intermediateWidth = selector.bounds.width
check(intermediateWidth > narrowWidth + 1 && intermediateWidth < selector.maximumWidth,
      "capsule passes through an intermediate width after the delay")
check(iconOrigin() == fixedIcon && selector.isRolling,
      "puzzle stays fixed while width and text animate independently")
finishAnimations()
let expandedWidth = selector.bounds.width
check(expandedWidth > intermediateWidth && mask().bounds.width >= uncutWidth - 1,
      "expanded capsule reveals the complete long title")
check(overlay() === originalOverlay && iconOrigin() == fixedIcon,
      "settling never swaps foreground or recenters the puzzle")
selector.setLabel("IInfo", forSegment: 0)
check(selector.bounds.width == expandedWidth, "short title initially keeps the expanded capsule")
run(for: 0.2)
let shrinkingWidth = selector.bounds.width
check(shrinkingWidth < expandedWidth && shrinkingWidth > narrowWidth,
      "short title smoothly shrinks the capsule")
selector.setLabel("Navigator", forSegment: 0)
check(abs(selector.bounds.width - shrinkingWidth) < 0.5,
      "interrupting resize starts from its actual current width")
run(for: 0.04)
selector.setLabel("OpenSubs", forSegment: 0)
run(for: 0.04)
selector.setLabel("IInfo", forSegment: 0)
finishAnimations()
check(abs(selector.bounds.width - narrowWidth) < 0.5 && selector.label(forSegment: 0) == "IInfo",
      "rapid changes settle on the latest title with no queued old sizes")
selector.setLabel("OpenSubs", forSegment: 0)
run(for: 0.06)
selector.setLabel("OpenSubs", forSegment: 0)
run(for: 0.09)
check(selector.bounds.width > narrowWidth,
      "repeated identical updates do not restart the resize delay")
finishAnimations()

for leading in [true, false] {
  controller.isLeading = leading
  controller.updateTabButtonLayout()
  root.layoutSubtreeIfNeeded()
  settle("IInfo")
  func outerEdge() -> CGFloat {
    let frame = selector.convert(selector.bounds, to: controller.view)
    return leading ? frame.minX : frame.maxX
  }
  let edge: CGFloat = leading ? 20 : controller.view.bounds.width - 20
  check(abs(outerEdge() - edge) < 0.5, "\(leading ? "left" : "right") capsule sits at the outer header edge")
  selector.setLabel("Thumbnail Navigator", forSegment: 0)
  run(for: 0.2)
  check(abs(outerEdge() - edge) < 0.5, "\(leading ? "left" : "right") capsule pins its outer edge during growth")
  finishAnimations()
  check(abs(outerEdge() - edge) < 0.5, "\(leading ? "left" : "right") capsule pins its outer edge after growth")
}
controller.isLeading = true
controller.updateTabButtonLayout()
window.setContentSize(NSSize(width: 300, height: 320))
root.layoutSubtreeIfNeeded()
selector.setLabel("An exceptionally long plugin name that cannot fit in the sidebar", forSegment: 0)
finishAnimations()
check(abs(selector.bounds.width - selector.maximumWidth) < 0.5 &&
      mask().sublayers!.first!.bounds.width > mask().bounds.width,
      "oversized title stops at available width and stays clipped")
check(selector.toolTip(forSegment: 0) == selector.label(forSegment: 0) &&
      selector.accessibilityLabel() == selector.label(forSegment: 0),
      "tooltip and accessibility retain the complete clipped title")
for size in [NSControl.ControlSize.large, .extraLarge] {
  selector.controlSize = size
  settle("IInfo")
  let origin = iconOrigin()
  selector.setLabel("OpenSubs", forSegment: 0)
  finishAnimations()
  check(iconOrigin() == origin && selector.cell === originalCell,
        "\(size): native bezel and puzzle survive title resizing")
}
let selectedBeforeScaleChange = controller.currentTab
for scale: CGFloat in [1, 2] {
  window.testScale = scale
  selector.viewDidChangeBackingProperties()
  check(mask().sublayers?.first?.contentsScale == scale, "title bitmap follows backing scale \(scale)")
  check(controller.currentTab.name == selectedBeforeScaleChange.name && !selector.isRolling,
        "backing scale change preserves logical plugin selection")
}
window.orderOut(nil)

func newWindowController() -> PluginViewController {
  let result = PluginViewController()
  result.player.plugins = [PluginInstance("alpha", "Alpha"), PluginInstance("beta", "Beta"),
                           PluginInstance("gamma", "Gamma")]
  result.beginWindowSession()
  return result
}
Preference.set("beta", for: .lastSelectedPlugin)
let firstWindow = newWindowController()
let unloadedWindow = newWindowController()
check(!firstWindow.isViewLoaded && !unloadedWindow.isViewLoaded,
      "opening snapshots the selection without loading plugin views")
_ = firstWindow.view
check(firstWindow.currentTab.name == "beta" &&
      firstWindow.tabButtonsSegmentControl.label(forSegment: 0) == "Beta",
      "new window restores the saved plugin and label")
firstWindow.selectPlugin(withIdentifier: "gamma")
_ = unloadedWindow.view
check(unloadedWindow.currentTab.name == "beta",
      "already open unloaded sidebar retains its opening selection")
let thirdWindow = newWindowController()
_ = thirdWindow.view
check(thirdWindow.currentTab.name == "gamma" && firstWindow.currentTab.name == "gamma" &&
      unloadedWindow.currentTab.name == "beta",
      "later window uses the latest selection while existing windows stay independent")

let selectedFromMenu = NSMenuItem(title: "Alpha", action: NSSelectorFromString("menuItemAction:"), keyEquivalent: "")
selectedFromMenu.representedObject = "alpha"
check(app.sendAction(selectedFromMenu.action!, to: unloadedWindow, from: selectedFromMenu),
      "native plugin menu dispatches its production action")
check(unloadedWindow.currentTab.name == "alpha" && Preference.string(for: .lastSelectedPlugin) == "alpha" &&
      firstWindow.currentTab.name == "gamma" && thirdWindow.currentTab.name == "gamma",
      "menu selection persists without changing other windows")
firstWindow.beginWindowSession()
check(firstWindow.currentTab.name == "gamma",
      "showing an already open window keeps its independent selection")
firstWindow.player.plugins = [firstWindow.player.plugins[2], firstWindow.player.plugins[0], firstWindow.player.plugins[1]]
firstWindow.updatePluginTabs()
check(firstWindow.currentTab.name == "gamma" && firstWindow.currentTab.tag == 1 &&
      Preference.string(for: .lastSelectedPlugin) == "alpha",
      "reordering preserves current identity without overwriting another window's preference")
firstWindow.player.plugins.removeFirst()
firstWindow.updatePluginTabs()
check(firstWindow.currentTab.name == "alpha" && Preference.string(for: .lastSelectedPlugin) == "alpha",
      "removed active plugin falls back to the first remaining entry rather than the opening preference")
firstWindow.switchToTab(firstWindow.allTabs.first { $0.name == "beta" }!)
check(Preference.string(for: .lastSelectedPlugin) == "alpha",
      "programmatic sidebar requests do not overwrite the last explicit choice")
firstWindow.selectPlugin(withIdentifier: "unknown")
check(firstWindow.currentTab.name == "beta" && Preference.string(for: .lastSelectedPlugin) == "alpha",
      "invalid explicit requests preserve selection and preference")

thirdWindow.selectPlugin(withIdentifier: "gamma")
firstWindow.endWindowSession()
firstWindow.player.plugins = thirdWindow.player.plugins.map { PluginInstance($0.plugin.identifier, $0.plugin.sidebarTabName) }
firstWindow.beginWindowSession()
check(firstWindow.currentTab.name == "gamma" &&
      firstWindow.tabButtonsSegmentControl.label(forSegment: 0) == "Gamma" &&
      firstWindow.player.plugins[2].sidebarTabView.superview != nil,
      "reused player starts a new session with the latest saved plugin and content")
unloadedWindow.selectPlugin(withIdentifier: "alpha")
firstWindow.beginWindowSession()
check(firstWindow.currentTab.name == "gamma" && Preference.string(for: .lastSelectedPlugin) == "alpha",
      "subsequent show calls never resnapshot an active window")
let reusedUnloaded = newWindowController()
reusedUnloaded.endWindowSession()
thirdWindow.selectPlugin(withIdentifier: "beta")
reusedUnloaded.beginWindowSession()
_ = reusedUnloaded.view
check(reusedUnloaded.currentTab.name == "beta",
      "reused player also refreshes its selection before the first sidebar load")

Preference.set("missing", for: .lastSelectedPlugin)
let unavailable = newWindowController()
unavailable.player.plugins.append(PluginInstance("missing", nil))
_ = unavailable.view
check(unavailable.currentTab.name == "alpha" && Preference.string(for: .lastSelectedPlugin) == "missing",
      "unavailable or panel-less saved plugin falls back without erasing the preference")
unavailable.removePluginTab(withIdentifier: "alpha")
check(unavailable.currentTab.name == "beta" && Preference.string(for: .lastSelectedPlugin) == "missing",
      "automatic removal fallback never becomes the shared preference")
unavailable.player.plugins = []
unavailable.updatePluginTabs()
check(unavailable.currentTab.tag == 0 && Preference.string(for: .lastSelectedPlugin) == "missing",
      "empty plugin list shows the placeholder and retains the saved identifier")
unavailable.player.plugins = [PluginInstance("alpha", "Alpha"), PluginInstance("missing", "Returned plugin")]
unavailable.updatePluginTabs()
check(unavailable.currentTab.name == "alpha" && Preference.string(for: .lastSelectedPlugin) == "missing",
      "plugin re-enabling keeps an open window's current fallback")
let returnedPluginWindow = newWindowController()
returnedPluginWindow.player.plugins = unavailable.player.plugins.map { PluginInstance($0.plugin.identifier, $0.plugin.sidebarTabName) }
returnedPluginWindow.endWindowSession()
returnedPluginWindow.beginWindowSession()
_ = returnedPluginWindow.view
check(returnedPluginWindow.currentTab.name == "missing",
      "new session can restore the saved plugin after it becomes available again")
let createdBeforeSelection = PluginViewController()
createdBeforeSelection.player.plugins = [PluginInstance("alpha", "Alpha"), PluginInstance("beta", "Beta")]
thirdWindow.selectPlugin(withIdentifier: "beta")
createdBeforeSelection.beginWindowSession()
_ = createdBeforeSelection.view
check(createdBeforeSelection.currentTab.name == "beta",
      "precreated idle player reads the preference at window opening")
print("Completed \(checks) plugin selector checks using production controller/control and fixture plugin views.")
