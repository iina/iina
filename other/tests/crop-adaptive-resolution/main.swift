import Cocoa

// PRODUCTION_GEOMETRY

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  precondition(value(), message)
  checks += 1
}
func near(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.000001) -> Bool {
  abs(a - b) <= tolerance
}
func points(_ rect: NSRect) -> [NSPoint] {
  [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
   NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.maxY)]
}
func project(_ point: NSPoint, through layer: CALayer) -> NSPoint {
  let x = point.x - layer.bounds.minX - layer.bounds.width * layer.anchorPoint.x
  let y = point.y - layer.bounds.minY - layer.bounds.height * layer.anchorPoint.y
  let t = layer.transform
  return NSPoint(x: layer.position.x + x * t.m11 + y * t.m21 + t.m41,
                 y: layer.position.y + x * t.m12 + y * t.m22 + t.m42)
}
func near(_ a: [NSPoint], _ b: [NSPoint]) -> Bool {
  a.count == b.count && zip(a, b).allSatisfy { near($0.x, $1.x) && near($0.y, $1.y) }
}
func scale(base: NSSize = NSSize(width: 800, height: 450),
           maximum: NSSize, source: NSSize = NSSize(width: 3840, height: 2160),
           backing: CGFloat = 2, legacy: CGFloat = 2) -> CGFloat {
  NativeCropVideoPresentation.rasterScale(base: base, maximum: maximum, source: source,
                                        backingScale: backing, legacyScale: legacy)
}

check(near(scale(maximum: NSSize(width: 800, height: 450)), 2),
      "unchanged 2x viewport spends no extra raster pixels")
check(near(scale(maximum: NSSize(width: 1600, height: 900)), 4),
      "2x crop enlargement receives 3200x1800 pixels for its Retina endpoint")
check(near(scale(maximum: NSSize(width: 1600, height: 900), backing: 1, legacy: 1), 2),
      "1x backing scale requires half the raster density for the same point geometry")
check(near(scale(maximum: NSSize(width: 400, height: 225)), 2),
      "shrinking or full-frame Cancel does not downsample the starting frame")
check(near(scale(maximum: NSSize(width: 800, height: 900)), 4),
      "height demand is retained when window constraints change the aspect ratio")
check(near(scale(maximum: NSSize(width: 2400, height: 450)), 4.8),
      "width-driven crop stops at all available 4K source detail")
check(near(scale(maximum: NSSize(width: 80000, height: 45000)), 4.8),
      "tiny crop cannot allocate a giant full-source surface")
check(near(scale(maximum: NSSize(width: 80000, height: 45000),
                 source: NSSize(width: 1920, height: 1080)), 2.4),
      "1080p source stops at source detail instead of wasting a 4K allocation")
check(near(scale(maximum: NSSize(width: 80000, height: 45000),
                 source: NSSize(width: 640, height: 360)), 2),
      "source detail cap cannot reduce existing screen-resolution quality")

let anamorphic = scale(base: NSSize(width: 512, height: 288),
                      maximum: NSSize(width: 2048, height: 1152),
                      source: NSSize(width: 720, height: 576))
check(near(anamorphic, 2) && near(288 * anamorphic, 576),
      "720x576 anamorphic source keeps every source row in a 1024x576 display raster")
let rotatedAnamorphic = scale(base: NSSize(width: 288, height: 512),
                             maximum: NSSize(width: 1152, height: 2048),
                             source: NSSize(width: 576, height: 720))
check(near(rotatedAnamorphic, 2) && near(288 * rotatedAnamorphic, 576),
      "quarter-rotated anamorphic source retains swapped source axes")
let eightK = scale(maximum: NSSize(width: 80000, height: 45000),
                   source: NSSize(width: 7680, height: 4320))
check(near(eightK, 4.8), "8K source with strong crop respects the 4K pixel-area budget")
let panoramic = scale(base: NSSize(width: 1000, height: 10),
                      maximum: NSSize(width: 10000, height: 100),
                      source: NSSize(width: 16000, height: 160))
check(near(panoramic, 8.192), "8192-pixel edge cap bounds extreme panoramas below the area cap")
let alreadyLarge = scale(base: NSSize(width: 6000, height: 3500),
                         maximum: NSSize(width: 12000, height: 7000),
                         source: NSSize(width: 24000, height: 14000))
check(near(alreadyLarge, 2), "large existing display raster is preserved without further expansion")

for invalid in [NSSize.zero, NSSize(width: -1, height: 2), NSSize(width: CGFloat.infinity, height: 2),
                NSSize(width: CGFloat.nan, height: 2)] {
  check(scale(base: invalid, maximum: NSSize(width: 1600, height: 900)) == 2,
        "invalid base dimensions retain a valid legacy density")
  check(scale(maximum: invalid) == 2, "invalid endpoint dimensions retain legacy density")
  check(scale(maximum: NSSize(width: 1600, height: 900), source: invalid) == 2,
        "invalid source metadata cannot amplify raster density")
}
for invalid: CGFloat in [0, -1, .infinity, .nan] {
  check(scale(maximum: NSSize(width: 1600, height: 900), backing: invalid) == 2,
        "invalid backing scale retains a valid fallback")
  check(scale(maximum: NSSize(width: 1600, height: 900), legacy: invalid) == 1,
        "invalid fallback scale yields a finite positive density")
}

// Check actual rounded native dimensions over portrait, landscape and extreme
// display aspects, independently from the implementation's scale calculation.
for base in [NSSize(width: 800, height: 450), NSSize(width: 450, height: 800),
             NSSize(width: 3000, height: 20), NSSize(width: 20, height: 3000)] {
  for backing: CGFloat in [1, 2] {
    for zoom: CGFloat in [1, 1.25, 4, 10000] {
      let density = scale(base: base, maximum: NSSize(width: base.width * zoom, height: base.height * zoom),
                          source: NSSize(width: base.width * 100, height: base.height * 100),
                          backing: backing, legacy: backing)
      let width = (base.width * density).rounded(), height = (base.height * density).rounded()
      // Half-pixel rounding of each edge can add at most this many pixels.
      let roundingAllowance = (width + height) / 2 + 1
      check(density.isFinite && density >= backing && width <= 8192 && height <= 8192 &&
            width * height <= 3840 * 2160 + roundingAllowance,
            "rounded raster obeys positive legacy floor, 4K area and 8192 edge limits")
    }
  }
}

final class ProbeLayer: CALayer {
  var assignedScales: [CGFloat] = []
  var assignedBounds: [NSRect] = []
  override var contentsScale: CGFloat { didSet { assignedScales.append(contentsScale) } }
  override var bounds: NSRect { didSet { assignedBounds.append(bounds) } }
}
func context(backing: CGFloat = 2) -> (NSView, NSView, ProbeLayer) {
  let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
  container.wantsLayer = true
  let native = NSView(frame: NSRect(x: 30, y: 50, width: 320, height: 180))
  let layer = ProbeLayer()
  layer.contentsScale = backing
  layer.contentsFormat = .RGBA16Float
  layer.contentsGravity = .resizeAspectFill
  layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
  native.layer = layer
  native.wantsLayer = true
  container.addSubview(native)
  return (container, native, layer)
}

// Exercise the two real allocation boundaries. Save upgrades an already-live
// editor raster; entry/preset plans before the first native projection.
for preparedBeforePresent in [false, true] {
 for backing: CGFloat in [1, 2] {
  let (container, native, layer) = context(backing: backing)
  let oldFrame = native.frame, parent = layer.superlayer
  let oldMask = CALayer()
  layer.mask = oldMask
  var acquired = 0, restored = 0
  let owner = NativeCropVideoPresentation(view: native, container: container,
    pixelSize: NSSize(width: 3840, height: 2160),
    beginLayout: { acquired += 1 }, restoreLayout: { restored += 1 })
  let start = NSRect(x: 10, y: 20, width: 800, height: 450)
  let end = NSRect(x: -300, y: -120, width: 1600, height: 900)
  if preparedBeforePresent { owner.prepareRaster(for: [start, end]) }
  owner.present(frame: start, clip: container.bounds)
  let projectedImage = points(layer.bounds).map { project($0, through: layer) }
  let projectedAperture = points(layer.mask!.frame).map { project($0, through: layer) }
  let mask = layer.mask
  let beforeUpgrade = layer.assignedScales.count
  if !preparedBeforePresent {
    owner.prepareRaster(for: [start, end])
    check(layer.assignedScales.count == beforeUpgrade + 1,
          "Save upgrades physical allocation once at its explicit preparation boundary")
  }
  check(near(layer.contentsScale, backing) && near(layer.bounds.width * layer.contentsScale, end.width * backing) &&
        near(layer.bounds.height * layer.contentsScale, end.height * backing),
        "planned physical raster covers the endpoint while retaining normal screen density")
  check(layer.mask === mask && near(projectedImage, points(layer.bounds).map { project($0, through: layer) }) &&
        near(projectedAperture, points(layer.mask!.frame).map { project($0, through: layer) }),
        "logical allocation upgrade preserves projected image and aperture coordinates")
  check(acquired == 1 && restored == 0, "active upgrade retains the original single layout acquisition")
  let bounds = layer.bounds, fixedDensity = layer.contentsScale
  let scaleAssignments = layer.assignedScales.count, boundsAssignments = layer.assignedBounds.count
  for tick in 0...100 {
    let progress = CGFloat(tick) / 100
    owner.present(frame: CropTransitionOverlay.interpolate(start, end, progress), clip: container.bounds)
    check(layer.bounds == bounds && layer.contentsScale == fixedDensity &&
          layer.assignedScales.count == scaleAssignments && layer.assignedBounds.count == boundsAssignments &&
          native.layer === layer && layer.superlayer === parent,
          "animation tick retains one native layer and fixed logical allocation/screen density")
  }
  check(near(layer.bounds.width * layer.transform.m11, end.width) &&
        near(layer.bounds.height * layer.transform.m22, end.height) &&
        layer.contentsFormat == .RGBA16Float && layer.contents == nil,
        "planned allocation reaches the requested endpoint with native floating-point output")
  owner.restore()
  owner.restore()
  check(acquired == 1 && restored == 1 && native.frame == oldFrame && layer.mask === oldMask &&
        near(layer.contentsScale, backing) && layer.contentsGravity == .resizeAspectFill &&
        layer.autoresizingMask == [.layerWidthSizable, .layerHeightSizable] && layer.contentsFormat == .RGBA16Float,
        "success/cancellation restores screen density and native layout once without reducing HDR precision")
 }
}

do {
  let (container, native, layer) = context()
  let owner = NativeCropVideoPresentation(view: native, container: container,
                                         pixelSize: NSSize(width: 3840, height: 2160))
  let start = NSRect(x: 0, y: 0, width: 800, height: 450)
  owner.prepareRaster(for: [.zero, NSRect(x: 0, y: 0, width: CGFloat.infinity, height: 4), start])
  owner.present(frame: start, clip: container.bounds)
  check(near(layer.contentsScale, 2), "invalid planned frames are ignored beside a valid endpoint")
  owner.prepareRaster(for: [.zero])
  check(near(layer.contentsScale, 2), "invalid later plan cannot corrupt an active native raster")
  owner.restore()
}

do {
  let (container, native, layer) = context()
  let owner = NativeCropVideoPresentation(view: native, container: container,
                                         pixelSize: NSSize(width: 3840, height: 2160))
  owner.present(frame: NSRect(x: -100000, y: -50000, width: 200000, height: 112500), clip: container.bounds)
  check(near(layer.bounds.width * layer.contentsScale, 3840) &&
        near(layer.bounds.height * layer.contentsScale, 2160),
        "nonadaptive geometry presentation keeps its previous bounded raster policy")
  owner.restore()
}

do {
  let (container, native, layer) = context()
  let overlay = CropTransitionOverlay(frame: container.bounds)
  overlay.useNativeVideo(native, in: container, pixelSize: NSSize(width: 3840, height: 2160))
  let from = CropTransitionOverlay.PlayerFrame(selection: NSRect(x: 0, y: 0, width: 1, height: 1),
    videoRect: container.bounds, viewport: container.bounds)
  let to = CropTransitionOverlay.PlayerFrame(selection: NSRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
    videoRect: container.bounds, viewport: container.bounds)
  overlay.showPlayerFrame(frame: from)
  overlay.setPlayerTargetFrame(to, present: false)
  overlay.presentPlayerTransition(progress: 0)
  check(near(layer.contentsScale, 2) && near(layer.bounds.width * layer.contentsScale, 3200) &&
        near(layer.bounds.height * layer.contentsScale, 1800),
        "production player-target hook covers the magnified source at normal screen density")
  let fixed = layer.bounds, densityAssignments = layer.assignedScales.count
  for tick in 0...100 { overlay.presentPlayerTransition(progress: CGFloat(tick) / 100) }
  check(layer.bounds == fixed && layer.assignedScales.count == densityAssignments,
        "production preset-crop projection never reallocates after target preparation")
  overlay.releaseNativeVideo()
  check(overlay.nativeVideo == nil && near(layer.contentsScale, 2), "preset owner releases adaptive density")
}

// The Save endpoint must use the crop's full-source extent. The aperture alone
// stays viewport-sized and would otherwise conceal a twofold quality deficit.
do {
  let (container, native, layer) = context()
  let overlay = CropTransitionOverlay(frame: container.bounds)
  overlay.useNativeVideo(native, in: container, pixelSize: NSSize(width: 3840, height: 2160))
  let source = NSSize(width: 3840, height: 2160)
  let start = container.bounds
  overlay.show(selection: NSRect(x: 960, y: 540, width: 1920, height: 1080), sourceSize: source,
    initialFrame: start, initialClip: start, initialSelection: NSRect(origin: .zero, size: source),
    controlsImage: nil, controlsFrame: .zero)
  overlay.nativeVideo?.present(frame: start, clip: start)
  let end = overlay.transformedImage(fitting: container.bounds)
  check(near(end.width, 1600) && near(end.height, 900),
        "half-width/height crop expands full-source endpoint to twice the viewport")
  overlay.nativeVideo?.prepareRaster(for: [start, end])
  let fixed = layer.bounds, densityAssignments = layer.assignedScales.count
  for tick in 0...100 { overlay.presentTransition(to: container.bounds, progress: CGFloat(tick) / 100) }
  check(near(layer.contentsScale, 2) && near(layer.bounds.width * layer.contentsScale, 3200) &&
        near(layer.bounds.height * layer.contentsScale, 1800) &&
        layer.bounds == fixed && layer.assignedScales.count == densityAssignments,
        "production Custom Save keeps physical source coverage and normal density through final zoom")
  let canonicalMask = CALayer()
  layer.mask = canonicalMask
  layer.transform = CATransform3DIdentity
  overlay.releaseNativeVideo()
  check(layer.mask === canonicalMask && CATransform3DIsIdentity(layer.transform) && near(layer.contentsScale, 2),
        "adaptive owner cannot restore obsolete geometry over a newer canonical handoff")
}

print("PASS: \(checks) adaptive raster sizing, source/budget limits and native ownership checks; no window or renderer")
