//
//  main.swift
//  vr2d-tests
//
//  Tests for the pure parts of VR2D — detection, frustum maths and the shader
//  parameters that replaced the plugin's filter strings. None of it touches
//  AppKit, mpv or OpenGL, so it compiles and runs on its own:
//
//      other/vr2d-tests/run.sh
//
//  This is a port of the plugin's `test/run.js`, which is the behavioural spec
//  these rules were written against.
//

import Foundation

var passed = 0
var failures: [String] = []

func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
  if actual == expected { passed += 1 }
  else { failures.append("\(name)\n    expected \(expected)\n    got      \(actual)") }
}

func checkNear(_ name: String, _ actual: Double, _ expected: Double, _ tolerance: Double) {
  if abs(actual - expected) <= tolerance { passed += 1 }
  else { failures.append("\(name)\n    expected \(expected) ±\(tolerance), got \(actual)") }
}

// MARK: - Detection

struct Summary: Equatable {
  var layout: VR2DLayout
  var swap: Bool
  var projection: VR2DProjection
  var hFov: Double
  var auto: Bool
}

func d(_ url: String, _ width: Int, _ height: Int,
       stereoIn: String? = nil, aggressive: Bool = false) -> Summary {
  let r = VR2DDetect.detect(url: url, width: width, height: height,
                            stereoIn: stereoIn, aggressive: aggressive)
  return Summary(layout: r.source.layout, swap: r.source.swapEyes,
                 projection: r.source.projection, hFov: r.source.inHFov, auto: r.auto)
}

// The naming convention from the brief.
check("180_180x180_3dh_LR",
      d("/v/Studio_Title_180_180x180_3dh_LR.mp4", 3840, 1920),
      Summary(layout: .sbs, swap: false, projection: .halfEquirect, hFov: 180, auto: true))

// Right eye stored first.
check("3dh_RL swaps eyes",
      d("/v/Title_180x180_3dh_RL.mp4", 3840, 1920),
      Summary(layout: .sbs, swap: true, projection: .halfEquirect, hFov: 180, auto: true))

// Lens profiles imply fisheye plus, by convention, a side-by-side pair.
check("MKX200 fisheye",
      d("/v/Title_MKX200_alpha.mp4", 4096, 2048),
      Summary(layout: .sbs, swap: false, projection: .fisheye, hFov: 200, auto: true))
check("MKX220 fisheye",
      d("/v/Title_MKX220.mp4", 4096, 2048),
      Summary(layout: .sbs, swap: false, projection: .fisheye, hFov: 220, auto: true))
check("RF52 dual fisheye",
      d("/v/Canon_RF52_clip.mp4", 3840, 1920),
      Summary(layout: .sbs, swap: false, projection: .fisheye, hFov: 190, auto: true))

// 360° over-under: a 1:1 frame whose halves are each 2:1.
check("360 3dv over-under",
      d("/v/Title_360_3dv_TB.mp4", 3840, 3840),
      Summary(layout: .tb, swap: false, projection: .equirect, hFov: 360, auto: true))

// 360° side-by-side is a 4:1 frame.
check("360 side-by-side",
      d("/v/Title_360_sbs.mp4", 7680, 1920),
      Summary(layout: .sbs, swap: false, projection: .equirect, hFov: 360, auto: true))

// A bare "180" on a square frame is monoscopic 180, not a stereo pair.
check("180 mono is square",
      d("/v/Title_vr180_mono.mp4", 2880, 2880),
      Summary(layout: .mono, swap: false, projection: .halfEquirect, hFov: 180, auto: true))

// Container metadata alone is enough.
check("container stereo flag",
      d("/v/no_hints_in_name.mp4", 4096, 2048, stereoIn: "sbs2l"),
      Summary(layout: .sbs, swap: false, projection: .halfEquirect, hFov: 180, auto: true))
check("container stereo flag, right eye first",
      d("/v/no_hints_in_name.mp4", 4096, 2048, stereoIn: "sbs2r"),
      Summary(layout: .sbs, swap: true, projection: .halfEquirect, hFov: 180, auto: true))
check("container says mono",
      d("/v/holiday.mp4", 1920, 1080, stereoIn: "mono"),
      Summary(layout: .mono, swap: false, projection: .equirect, hFov: 360, auto: false))

// Ordinary videos must be left alone. The descriptor still gets filled in — it
// is what a manual "turn it on anyway" would use — but `auto` stays false.
check("ordinary 16:9 film",
      d("/v/Some.Film.2024.1080p.BluRay.x264-GRP.mkv", 1920, 1080),
      Summary(layout: .mono, swap: false, projection: .equirect, hFov: 360, auto: false))
check("ordinary 2:1 film without hints stays off",
      d("/v/Some.Documentary.2160p.mp4", 3840, 1920),
      Summary(layout: .mono, swap: false, projection: .equirect, hFov: 360, auto: false))

// Weak hints need the aggressive setting before they count.
check("weak hint alone stays off",
      d("/v/My_VR_clip_360.mp4", 3840, 1920),
      Summary(layout: .mono, swap: false, projection: .equirect, hFov: 360, auto: false))
check("weak hint with aggressive detection",
      d("/v/My_VR_clip_360.mp4", 3840, 1920, aggressive: true),
      Summary(layout: .mono, swap: false, projection: .equirect, hFov: 360, auto: true))

// A strong name signal contradicted by the frame shape should not auto-engage.
check("sbs tag on a 16:9 frame does not auto-engage",
      d("/v/weird_sbs_tag.mp4", 1920, 1080).auto, false)

// URLs, escaping and extensions.
check("percent-escaped URL",
      d("file:///Users/x/My%20Clip_180x180_3dh_LR.mp4", 3840, 1920).layout, .sbs)
check("tokenizer", VR2DDetect.tokenize("/a/Clip_180_180x180_3dh_LR.mp4"),
      ["clip", "180", "180x180", "3dh", "lr"])
check("basename strips query",
      VR2DDetect.basename("http://h/v/Clip_180x180.mp4?token=1"), "Clip_180x180")

check("summary reads as prose",
      VR2DDetect.summarize(VR2DSource(layout: .sbs, swapEyes: false, projection: .halfEquirect,
                                      inHFov: 180, inVFov: 180)),
      "180° equirect, side-by-side")

// MARK: - Geometry

// A 90° diagonal on a 16:9 frame splits into a wider horizontal, narrower
// vertical, and both must invert cleanly.
let parts = VR2DGeometry.fovComponents(90, 1920, 1080)
checkNear("horizontal component of 90° diagonal", parts.h, 82.15, 0.05)
checkNear("vertical component of 90° diagonal", parts.v, 52.23, 0.05)
checkNear("diagonalFromHorizontal inverts fovComponents",
          VR2DGeometry.diagonalFromHorizontal(parts.h, 1920, 1080), 90, 0.01)
checkNear("diagonalFromVertical inverts fovComponents",
          VR2DGeometry.diagonalFromVertical(parts.v, 1920, 1080), 90, 0.01)

check("wrap180 folds past the seam", VR2DGeometry.wrap180(200), -160)
check("wrap180 leaves in-range angles alone", VR2DGeometry.wrap180(-90), -90)

let hemisphere = VR2DSource(projection: .halfEquirect, inHFov: 180, inVFov: 180)
let sphere = VR2DSource(projection: .equirect, inHFov: 360, inVFov: 180)

// On a hemisphere the view can never be aimed at the void outside it.
let clamped = VR2DGeometry.clampView(VR2DView(yaw: 175, pitch: 0, fov: 90), hemisphere, 1920, 1080)
checkNear("yaw is fenced in on a hemisphere", clamped.yaw, (180 - parts.h) / 2, 0.5)

// On a full sphere yaw is free but wraps.
check("yaw wraps on a full sphere",
      VR2DGeometry.clampView(VR2DView(yaw: 200, pitch: 0, fov: 90), sphere, 1920, 1080).yaw, -160)

// Pitch stops before the poles.
let pitched = VR2DGeometry.clampView(VR2DView(yaw: 0, pitch: 89, fov: 90), sphere, 1920, 1080)
checkNear("pitch stops short of the pole", pitched.pitch, (180 - parts.v) / 2, 0.5)

// A 180° hemisphere comfortably contains the widest view we ever render, so
// nothing is clipped there...
check("a hemisphere does not restrict zoom-out",
      VR2DGeometry.clampView(VR2DView(yaw: 0, pitch: 0, fov: 149), hemisphere, 1920, 1080).fov, 149)
// ...but a narrower source does, and the cap lands exactly on its coverage.
let narrow = VR2DSource(projection: .fisheye, inHFov: 100, inVFov: 100)
let zoomedOut = VR2DGeometry.clampView(VR2DView(yaw: 0, pitch: 0, fov: 149), narrow, 1920, 1080)
checkNear("zoom-out is capped by a narrow source", zoomedOut.fov, 107.7, 0.2)
checkNear("the capped view exactly fills the source horizontally",
          VR2DGeometry.fovComponents(zoomedOut.fov, 1920, 1080).h, 100, 0.05)

// Dragging right swings the view left; dragging down tips it up.
let dragged = VR2DGeometry.applyDrag(VR2DView(yaw: 0, pitch: 0, fov: 90),
                                     dx: 100, dy: 100, width: 1920, height: 1080)
check("drag right looks left", dragged.yaw < 0, true)
check("drag down looks up", dragged.pitch > 0, true)
checkNear("a full-width drag sweeps one horizontal field",
          VR2DGeometry.applyDrag(VR2DView(yaw: 0, pitch: 0, fov: 90),
                                 dx: 1920, dy: 0, width: 1920, height: 1080).yaw,
          -parts.h, 0.01)

check("zoom in reduces the field",
      VR2DGeometry.applyZoom(VR2DView(yaw: 0, pitch: 0, fov: 90), notches: -1).fov < 90, true)
check("zoom out widens the field",
      VR2DGeometry.applyZoom(VR2DView(yaw: 0, pitch: 0, fov: 90), notches: 1).fov > 90, true)

// The starting view is configured horizontally, since that is how the width of
// a shot actually reads on screen. A 90° *diagonal* comes out at only ~82°
// across, which looks cropped in on 180° footage.
let startDiagonal = VR2DGeometry.diagonalFromHorizontal(105, 2832, 1770)
checkNear("105° across is what the default asks for",
          VR2DGeometry.fovComponents(startDiagonal, 2832, 1770).h, 105, 0.01)
check("the new default really is wider than the old one",
      VR2DGeometry.fovComponents(startDiagonal, 2832, 1770).h >
        VR2DGeometry.fovComponents(90, 2832, 1770).h, true)
// It must still survive clamping against a 180° source rather than being
// silently pulled back in.
check("the default view fits inside a 180° source",
      abs(VR2DGeometry.clampView(VR2DView(yaw: 0, pitch: 0, fov: startDiagonal),
                                 hemisphere, 2832, 1770).fov - startDiagonal) < 0.01, true)

// MARK: - Eye selection
//
// The plugin cropped one eye out of the frame before reprojecting. The shader
// does the same thing as a texture transform, and must land on the same halves.
// Note `v` runs bottom-up, so for an over-under frame the eye stored first is
// the upper half of the texture.

func eye(_ layout: VR2DLayout, _ swap: Bool, _ which: VR2DEye) -> [Double] {
  let t = VR2DGeometry.eyeTransform(layout: layout, swapEyes: swap, eye: which)
  return [t.scale.0, t.scale.1, t.offset.0, t.offset.1]
}

check("sbs left eye", eye(.sbs, false, .left), [0.5, 1, 0, 0])
check("sbs right eye", eye(.sbs, false, .right), [0.5, 1, 0.5, 0])
check("sbs swapped, left eye is the right half", eye(.sbs, true, .left), [0.5, 1, 0.5, 0])
check("sbs swapped, right eye is the left half", eye(.sbs, true, .right), [0.5, 1, 0, 0])
check("tb left eye is the top half", eye(.tb, false, .left), [1, 0.5, 0, 0.5])
check("tb right eye is the bottom half", eye(.tb, false, .right), [1, 0.5, 0, 0])
check("tb swapped left eye is the bottom half", eye(.tb, true, .left), [1, 0.5, 0, 0])
check("mono needs no transform", eye(.mono, false, .left), [1, 1, 0, 0])

// MARK: - View rotation
//
// The shader builds a ray as `uRot * (x·tanH, y·tanV, -1)`, so the matrix has
// to send the view axis to the right place on the sphere.

func forward(yaw: Double, pitch: Double) -> [Double] {
  let m = VR2DGeometry.rotationMatrix(yaw: yaw, pitch: pitch)
  // Column-major times (0, 0, -1) is minus the third column.
  return [Double(-m[6]), Double(-m[7]), Double(-m[8])].map { ($0 * 1e6).rounded() / 1e6 }
}

check("looking straight ahead is -Z", forward(yaw: 0, pitch: 0), [0, 0, -1])
checkNear("positive yaw looks right", forward(yaw: 90, pitch: 0)[0], 1, 1e-5)
checkNear("positive pitch looks up", forward(yaw: 0, pitch: 90)[1], 1, 1e-5)
checkNear("yaw 90 leaves nothing pointing forward", forward(yaw: 90, pitch: 0)[2], 0, 1e-5)

// The rotation must stay orthonormal, or the view would shear.
let m = VR2DGeometry.rotationMatrix(yaw: 37, pitch: -22).map(Double.init)
checkNear("columns stay unit length", (m[0]*m[0] + m[1]*m[1] + m[2]*m[2]).squareRoot(), 1, 1e-6)
checkNear("columns stay perpendicular", m[0]*m[3] + m[1]*m[4] + m[2]*m[5], 0, 1e-6)

// Pitching must not roll the horizon: the view's right stays horizontal.
checkNear("pitching keeps the horizon level", VR2DGeometry.rotationMatrix(yaw: 20, pitch: 40).map(Double.init)[1], 0, 1e-6)

// MARK: -

if !failures.isEmpty {
  FileHandle.standardError.write("\n\(failures.count) failed, \(passed) passed\n\n".data(using: .utf8)!)
  for (i, failure) in failures.enumerated() {
    FileHandle.standardError.write("  \(i + 1). \(failure)\n\n".data(using: .utf8)!)
  }
  exit(1)
}
print("\(passed) checks passed")
