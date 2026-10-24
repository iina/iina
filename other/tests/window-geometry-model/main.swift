import Foundation
// Compile the production parser/model with only AppData's minimum-size constant
// isolated. These checks exercise draft serialization and illustrative geometry,
// not IINA window behavior, AppKit layout, or preference persistence.
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
  precondition(condition(), label)
  checks += 1
  print("PASS: \(label)")
}
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
let screen = NSSize(width: 1000, height: 800)
for raw in ["", "640", "x480%", "+20-30", "640+20-30", "640x480+20%-30%", "000640x000480+0020-0030", "0x480", "0", "garbage", "50.5%+2-3", "99999999999999999999999999+0+0"] {
  let draft = InitialWindowGeometry(raw)
  check(draft.geometryString == raw, "no-op preserves \(raw.debugDescription)")
}
for (raw, sizeEnabled, positionEnabled) in [("", false, false), ("640", true, false), ("+20-30", false, true), ("640+20-30", true, true)] {
  let draft = InitialWindowGeometry(raw)
  check(draft.sizeEnabled == sizeEnabled && draft.positionEnabled == positionEnabled, "independent enabled groups for \(raw.debugDescription)")
}
var both = InitialWindowGeometry("640x480+20-30")
check(both.independentSize && both.widthValue == 640 && both.heightValue == 480,
      "both explicit dimensions load independently of the live aspect lock")
both.xValue = 40
check(both.geometryString == "640x480+40-30", "position edit preserves both loaded size dimensions")
both.sizeValue = 800
check(both.geometryString == "800x480+40-30", "editing one explicit size retains the other dimension")
var toggles = InitialWindowGeometry("640x480+20-30")
toggles.sizeEnabled = false
check(toggles.geometryString == "+20-30", "size off preserves position")
toggles.positionEnabled = false
check(toggles.geometryString == "", "both off omit both groups")
toggles.sizeEnabled = true
toggles.positionEnabled = true
check(toggles.geometryString == "640x480+20-30", "off/on restores full local draft")
let emptyFrame = InitialWindowGeometry("").previewFrame(screenSize: screen)
check(near(emptyFrame.width, 500) && near(emptyFrame.midX, 500) && near(emptyFrame.midY, 400), "disabled groups preview illustrative centered half-screen width")
let sizeOnly = InitialWindowGeometry("400").previewFrame(screenSize: screen)
check(near(sizeOnly.width, 400) && near(sizeOnly.height, 225) && near(sizeOnly.midX, 500), "width preserves illustrative aspect and absent position centers")
let heightOnly = InitialWindowGeometry("x50%").previewFrame(screenSize: screen)
check(near(heightOnly.height, 400) && near(heightOnly.width, 400 * 16 / 9), "height percentage uses visible screen height")
let bothFrame = InitialWindowGeometry("400x100").previewFrame(screenSize: screen)
check(near(bothFrame.width, 400) && near(bothFrame.height, 120), "both-dimension preview respects the explicit height and native minimum")
let zeroWidth = InitialWindowGeometry("0x400").previewFrame(screenSize: screen)
check(near(zeroWidth.height, 400), "exact zero width permits height fallback")
let paddedZero = InitialWindowGeometry("000x400").previewFrame(screenSize: screen)
check(near(paddedZero.width, 285), "padded zero follows runtime literal-zero distinction")
for xAnchor in [InitialWindowGeometry.HorizontalAnchor.left, .right] {
  for yAnchor in [InitialWindowGeometry.VerticalAnchor.top, .bottom] {
    for unit in [InitialWindowGeometry.Unit.points, .percent] {
      var draft = InitialWindowGeometry("400+20-30")
      draft.xAnchor = xAnchor
      draft.yAnchor = yAnchor
      draft.xUnit = unit
      draft.yUnit = unit
      draft.xValue = unit == .points ? 30 : 25
      draft.yValue = unit == .points ? 40 : 25
      let frame = draft.previewFrame(screenSize: screen)
      let expectedX: CGFloat = unit == .points ? (xAnchor == .left ? 30 : 570) : (xAnchor == .left ? 50 : 550)
      let expectedY: CGFloat = unit == .points ? (yAnchor == .bottom ? 40 : 535) : (yAnchor == .bottom ? 87.5 : 487.5)
      check(near(frame.minX, expectedX) && near(frame.minY, expectedY), "\(unit) preview obeys \(xAnchor)/\(yAnchor) physical anchors")
      let sizeBefore = (draft.sizeDimension, draft.sizeValue, draft.sizeUnit)
      draft.movePreview(to: NSPoint(x: 120, y: 100), screenSize: screen, windowSize: frame.size)
      let expectedMovedX = unit == .points ? (xAnchor == .left ? 120 : 480) : (xAnchor == .left ? 32 : 68)
      let expectedMovedY = unit == .points ? (yAnchor == .bottom ? 100 : 475) : (yAnchor == .bottom ? 27 : 73)
      check(draft.xValue == expectedMovedX && draft.yValue == expectedMovedY && draft.xUnit == unit && draft.yUnit == unit,
            "move rounds supported values and preserves \(unit)/\(xAnchor)/\(yAnchor)")
      check(draft.sizeDimension == sizeBefore.0 && draft.sizeValue == sizeBefore.1 && draft.sizeUnit == sizeBefore.2, "move leaves size group unchanged")
    }
  }
}
var noMove = InitialWindowGeometry("640")
// Boundary contact must survive integer serialization, including percentage
// centers that do not land on an integer percentage of the available desktop.
let contactScreen = NSSize(width: 1000, height: 920)
for width in [870, 885, 900] {
  for unit in [InitialWindowGeometry.Unit.points, .percent] {
    for xAnchor in [InitialWindowGeometry.HorizontalAnchor.left, .right] {
      for yAnchor in [InitialWindowGeometry.VerticalAnchor.top, .bottom] {
        var draft = InitialWindowGeometry("\(width)+50%-50%")
        draft.xAnchor = xAnchor
        draft.yAnchor = yAnchor
        draft.xUnit = unit
        draft.yUnit = unit
        let size = draft.previewFrame(screenSize: contactScreen).size
        for x in [CGFloat(0), contactScreen.width - size.width] {
          for y in [CGFloat(0), contactScreen.height - size.height] {
            draft.movePreview(to: NSPoint(x: x, y: y), screenSize: contactScreen, windowSize: size)
            let restored = InitialWindowGeometry(draft.geometryString).previewFrame(screenSize: contactScreen)
            check(near(restored.minX, x) && near(restored.minY, y),
                  "edge contact survives \(unit) serialization at \(xAnchor)/\(yAnchor), width \(width)")
          }
        }
      }
    }
  }
}
noMove.movePreview(to: NSPoint(x: 100, y: 100), screenSize: screen, windowSize: NSSize(width: 640, height: 360))
check(noMove.geometryString == "640", "move cannot enable disabled position")
var noResize = InitialWindowGeometry("+20-30")
noResize.resizePreview(to: NSSize(width: 400, height: 225), screenSize: screen)
check(noResize.geometryString == "+20-30", "resize cannot enable disabled size")
for dimension in [InitialWindowGeometry.SizeDimension.width, .height] {
  for unit in [InitialWindowGeometry.Unit.points, .percent] {
    var draft = InitialWindowGeometry("400+20-30")
    draft.sizeDimension = dimension
    draft.sizeUnit = unit
    draft.resizePreview(to: NSSize(width: 420.4, height: 300.4), screenSize: screen)
    let expected = unit == .points ? (dimension == .width ? 420 : 300) : (dimension == .width ? 42 : 38)
    check(draft.sizeValue == expected && draft.sizeDimension == dimension && draft.sizeUnit == unit, "resize preserves \(dimension)/\(unit) and rounds selected value")
    check(draft.xValue == 20 && draft.yValue == 30 && draft.xAnchor == .left && draft.yAnchor == .top, "resize leaves position values and anchors unchanged")
  }
}
let small = InitialWindowGeometry("4000+1000-1000").previewFrame(screenSize: NSSize(width: 200, height: 100))
check(small.minX >= 0 && small.minY >= 0 && small.maxX <= 200 && small.maxY <= 100, "small screen preview is visible after proportional size and origin constraints")
check(InitialWindowGeometry("400").previewFrame(screenSize: .zero) == .zero, "empty preview screen is safe")
let local = InitialWindowGeometry("400+30-40").previewFrame(screenSize: screen)
let translated = local.offsetBy(dx: -1000, dy: 400)
check(near(translated.minX, -970) && near(translated.maxY, 1160), "preview is visible-frame local; monitor origin is applied by its caller")
var negative = InitialWindowGeometry("400+20-30")
negative.xValue = -1
negative.sizeValue = -4
check(negative.geometryString == "0+0-30", "explicit negative draft values serialize supported nonnegative tokens")
var mixed = InitialWindowGeometry("400-20+25%")
mixed.movePreview(to: NSPoint(x: 120, y: 100), screenSize: screen, windowSize: NSSize(width: 400, height: 225))
check(mixed.geometryString == "400-480+27%", "each axis retains its independent points/percent unit")
let beforeInvalidMove = mixed.geometryString
mixed.movePreview(to: NSPoint(x: CGFloat.nan, y: 100), screenSize: screen, windowSize: NSSize(width: 400, height: 225))
mixed.resizePreview(to: NSSize(width: CGFloat.infinity, height: 225), screenSize: screen)
check(mixed.geometryString == beforeInvalidMove, "nonfinite pointer geometry cannot mutate the draft")
var unsupported = InitialWindowGeometry("not geometry")
unsupported.sizeEnabled = true
unsupported.sizeEnabled = false
check(unsupported.geometryString == "not geometry", "off/on restoration preserves untouched unsupported raw input")
var free = InitialWindowGeometry("60%x500+50%-50%")
free.prepareIndependentSize(screenSize: screen, aspect: 16 / 9)
check(free.widthValue == 60 && free.heightValue == 500 && free.widthUnit == .percent && free.heightUnit == .points,
      "free aspect loads both dimensions and their independent units")
var freeFrame = free.previewFrame(screenSize: screen)
check(freeFrame.size == NSSize(width: 600, height: 500) && near(freeFrame.midX, 500) && near(freeFrame.midY, 400),
      "free aspect preview uses arbitrary dimensions and centered position")
free.resizePreview(to: NSSize(width: 700, height: 400), screenSize: screen)
check(free.geometryString == "70%x400+50%-50%", "free resize saves both dimensions without changing their units")
free.independentSize = false
freeFrame = free.previewFrame(screenSize: screen)
check(near(freeFrame.height, 700 * 9 / 16), "locking a saved free size restores proportional preview")
free.sizeValue = 80
check(free.geometryString == "80%+50%-50%", "editing locked size replaces the independent pair with a single controlling axis")
var heightDraft = InitialWindowGeometry("x400")
heightDraft.prepareIndependentSize(screenSize: screen, aspect: 16 / 9)
check(heightDraft.heightValue == 400 && heightDraft.widthValue == 711 && heightDraft.geometryString == "711x400",
      "legacy height-only geometry gains width without changing the chosen height")
var tiny = InitialWindowGeometry("10x900")
tiny.prepareIndependentSize(screenSize: screen, aspect: 16 / 9)
let bounded = tiny.previewFrame(screenSize: screen, minimumSize: NSSize(width: 400, height: 225))
check(bounded.size == NSSize(width: 400, height: 800), "free preview clamps each axis independently to player and screen limits")
let fittingScreen = NSSize(width: 1440, height: 900)
let floatingMinimum = NSSize(width: 400, height: 225)
check(InitialWindowGeometry("640").previewFrame(screenSize: fittingScreen, aspect: 3840.0 / 414,
      minimumSize: floatingMinimum, enforceMinimumAfterScreenFit: true).size == NSSize(width: 640, height: 225),
      "wide-crop preview preserves requested startup width while adding minimum-height fields")
for (raw, aspect, expected) in [("400", CGFloat(1.0 / 8), NSSize(width: 400, height: 900)),
                                 ("1440", CGFloat(8), NSSize(width: 1440, height: 225))] {
  let floating = InitialWindowGeometry(raw).previewFrame(screenSize: fittingScreen, aspect: aspect,
    minimumSize: floatingMinimum, enforceMinimumAfterScreenFit: true)
  check(floating.size == expected, "floating \(aspect) media preview retains both native minima after fitting the screen")
  check(near(floating.midX, fittingScreen.width / 2) && near(floating.midY, fittingScreen.height / 2),
        "floating fit resolves automatic centering from the final bounded dimensions")
}
let dockedTall = InitialWindowGeometry("400").previewFrame(screenSize: fittingScreen, aspect: 1.0 / 8)
check(dockedTall.size == NSSize(width: 112.5, height: 900), "docked screen fitting retains its original proportional behavior")
let proportionalFloating = InitialWindowGeometry("1440").previewFrame(screenSize: fittingScreen, aspect: 8,
  minimumSize: floatingMinimum)
check(proportionalFloating.size == NSSize(width: 1440, height: 180), "floating enforcement is explicit rather than inferred from minimum dimensions")
let tinyFloating = InitialWindowGeometry("400").previewFrame(screenSize: NSSize(width: 200, height: 100), aspect: 1.0 / 8,
  minimumSize: floatingMinimum, enforceMinimumAfterScreenFit: true)
check(tinyFloating.size == NSSize(width: 200, height: 100), "a physical display smaller than floating minima bounds each preview axis")
var floatingSeed = InitialWindowGeometry("400")
floatingSeed.prepareIndependentSize(screenSize: fittingScreen, aspect: 1.0 / 8, minimumSize: floatingMinimum,
  enforceMinimumAfterScreenFit: true)
check(floatingSeed.widthValue == 400 && floatingSeed.heightValue == 900,
      "unlocking aspect seeds the missing dimension from the actual bounded floating frame")
print("Completed \(checks) pure geometry-model checks; no window or production preferences accessed.")
