//
//  VR2DGeometry.swift
//  iina
//
//  Viewing-frustum maths for the VR2D reprojection pass.
//
//  The shader is aimed with a *diagonal* field of view, because that is the one
//  number that behaves sensibly when the window changes shape. Panning limits
//  and drag sensitivity are far easier to reason about horizontally and
//  vertically, so most of this file converts between the two.
//
//  Nothing here touches AppKit, mpv or OpenGL, so it can be compiled and tested
//  on its own — see `other/vr2d-tests`.
//

import Foundation

/// How a single eye of a VR frame maps onto the sphere.
///
/// The raw values are part of the shader interface: they are passed straight
/// through as the `uProjection` uniform, so they must stay in step with the
/// branches in `VR2DShader.fragment`.
enum VR2DProjection: Int, CaseIterable {
  /// Half equirectangular — a 180° hemisphere, square per eye. `v360`'s `he`.
  case halfEquirect = 0
  /// Equirectangular — the full sphere, 2:1 per eye. `v360`'s `e`.
  case equirect = 1
  /// Equidistant fisheye, covering `inHFov` × `inVFov`. `v360`'s `fisheye`.
  case fisheye = 2
  /// Equi-angular cubemap in YouTube's 3x2 packing. `v360`'s `eac`.
  case eac = 3
}

/// How the two eyes are packed into one frame.
enum VR2DLayout: String, CaseIterable {
  case mono
  /// Side by side.
  case sbs
  /// Over under.
  case tb
}

/// Which eye to show.
enum VR2DEye: String, CaseIterable {
  case left
  case right
}

/// Everything the shader needs to know about how the source is stored.
struct VR2DSource: Equatable {
  var layout: VR2DLayout = .mono
  /// `true` when the right eye is stored first (RL / BT).
  var swapEyes = false
  var projection: VR2DProjection = .halfEquirect
  /// Horizontal coverage of one eye, in degrees.
  var inHFov: Double = 180
  /// Vertical coverage of one eye, in degrees.
  var inVFov: Double = 180

  static let defaultFor180 = VR2DSource()
}

/// Where the viewer is looking. Angles in degrees, `fov` is diagonal.
struct VR2DView: Equatable {
  var yaw: Double = 0
  var pitch: Double = 0
  var fov: Double = 90
}

enum VR2DGeometry {

  private static let deg = 180 / Double.pi
  private static let rad = Double.pi / 180

  /// Beyond this a rectilinear projection stretches the edges into mush.
  static let maxDiagonalFov: Double = 150
  static let minDiagonalFov: Double = 15

  static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
    return value < lo ? lo : (value > hi ? hi : value)
  }

  /// Fold an angle into [-180, 180).
  static func wrap180(_ degrees: Double) -> Double {
    let x = (degrees + 180).truncatingRemainder(dividingBy: 360)
    return (x < 0 ? x + 360 : x) - 180
  }

  /// Split a diagonal FOV into its horizontal and vertical components for a
  /// rectilinear (gnomonic) projection of the given pixel size.
  static func fovComponents(_ dFov: Double, _ width: Double, _ height: Double) -> (h: Double, v: Double) {
    let diagonal = (width * width + height * height).squareRoot()
    guard diagonal > 0 else { return (dFov, dFov) }
    let halfDiag = tan(clamp(dFov, 1, 179) / 2 * rad)
    return (h: 2 * atan((width / diagonal) * halfDiag) * deg,
            v: 2 * atan((height / diagonal) * halfDiag) * deg)
  }

  /// Inverse of `fovComponents` for the horizontal axis.
  static func diagonalFromHorizontal(_ hFov: Double, _ width: Double, _ height: Double) -> Double {
    let diagonal = (width * width + height * height).squareRoot()
    guard width > 0 else { return hFov }
    return 2 * atan((diagonal / width) * tan(clamp(hFov, 1, 179) / 2 * rad)) * deg
  }

  /// Inverse of `fovComponents` for the vertical axis.
  static func diagonalFromVertical(_ vFov: Double, _ width: Double, _ height: Double) -> Double {
    let diagonal = (width * width + height * height).squareRoot()
    guard height > 0 else { return vFov }
    return 2 * atan((diagonal / height) * tan(clamp(vFov, 1, 179) / 2 * rad)) * deg
  }

  /// Widest diagonal FOV that still fits inside what the source actually
  /// covers, so zooming out can never reveal the void outside a hemisphere.
  static func maxFov(_ source: VR2DSource, _ width: Double, _ height: Double) -> Double {
    var limits = [maxDiagonalFov]
    if source.inHFov < 360 {
      limits.append(diagonalFromHorizontal(min(source.inHFov, 170), width, height))
    }
    limits.append(diagonalFromVertical(min(source.inVFov, 170), width, height))
    return clamp(limits.min()!, minDiagonalFov, maxDiagonalFov)
  }

  /// Constrain a view so it always looks at real pixels: yaw wraps freely on a
  /// full sphere but is fenced in on a hemisphere, and pitch never tips past
  /// the poles.
  static func clampView(_ view: VR2DView, _ source: VR2DSource,
                        _ width: Double, _ height: Double) -> VR2DView {
    let fov = clamp(view.fov, minDiagonalFov, maxFov(source, width, height))
    let parts = fovComponents(fov, width, height)

    let yaw: Double
    if source.inHFov >= 359 {
      yaw = wrap180(view.yaw)
    } else {
      let yawLimit = max(0, (source.inHFov - parts.h) / 2)
      yaw = clamp(view.yaw, -yawLimit, yawLimit)
    }

    let pitchLimit = max(0, (source.inVFov - parts.v) / 2)
    let pitch = clamp(view.pitch, -pitchLimit, pitchLimit)

    return VR2DView(yaw: yaw, pitch: pitch, fov: fov)
  }

  /// Translate a mouse drag into a view change, so the image tracks the cursor:
  /// dragging right swings the view left, dragging down tips it up.
  static func applyDrag(_ view: VR2DView, dx: Double, dy: Double,
                        width: Double, height: Double, sensitivity: Double = 1) -> VR2DView {
    let parts = fovComponents(view.fov, width, height)
    guard width > 0, height > 0 else { return view }
    return VR2DView(yaw: view.yaw - (dx / width) * parts.h * sensitivity,
                    pitch: view.pitch + (dy / height) * parts.v * sensitivity,
                    fov: view.fov)
  }

  /// Zoom by a number of notches. Multiplicative, so each notch feels the same
  /// whether you are wide open or zoomed right in.
  static func applyZoom(_ view: VR2DView, notches: Double) -> VR2DView {
    return VR2DView(yaw: view.yaw, pitch: view.pitch,
                    fov: clamp(view.fov * pow(1.1, notches), minDiagonalFov, maxDiagonalFov))
  }

  /// Pan by a step in degrees.
  static func applyPanStep(_ view: VR2DView, dxDeg: Double, dyDeg: Double) -> VR2DView {
    return VR2DView(yaw: view.yaw + dxDeg, pitch: view.pitch + dyDeg, fov: view.fov)
  }

  // MARK: - Shader parameters

  /// The rotation that turns a view-space ray into a world-space one, in
  /// column-major order ready for `glUniformMatrix3fv`.
  ///
  /// View space looks down -Z with +X right and +Y up. Yaw turns about +Y and
  /// is applied after pitch, so pitching up never rolls the horizon. Positive
  /// yaw looks right, positive pitch looks up:
  ///
  ///     R = Ryaw · Rpitch  maps (0, 0, -1) to (sin yaw · cos pitch,
  ///                                            sin pitch,
  ///                                            -cos yaw · cos pitch)
  static func rotationMatrix(yaw: Double, pitch: Double) -> [Float] {
    let cy = cos(yaw * rad), sy = sin(yaw * rad)
    let cp = cos(pitch * rad), sp = sin(pitch * rad)

    // Column-major: [col0, col1, col2].
    return [
      Float(cy), 0, Float(sy),
      Float(-sy * sp), Float(cp), Float(cy * sp),
      Float(-sy * cp), Float(-sp), Float(cy * cp),
    ]
  }

  /// The scale and offset that pick one eye out of the packed frame, applied to
  /// a per-eye UV as `uv * scale + offset`.
  ///
  /// This is the plugin's `crop` filter expressed as a texture transform. Like
  /// the crop it costs nothing and — unlike `v360`'s own `in_stereo` handling —
  /// it can pick either eye.
  ///
  /// - Note: `v` runs bottom-up, so for an over-under frame the eye stored
  ///   *first* is the one at the top, which is the upper half of the texture.
  static func eyeTransform(layout: VR2DLayout, swapEyes: Bool, eye: VR2DEye) -> (scale: (Double, Double), offset: (Double, Double)) {
    // Asking for the right eye, or the eyes being stored swapped, each flip
    // which half we want; both together cancel out.
    let secondHalf = (eye == .right) != swapEyes
    switch layout {
    case .mono:
      return (scale: (1, 1), offset: (0, 0))
    case .sbs:
      return (scale: (0.5, 1), offset: (secondHalf ? 0.5 : 0, 0))
    case .tb:
      return (scale: (1, 0.5), offset: (0, secondHalf ? 0 : 0.5))
    }
  }
}
