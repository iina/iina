let application = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                      styleMask: [.titled], backing: .buffered, defer: false)
let titles = ["Layout", "Video", "Audio", "Subtitles"]
let control = SidebarTabSelectorControl(titles: titles)
control.segmentCount = titles.count
if #available(macOS 26.0, *) { control.controlSize = .extraLarge }
for index in titles.indices {
  control.setTag(10 + index, forSegment: index)
  control.setImage(NSImage(systemSymbolName: "circle", accessibilityDescription: nil), forSegment: index)
}
window.contentView!.addSubview(control)
control.frame = NSRect(origin: NSPoint(x: 20, y: 20), size: control.intrinsicContentSize)
let overlay = control.subviews.last!
let highlight = overlay.subviews.first!
let icons = overlay.subviews.compactMap { $0 as? NSImageView }
let labels = overlay.subviews.compactMap { $0 as? NSTextField }
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fatalError(message) }
}
class Receiver: NSObject {
  var calls = 0
  var selectedTag = -1
  @objc func select(_ sender: NSSegmentedControl) {
    calls += 1
    selectedTag = sender.tag(forSegment: sender.selectedSegment)
    (sender as! SidebarTabSelectorControl).updateSelection(animated: false)
  }
}
let receiver = Receiver()
control.target = receiver
control.action = #selector(Receiver.select(_:))
let originalSize = control.intrinsicContentSize
var widths: [CGFloat] = []
for selected in titles.indices {
  control.selectedSegment = selected
  control.updateSelection(animated: false)
  check(control.intrinsicContentSize == originalSize, "Outer size changed with selection")
  check(labels[selected].alphaValue == 1, "Selected label missing")
  check(labels.enumerated().allSatisfy { $0.offset == selected || $0.element.alphaValue == 0 }, "Inactive labels visible")
  check(icons.allSatisfy { overlay.bounds.contains($0.frame) }, "Icon outside capsule")
  check(highlight.frame.contains(icons[selected].frame), "Highlight missed selected icon")
  check(labels[selected].frame.width >= labels[selected].cell!.cellSize.width,
        "Selected title clipped at normal width")
  widths.append(highlight.frame.width)
  for next in titles.indices {
    let point = icons[next].convert(NSPoint(x: 9, y: 9), to: nil)
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    control.mouseDown(with: event)
    check(receiver.selectedTag == 10 + next, "Native action selected wrong tab")
  }
}
check(widths[1] < widths[3], "Highlight does not fit individual titles")
check(receiver.calls == 16, "Click action lost or duplicated")
control.isEnabled = false
let calls = receiver.calls
let point = icons[0].convert(NSPoint(x: 9, y: 9), to: nil)
let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
  windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
control.mouseDown(with: event)
check(receiver.calls == calls, "Disabled control accepted click")
control.isEnabled = true
let header = HeaderFixture(control, titles: titles)
AccessibilityPreferences.motionReductionEnabled = true
for leading in [true, false, true] {
  header.isLeading = leading
  for selected in titles.indices {
    header.currentTab = header.allTabs[selected]
    header.updateTabActiveStatus()
    control.frame.size = control.intrinsicContentSize
    control.updateSelection(animated: false)
    check(labels[selected].alphaValue == 1 && labels[selected].frame.width > 0,
          "Selected title missing on \(leading ? "left" : "right") sidebar")
    check(control.label(forSegment: selected) == "sidebar.\(titles[selected])",
          "Native selected segment label missing")
  }
}
AccessibilityPreferences.motionReductionEnabled = false
control.frame.size = NSSize(width: 150, height: originalSize.height)
for selected in titles.indices {
  control.selectedSegment = selected
  control.updateSelection(animated: false)
  check(highlight.frame.minX >= 0 && highlight.frame.maxX <= overlay.bounds.maxX, "Narrow capsule highlight overflow")
  check(icons.allSatisfy { overlay.bounds.contains($0.frame) }, "Narrow capsule icon overflow")
}
control.controlSize = .large
control.frame.size = control.intrinsicContentSize
control.updateSelection(animated: false)
check(control.intrinsicContentSize.height == 30, "Compact height incorrect")
check(icons.allSatisfy { overlay.bounds.contains($0.frame) }, "Compact icon overflow")
print("Sidebar selector: \(checks) checks passed")
