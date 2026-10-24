import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
  precondition(condition(), label)
  checks += 1
  print("PASS: \(label)")
}
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.000001 }
func scale(_ width: CGFloat, _ height: CGFloat) -> CGFloat {
  FloatingOSCScale.factor(for: NSSize(width: width, height: height))
}

check(near(scale(450, 250), 0.8), "compact window reaches 80 percent")
check(near(scale(900, 500), 1), "comfortable window reaches original size")
check(near(scale(675, 375), 0.9), "middle size scales smoothly")
check(near(scale(300, 180), 0.8), "very small window keeps minimum scale")
check(near(scale(3000, 1800), 1), "large/fullscreen window never enlarges beyond original")
check(near(scale(1200, 250), 0.8), "short wide window compacts by height")
check(near(scale(450, 900), 0.8), "narrow tall window compacts by width")
check(near(scale(900, 375), 0.9), "height independently limits scale")
check(near(scale(675, 900), 0.9), "width independently limits scale")
check(near(scale(0, 0), 0.8), "unmeasured size has bounded fallback")
check(near(scale(-1, 500), 0.8), "negative size has bounded fallback")
check(near(scale(.infinity, 500), 0.8), "nonfinite size has bounded fallback")
check(near(scale(900, .nan), 0.8), "NaN size has bounded fallback")

var previous: CGFloat = 0.8
for step in 0...1000 {
  let current = scale(CGFloat(step * 2), CGFloat(step))
  precondition(current >= 0.8 && current <= 1, "bounded across window sizes")
  precondition(current >= previous, "monotonic while resizing")
  previous = current
}
check(true, "1001 window sizes remain bounded and monotonic")
check(near(scale(449.999, 800), scale(450.001, 800)), "continuous at lower width threshold")
check(near(scale(899.999, 800), scale(900.001, 800)), "continuous at upper width threshold")
check(near(scale(1000, 249.999), scale(1000, 250.001)), "continuous at lower height threshold")
check(near(scale(1000, 499.999), scale(1000, 500.001)), "continuous at upper height threshold")
print("\(checks) floating OSC scale checks passed")

// Continuous contact, including a controller already near either edge and a
// sidebar too wide to leave enough space. Window-edge margins stay independent.
for windowWidth: CGFloat in [400, 500, 900, 1200] {
  let panelWidth: CGFloat = windowWidth == 400 ? 368 : 460
  let half = panelWidth / 2
  let physical = (half + 16)...(windowWidth - half - 16)
  for fraction: CGFloat in [0.1, 0.5, 0.9] {
    let preferred = (windowWidth * fraction).clamped(to: physical)
    for left in [false, true] {
      for step in 0...Int(windowWidth * 1.6) {
        let extent = CGFloat(step) / 2
        let actual = FloatingOSCPlacement.center(preferred: preferred, width: panelWidth,
          windowWidth: windowWidth, leftSidebar: left ? extent : 0,
          rightSidebar: left ? 0 : extent, margin: 16)
        let pushed = left ? max(preferred, extent + 6 + half) :
          min(preferred, windowWidth - extent - 6 - half)
        let expected = extent == 0 ? preferred : pushed.clamped(to: physical)
        precondition(near(actual, expected), "contact follows boundary continuously, saturating at physical edge")
      }
      check(true, "six-point contact remains continuous to window edge (width=\(windowWidth), fraction=\(fraction), left=\(left))")
    }
    for fixed: CGFloat in [20, windowWidth * 0.3, windowWidth * 0.45] {
      var previousCenter = FloatingOSCPlacement.center(preferred: preferred, width: panelWidth,
        windowWidth: windowWidth, leftSidebar: 0, rightSidebar: fixed, margin: 16)
      for step in 1...Int(windowWidth * 0.9) {
        let extent = CGFloat(step) / 2
        let actual = FloatingOSCPlacement.center(preferred: preferred, width: panelWidth,
          windowWidth: windowWidth, leftSidebar: extent, rightSidebar: fixed, margin: 16)
        precondition(abs(actual - previousCenter) <= 0.500001,
                     "second sidebar cannot cause a gap-sized jump as free space closes")
        previousCenter = actual
      }
      check(true, "two-panel clearance yields continuously when space runs out (width=\(windowWidth), fraction=\(fraction), right=\(fixed))")
    }
  }
}

// Unavoidable overlap shares pressure between both higher sidebars, even when
// the user's requested position is off-center or panel widths differ.
for (windowWidth, panelWidth, left, right) in [
  (CGFloat(900), CGFloat(460), CGFloat(300), CGFloat(300)),
  (900, 460, 240, 340), (803, 368, 300, 260), (500, 368, 200, 200)
] {
  for preferred in [panelWidth / 2 + 16, windowWidth / 2, windowWidth - panelWidth / 2 - 16] {
    let center = FloatingOSCPlacement.center(preferred: preferred, width: panelWidth,
      windowWidth: windowWidth, leftSidebar: left, rightSidebar: right, margin: 16)
    let leftCovered = left - (center - panelWidth / 2)
    let rightCovered = center + panelWidth / 2 - (windowWidth - right)
    check(near(leftCovered, rightCovered), "both sidebars cover equal OSC widths regardless of preferred position")
    let mirrored = FloatingOSCPlacement.center(preferred: windowWidth - preferred, width: panelWidth,
      windowWidth: windowWidth, leftSidebar: right, rightSidebar: left, margin: 16)
    check(near(center + mirrored, windowWidth), "swapping sidebar sides mirrors balanced pressure")
  }
}
check(near(FloatingOSCPlacement.center(preferred: 400, width: 460, windowWidth: 1200,
  leftSidebar: 100, rightSidebar: 200), 400), "two sidebars preserve off-center placement while there is room")
check(near(FloatingOSCPlacement.center(preferred: 300, width: 460, windowWidth: 1200,
  leftSidebar: 200, rightSidebar: 200), 436), "fitting OSC receives only the necessary sidebar displacement")
check(near(FloatingOSCPlacement.center(preferred: 450, width: 460, windowWidth: 900,
  leftSidebar: 850, rightSidebar: 20, margin: 16), 654), "physical window bounds take priority when equal overlap cannot fit")

// Position fractions must describe the same balance on laptop, 16:9, 21:9,
// portrait, and small window geometry, with both adaptive panel sizes.
for window in [NSSize(width: 1512, height: 982), NSSize(width: 1920, height: 1080),
               NSSize(width: 2560, height: 1080), NSSize(width: 1080, height: 1920),
               NSSize(width: 400, height: 225)] {
  for panel in [NSSize(width: 460, height: 80), NSSize(width: 368, height: 64)] {
    for h: CGFloat in [0, 0.01, 0.25, 0.5, 0.75, 0.99, 1] {
      for v: CGFloat in [0, 0.01, 0.25, 0.5, 0.75, 0.99, 1] {
        let rect = FloatingOSCPlacement.defaultFrame(horizontal: h, vertical: v, size: panel,
          contentSize: window, titlebarBottom: window.height - 25)
        let left = rect.minX - 16
        let right = window.width - rect.maxX - 16
        let top = window.height - 25 - rect.maxY
        let bottom = rect.minY
        if window.width >= panel.width + 32 {
          check(near(left * (1 - h), right * h), "horizontal percentage balances safe opposing gaps")
        }
        check(near(top * (1 - v), bottom * v), "vertical percentage balances safe opposing gaps")
        let position = FloatingOSCPlacement.defaultPosition(frame: rect, contentSize: window,
          titlebarBottom: window.height - 25, fallback: NSPoint(x: h, y: v))
        check(near(position.x, h) && near(position.y, v), "placement and dragging round-trip all fractions")
      }
    }
  }
}
let collapsed = FloatingOSCPlacement.defaultFrame(horizontal: 0.25, vertical: 0.75,
  size: NSSize(width: 400, height: 200), contentSize: NSSize(width: 400, height: 200),
  titlebarBottom: 200)
let preserved = FloatingOSCPlacement.defaultPosition(frame: collapsed,
  contentSize: NSSize(width: 400, height: 200), titlebarBottom: 200,
  fallback: NSPoint(x: 0.25, y: 0.75))
check(preserved == NSPoint(x: 0.25, y: 0.75), "collapsed travel preserves requested percentages")
print("Completed \(checks) scale and position model checks")

for size in [NSSize(width: 400, height: 225), NSSize(width: 1512, height: 982), NSSize(width: 2560, height: 1080)] {
  let rect = FloatingOSCPlacement.frame(position: .initial, size: NSSize(width: 368, height: 64), contentSize: size, titlebarBottom: size.height - 25)
  check(near(rect.minY, 16) && near(rect.midX, size.width / 2), "factory bottom gap remains sixteen points regardless of window size")
}

// Explicit units preserve intent through serialization, preview scaling and clipping.
for window in [NSSize(width: 400, height: 225), NSSize(width: 1512, height: 982), NSSize(width: 2560, height: 1080)] {
  for xu in [FloatingOSCPosition.Unit.percent, .point] {
    for yu in [FloatingOSCPosition.Unit.percent, .point] {
      for xe in [FloatingOSCPosition.Edge.near, .far] {
        for ye in [FloatingOSCPosition.Edge.near, .far] {
          let model = FloatingOSCPosition(horizontal: .init(value: xu == .percent ? 0.25 : 24, unit: xu, edge: xe),
            vertical: .init(value: yu == .percent ? 0.75 : 16, unit: yu, edge: ye))
          check(FloatingOSCPosition(dictionary: model.dictionary) == model, "all per-axis units and anchors round-trip their versioned dictionary")
          let panel = NSSize(width: 200, height: 64)
          let rect = FloatingOSCPlacement.frame(position: model, size: panel, contentSize: window, titlebarBottom: window.height - 25)
          if xu == .point { check(near(xe == .near ? rect.minX : window.width - rect.maxX, 24), "point horizontal offset is independent of window dimensions") }
          if yu == .point { check(near(ye == .near ? window.height - 25 - rect.maxY : rect.minY, 16), "point vertical offset is independent of window dimensions") }
          let restored = FloatingOSCPlacement.capturing(frame: rect, keeping: model, contentSize: window, titlebarBottom: window.height - 25)
          check(near(restored.horizontal.value, model.horizontal.value) && near(restored.vertical.value, model.vertical.value), "mixed-unit geometry and drag capture are inverse")
          let scaled = FloatingOSCPlacement.frame(position: model, size: NSSize(width: panel.width / 2, height: panel.height / 2),
            contentSize: NSSize(width: window.width / 2, height: window.height / 2), titlebarBottom: (window.height - 25) / 2, pointScale: 0.5)
          check(near(scaled.minX * 2, rect.minX) && near(scaled.minY * 2, rect.minY), "preview scaling preserves point and percentage semantics")
        }
      }
    }
  }
}
let oversizedIntent = FloatingOSCPosition(horizontal: .init(value: 700, unit: .point, edge: .far), vertical: .init(value: 500, unit: .point))
let clipped = FloatingOSCPlacement.frame(position: oversizedIntent, size: NSSize(width: 368, height: 64), contentSize: NSSize(width: 400, height: 225), titlebarBottom: 200)
check(near(clipped.minX, 16) && near(clipped.minY, 0), "oversized point offsets clamp displayed geometry")
let expanded = FloatingOSCPlacement.frame(position: oversizedIntent, size: NSSize(width: 460, height: 80), contentSize: NSSize(width: 1920, height: 1080), titlebarBottom: 1055)
check(near(1920 - expanded.maxX, 700) && near(1055 - expanded.maxY, 500), "expanding restores original point intent after clipping")
for bad in [Double.nan, -1, Double.infinity, 100001] {
  var dictionary = FloatingOSCPosition.initial.dictionary
  dictionary["vertical"] = ["value": bad, "unit": 1, "edge": 1]
  check(FloatingOSCPosition(dictionary: dictionary) == nil, "invalid stored point values are rejected")
}
print("Completed \(checks) scale and dual-unit model checks")

let quarterFromFar = FloatingOSCPosition(horizontal: .init(value: 0.25, edge: .far), vertical: .init(value: 0.25, edge: .far))
let quarterFrame = FloatingOSCPlacement.frame(position: quarterFromFar, size: NSSize(width: 200, height: 80), contentSize: NSSize(width: 1000, height: 600), titlebarBottom: 560)
check(near(quarterFrame.minX, 16 + (1000 - 200 - 32) * 0.75) && near(quarterFrame.minY, (560 - 80) * 0.25), "quarter from right and bottom measures travel from the selected edge")
for edge in [FloatingOSCPosition.Edge.near, .far] {
  for value: CGFloat in [0, 0.25, 0.5, 1] {
    let original = FloatingOSCPosition(horizontal: .init(value: value, edge: edge), vertical: .init(value: value, edge: edge))
    let inverse = FloatingOSCPosition(horizontal: .init(value: 1 - value, edge: edge == .near ? .far : .near), vertical: .init(value: 1 - value, edge: edge == .near ? .far : .near))
    let a = FloatingOSCPlacement.frame(position: original, size: NSSize(width: 200, height: 80), contentSize: NSSize(width: 1000, height: 600), titlebarBottom: 560)
    let b = FloatingOSCPlacement.frame(position: inverse, size: a.size, contentSize: NSSize(width: 1000, height: 600), titlebarBottom: 560)
    check(a == b, "complementing percent with opposite edge preserves physical placement")
  }
}
var oldPercent = quarterFromFar.dictionary
oldPercent["version"] = 1
let migratedPercent = FloatingOSCPosition(dictionary: oldPercent)!
check(migratedPercent.horizontal.edge == .near && migratedPercent.vertical.edge == .near && migratedPercent.horizontal.value == 0.25 && migratedPercent.vertical.value == 0.25, "old dictionaries retain historical percent direction instead of suddenly mirroring")
var oldPoints = FloatingOSCPosition.initial.dictionary
oldPoints["version"] = 1
check(FloatingOSCPosition(dictionary: oldPoints) == .initial, "old mixed dictionaries preserve bottom point anchor")
print("Completed \(checks) scale, edge and migration model checks")
