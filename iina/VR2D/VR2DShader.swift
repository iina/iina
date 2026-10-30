//
//  VR2DShader.swift
//  iina
//
//  GLSL for the VR2D reprojection pass.
//
//  One full-screen triangle. For each output pixel the fragment shader builds a
//  view ray from the current yaw / pitch / field of view, maps it back into
//  whichever projection the source is stored in, picks one eye out of the
//  packed frame and samples it.
//
//  The result is rectilinear (gnomonic), which is the projection a normal
//  camera produces — so straight lines in the world come out straight. That is
//  also the quickest way to spot a wrong input projection: get it wrong and
//  every straight edge bows.
//
//  Targets GLSL 1.50, i.e. an OpenGL 3.2 core profile, which is what
//  `ViewLayer` asks CGL for first.
//

import Foundation

enum VR2DShader {

  /// Positions come from `gl_VertexID`, so no vertex buffer is needed — but a
  /// vertex array object still has to be bound in a core profile.
  static let vertex = """
  #version 150

  out vec2 vUV;

  void main() {
    // (0,0), (2,0), (0,2) — one oversized triangle covering the viewport.
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    vUV = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
  }
  """

  static let fragment = """
  #version 150

  uniform sampler2D uSrc;
  /// tan of half the horizontal and vertical field of view.
  uniform vec2 uTanHalfFov;
  /// View-space ray to world-space ray.
  uniform mat3 uRot;
  /// 0 half-equirect, 1 equirect, 2 fisheye, 3 equi-angular cubemap.
  uniform int uProjection;
  /// Half the source's coverage, in radians: (horizontal, vertical).
  uniform vec2 uInFovHalf;
  /// Picks one eye: uv * uEye.xy + uEye.zw.
  uniform vec4 uEye;

  in vec2 vUV;
  out vec4 fragColor;

  const float PI = 3.141592653589793;

  // Equirectangular, and its 180° half. Both are the same mapping: longitude
  // and latitude scaled by whatever the source actually covers. A full sphere
  // is just the case where that coverage is 360x180.
  vec2 mapEquirect(vec3 d, out bool ok) {
    float lon = atan(d.x, -d.z);
    float lat = asin(clamp(d.y, -1.0, 1.0));
    ok = abs(lon) <= uInFovHalf.x + 1e-6 && abs(lat) <= uInFovHalf.y + 1e-6;
    return vec2(0.5 + lon / (2.0 * uInFovHalf.x),
                0.5 + lat / (2.0 * uInFovHalf.y));
  }

  // Equidistant fisheye: distance from the centre of the circle is proportional
  // to the angle away from the lens axis, so the lens FOV sets the scale.
  vec2 mapFisheye(vec3 d, out bool ok) {
    float theta = acos(clamp(-d.z, -1.0, 1.0));
    float h = length(d.xy);
    vec2 azimuth = h > 1e-9 ? d.xy / h : vec2(1.0, 0.0);
    vec2 r = theta * azimuth / uInFovHalf;
    ok = length(r) <= 1.0;
    return r * 0.5 + 0.5;
  }

  // Equi-angular cubemap, in the 3x2 packing YouTube uses. Within a face the
  // coordinate is proportional to angle rather than to the tangent, which is
  // what keeps the sampling density even — hence "equi-angular".
  //
  // The packing is:
  //
  //     top row     left (-X)   front (-Z)   right (+X)
  //     bottom row  down (-Y)   back  (+Z)   up    (+Y)
  //
  // with the bottom row stored on its side. Every face's orientation below was
  // measured out of a `v360`-produced cubemap of a coordinate-encoded sphere
  // rather than reasoned about, because the sign conventions are easy to get
  // subtly wrong and a mirrored face still looks like a plausible picture.
  vec2 mapEAC(vec3 d, out bool ok) {
    ok = true;

    vec3 a = abs(d);
    float m;
    vec2 c;         // face coordinates: x right, y up, as the face is stored
    vec2 cell;      // column across, row down

    if (a.x >= a.y && a.x >= a.z) {
      m = a.x;
      if (d.x > 0.0) { c = vec2(d.z, d.y);  cell = vec2(2.0, 0.0); }
      else           { c = vec2(-d.z, d.y); cell = vec2(0.0, 0.0); }
    } else if (a.y >= a.z) {
      m = a.y;
      if (d.y > 0.0) { c = vec2(-d.z, d.x); cell = vec2(2.0, 1.0); }
      else           { c = vec2(d.z, d.x);  cell = vec2(0.0, 1.0); }
    } else {
      m = a.z;
      if (d.z > 0.0) { c = vec2(d.y, d.x);  cell = vec2(1.0, 1.0); }
      else           { c = vec2(d.x, d.y);  cell = vec2(1.0, 0.0); }
    }

    // Proportional to angle rather than to the tangent: the "equi-angular" part.
    vec2 inFace = atan(c / max(m, 1e-9)) * (2.0 / PI) + 0.5;

    // `v` runs bottom-up, so row 0 of the packing is the upper half.
    return vec2((cell.x + inFace.x) / 3.0,
                (inFace.y + 1.0 - cell.y) * 0.5);
  }

  void main() {
    vec2 ndc = vUV * 2.0 - 1.0;
    vec3 dir = normalize(uRot * vec3(ndc * uTanHalfFov, -1.0));

    bool ok;
    vec2 uv;
    if (uProjection == 2) uv = mapFisheye(dir, ok);
    else if (uProjection == 3) uv = mapEAC(dir, ok);
    else uv = mapEquirect(dir, ok);

    if (!ok) {
      fragColor = vec4(0.0, 0.0, 0.0, 1.0);
      return;
    }
    fragColor = texture(uSrc, clamp(uv, 0.0, 1.0) * uEye.xy + uEye.zw);
  }
  """
}
