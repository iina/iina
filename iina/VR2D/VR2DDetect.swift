//
//  VR2DDetect.swift
//  iina
//
//  Works out, from the file name plus whatever the container told mpv, how a
//  video is packed: how the two eyes are stored, how one eye maps onto the
//  sphere, and how much of the sphere it covers.
//
//  Detection uses a strong/weak evidence model. A file is flattened
//  automatically only when there is at least one *strong* signal and the shape
//  of the frame agrees with it, because plenty of ordinary files contain a bare
//  "180" or the word "VR" and must be left completely alone.
//
//  Like `VR2DGeometry`, this file touches no AppKit, mpv or OpenGL, so it can
//  be compiled and tested on its own — see `other/vr2d-tests`.
//

import Foundation

/// What detection made of a file.
struct VR2DDetection {
  var source = VR2DSource()
  /// Frame aspect ratio, or 0 when the frame size is not known yet.
  var aspect: Double = 0
  /// `true` when the evidence is good enough to turn reprojection on unasked.
  var auto = false
  /// Evidence strong enough to act on by itself.
  var strong: [String] = []
  /// Evidence that only counts alongside a plausible aspect ratio.
  var weak: [String] = []
  /// Short human-readable description, e.g. `"180° equirect, side-by-side"`.
  var summary = ""
}

enum VR2DDetect {

  // MARK: - Name tokenising

  /// Strip a URL down to its file name, without query string or extension.
  static func basename(_ url: String) -> String {
    var s = url
    if let hash = s.firstIndex(of: "#") { s = String(s[s.startIndex..<hash]) }
    if let query = s.firstIndex(of: "?") { s = String(s[s.startIndex..<query]) }
    if let slash = s.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
      s = String(s[s.index(after: slash)...])
    }
    // Malformed percent-escapes: keep the raw name, it is still useful.
    s = s.removingPercentEncoding ?? s

    // Drop a trailing extension of one to five alphanumerics.
    if let dot = s.lastIndex(of: ".") {
      let ext = s[s.index(after: dot)...]
      if (1...5).contains(ext.count) && ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
        s = String(s[s.startIndex..<dot])
      }
    }
    return s
  }

  /// Split a file name into lowercase alphanumeric tokens.
  /// `"Clip_180_180x180_3dh_LR.mp4"` becomes
  /// `["clip", "180", "180x180", "3dh", "lr"]`.
  static func tokenize(_ url: String) -> [String] {
    let name = basename(url).lowercased()
    var tokens: [String] = []
    var current = ""
    for character in name {
      if character.isASCII && (character.isLetter || character.isNumber) {
        current.append(character)
      } else if !current.isEmpty {
        tokens.append(current)
        current = ""
      }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
  }

  // MARK: - Token vocabulary

  // How the two eyes are laid out inside one frame.
  private static let sbsTokens = ["3dh", "sbs", "hsbs", "fsbs", "sbs2l", "lr", "leftright"]
  private static let sbsSwappedTokens = ["rl", "sbs2r", "rightleft"]
  private static let tbTokens = ["3dv", "tb", "ou", "htb", "ftb", "ab2l", "overunder", "topbottom"]
  private static let tbSwappedTokens = ["bt", "ab2r", "ut", "bottomtop"]
  private static let monoTokens = ["mono", "2d", "monoscopic"]

  /// Lens and camera profiles. These names imply both a fisheye projection and,
  /// by near-universal convention, a side-by-side stereo pair.
  private static let lensProfiles: [String: Double] = [
    "mkx200": 200,
    "mkx220": 220,
    "vrca220": 220,
    "rf52": 190,
    "f180": 180,
  ]

  // Projection named outright in the file name.
  private static let equirect180Tokens = ["180x180", "vr180", "equirect180", "er180", "hequirect"]
  private static let equirect360Tokens = ["360x180", "vr360", "equirect", "erp", "spherical"]
  private static let eacTokens = ["eac", "equiangular"]

  /// Only a hint on its own — plenty of non-VR files contain a bare "180"/"360",
  /// and a headset name says nothing about the packing.
  private static let weakVRTokens = [
    "vr", "oculus", "gearvr", "psvr", "daydream", "deovr", "smartphone", "vive", "quest", "headset",
  ]

  // MARK: - Aspect-ratio reasoning

  /// Aspect ratio of one eye once the frame has been split.
  static func perEyeAspect(_ aspect: Double, _ layout: VR2DLayout) -> Double {
    switch layout {
    case .sbs: return aspect / 2
    case .tb: return aspect * 2
    case .mono: return aspect
    }
  }

  private static func near(_ value: Double, _ target: Double, _ tolerance: Double = 0.08) -> Bool {
    guard value > 0, target > 0 else { return false }
    return abs(value - target) / target <= tolerance
  }

  /// Layouts whose per-eye aspect ratio would come out at a sane VR value —
  /// 1:1 for a 180° hemisphere, 2:1 for a full sphere. Most likely first.
  private static func layoutsMatchingAspect(_ aspect: Double) -> [(layout: VR2DLayout, projection: VR2DProjection)] {
    var out: [(VR2DLayout, VR2DProjection)] = []
    for layout in [VR2DLayout.sbs, .tb, .mono] {
      let eye = perEyeAspect(aspect, layout)
      if near(eye, 2) { out.append((layout, .equirect)) }
      else if near(eye, 1) { out.append((layout, .halfEquirect)) }
    }
    return out
  }

  // MARK: - Container metadata

  /// Interpret mpv's `video-params/stereo-in`, which surfaces the container's
  /// stereoscopic flag (Matroska StereoMode, MP4 `st3d`).
  static func layoutFromStereoIn(_ stereoIn: String?) -> (layout: VR2DLayout, swapEyes: Bool)? {
    guard let stereoIn, !stereoIn.isEmpty, stereoIn != "mono", stereoIn != "unknown" else { return nil }
    let s = stereoIn.lowercased()
    if s.hasPrefix("sbs") { return (.sbs, s == "sbs2r") }
    if s.hasPrefix("ab") { return (.tb, s == "ab2r") }
    return nil
  }

  // MARK: - Detection

  private static let projectionFov: [VR2DProjection: (h: Double, v: Double)] = [
    .halfEquirect: (180, 180),
    .equirect: (360, 180),
    .eac: (360, 180),
    .fisheye: (180, 180),
  ]

  /// Analyse a video.
  ///
  /// - Parameters:
  ///   - url: file path or URL
  ///   - width: decoded frame width in pixels
  ///   - height: decoded frame height in pixels
  ///   - stereoIn: mpv's `video-params/stereo-in`
  ///   - aggressive: treat weak hints as enough to turn reprojection on
  static func detect(url: String, width: Int, height: Int,
                     stereoIn: String? = nil, aggressive: Bool = false) -> VR2DDetection {
    let tokens = tokenize(url)
    let tokenSet = Set(tokens)
    func has(_ token: String) -> Bool { tokenSet.contains(token) }
    func hasAny(_ list: [String]) -> Bool { list.contains(where: has) }

    let aspect = width > 0 && height > 0 ? Double(width) / Double(height) : 0

    var strong: [String] = []
    var weak: [String] = []

    var layout: VR2DLayout?
    var swapEyes = false
    var projection: VR2DProjection?
    var hFov: Double?
    var vFov: Double?

    // Container metadata: the most trustworthy source we have.
    if let fromContainer = layoutFromStereoIn(stereoIn) {
      layout = fromContainer.layout
      swapEyes = fromContainer.swapEyes
      strong.append("container stereo flag (\(stereoIn!))")
    }

    // An explicit stereo layout in the name.
    if hasAny(sbsSwappedTokens) {
      layout = .sbs
      swapEyes = true
      strong.append("name says side-by-side, right eye first")
    } else if hasAny(sbsTokens) {
      layout = .sbs
      swapEyes = false
      strong.append("name says side-by-side")
    } else if hasAny(tbSwappedTokens) {
      layout = .tb
      swapEyes = true
      strong.append("name says over-under, bottom eye first")
    } else if hasAny(tbTokens) {
      layout = .tb
      swapEyes = false
      strong.append("name says over-under")
    } else if hasAny(monoTokens) {
      layout = .mono
      strong.append("name says monoscopic")
    }

    // A lens profile implies fisheye, and conventionally side-by-side.
    let lensToken = tokens.first { lensProfiles[$0] != nil }
    let fisheyeToken = tokens.first { token in
      guard token.hasPrefix("fisheye") else { return false }
      let digits = token.dropFirst("fisheye".count)
      return (2...3).contains(digits.count) && digits.allSatisfy { $0.isNumber }
    }

    if let lensToken {
      projection = .fisheye
      hFov = lensProfiles[lensToken]
      vFov = hFov
      strong.append("lens profile \(lensToken.uppercased()) (\(Int(hFov!))° fisheye)")
      if layout == nil { layout = .sbs }
    } else if let fisheyeToken {
      projection = .fisheye
      hFov = Double(fisheyeToken.dropFirst("fisheye".count)) ?? 180
      vFov = hFov
      strong.append("name says \(Int(hFov!))° fisheye")
      if layout == nil { layout = .sbs }
    } else if has("fisheye") {
      projection = .fisheye
      hFov = 180
      vFov = 180
      strong.append("name says fisheye")
      if layout == nil { layout = .sbs }
    }

    // A projection named in the file name.
    if projection == nil {
      if hasAny(equirect180Tokens) {
        projection = .halfEquirect
        strong.append("name says 180° equirectangular")
      } else if hasAny(eacTokens) {
        projection = .eac
        strong.append("name says equi-angular cubemap")
      } else if hasAny(equirect360Tokens) {
        projection = .equirect
        strong.append("name says 360° equirectangular")
      }
    }

    // Weak hints.
    if projection == nil && has("180") {
      projection = .halfEquirect
      weak.append("bare \"180\" in the name")
    } else if projection == nil && has("360") {
      projection = .equirect
      weak.append("bare \"360\" in the name")
    }
    if let weakVR = tokens.first(where: { weakVRTokens.contains($0) }) {
      weak.append("\"\(weakVR)\" in the name")
    }

    // Fill the gaps from the frame geometry.
    let candidates = layoutsMatchingAspect(aspect)
    let aspectFits = candidates.contains { layout == nil || $0.layout == layout }

    if layout == nil {
      // Nothing said how the eyes are packed, so let the frame's shape decide —
      // but only among the packings that agree with the projection we already
      // believe in. A 2:1 frame is 180° side-by-side or 360° monoscopic;
      // knowing which projection it is settles it.
      var matching = projection == nil ? [] : candidates.filter { $0.projection == projection }
      if matching.isEmpty {
        // Still ambiguous: read the frame as a single image rather than
        // inventing a stereo pair.
        matching = candidates.filter { $0.layout == .mono }
      }
      layout = matching.first?.layout ?? candidates.first?.layout ?? .mono
    }

    if projection == nil {
      projection = near(perEyeAspect(aspect, layout!), 2, 0.25) ? .equirect : .halfEquirect
    }

    let defaults = projectionFov[projection!] ?? (180, 180)
    if hFov == nil { hFov = defaults.h }
    if vFov == nil { vFov = defaults.v }

    // A 360° source stored as a single hemisphere-shaped eye is a
    // contradiction; trust the geometry over a bare "360" in the name.
    if projection == .equirect && near(perEyeAspect(aspect, layout!), 1, 0.12) {
      projection = .halfEquirect
      hFov = 180
      vFov = 180
    }

    let auto: Bool
    if !strong.isEmpty {
      auto = aspectFits || aspect == 0
    } else {
      auto = !weak.isEmpty && aspectFits && aggressive
    }

    let source = VR2DSource(layout: layout!, swapEyes: swapEyes, projection: projection!,
                            inHFov: hFov!, inVFov: vFov!)
    return VR2DDetection(source: source, aspect: aspect, auto: auto, strong: strong, weak: weak,
                         summary: summarize(source))
  }

  /// Short human-readable description, e.g. `"180° equirect, side-by-side"`.
  static func summarize(_ source: VR2DSource) -> String {
    let projection: String
    switch source.projection {
    case .fisheye: projection = "\(Int(source.inHFov))° fisheye"
    case .halfEquirect: projection = "180° equirect"
    case .eac: projection = "equi-angular cubemap"
    case .equirect: projection = "360° equirect"
    }

    let stereo: String
    switch source.layout {
    case .sbs: stereo = "side-by-side"
    case .tb: stereo = "over-under"
    case .mono: stereo = "monoscopic"
    }

    return "\(projection), \(stereo)"
  }
}
