import Foundation

struct TrackVideoCrop: Equatable {
  var x: Int
  var y: Int
  var width: Int
  var height: Int
}

/// Per-source processing. Master controls remain native mpv output controls.
struct VideoTrackProcessing: Equatable {
  var aspect: String = "Default"
  var crop: TrackVideoCrop? = nil
  var cropDescription: String = "None"
  var rotation: Int = 0
  var brightness: Int = 0
  var contrast: Int = 0
  var saturation: Int = 0
  var gamma: Int = 0
  var hue: Int = 0
  var lutPath: String? = nil

  var isNeutral: Bool {
    aspect == "Default" && crop == nil && rotation == 0 &&
      brightness == 0 && contrast == 0 && saturation == 0 && gamma == 0 && hue == 0 && lutPath == nil
  }
}

/// File-local geometry excludes window size; visiting another file must retain the user's window scale.
struct MediaVideoGeometryState {
  static let optionNames = [
    "video-aspect-override", "video-aspect-method", "video-rotate", "video-crop", "video-unscaled", "panscan", "video-zoom",
    "video-pan-x", "video-pan-y", "video-scale-x", "video-scale-y",
    "video-align-x", "video-align-y"
  ]
  var options: [String: String] = [:]
  var filters: [String] = []
  var filterIndices: [Int] = []
  var aspectDescription = "Default"
  var cropDescription = "None"
  var video: [Int: VideoTrackProcessing] = [:]
  var videoTarget = 0
  var videoOrder: [Int] = []
  var activeVideo: [Int] = []

  mutating func removeLUT(atPath path: String) {
    for id in Array(video.keys) where video[id]?.lutPath == path {
      video[id]?.lutPath = nil
    }
  }

  static func aspectDescription(for ratio: Double, preferred: String) -> String {
    guard ratio.isFinite, ratio > 0 else { return "Default" }
    let parts = preferred.split(separator: ":").compactMap { Double($0) }
    if parts.count == 2, parts[1] > 0, abs(parts[0] / parts[1] - ratio) < 0.00001 { return preferred }
    for (w, h) in [(4, 3), (16, 9), (16, 10), (21, 9), (3, 2), (5, 4)] {
      if abs(Double(w) / Double(h) - ratio) < 0.00001 { return "\(w):\(h)" }
    }
    return "\(ratio):1"
  }
}

enum ProcessedVideoGraph {
  /// IDs are front-to-back. Width/height and pixelAspect describe the fixed
  /// bottom-source canvas. Each source's incoming SAR is respected when fitting.
  static func make(_ ids: [Int], width: Int, height: Int,
                   settings: [Int: VideoTrackProcessing], pixelAspect: Double = 1) -> String? {
    guard !ids.isEmpty, ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count,
          width > 0, height > 0, pixelAspect.isFinite, pixelAspect > 0 else { return nil }
    if ids.allSatisfy({ settings[$0, default: VideoTrackProcessing()].isNeutral }) {
      if ids.count == 1 { return "[vid\(ids[0])]null[vo]" }
      return VideoTrackLayerGraph.make(ids, width: width, height: height)
    }

    var parts: [String] = []
    for (index, id) in ids.reversed().enumerated() {
      let value = settings[id, default: VideoTrackProcessing()]
      guard [0, 90, 180, 270].contains(value.rotation),
            [value.brightness, value.contrast, value.saturation, value.gamma, value.hue]
              .allSatisfy({ (-100...100).contains($0) }) else { return nil }
      let hasColor = value.brightness != 0 || value.contrast != 0 || value.saturation != 0 ||
        value.gamma != 0 || value.hue != 0
      // Avoid 8-bit overlay/EQ formats when a single source only needs geometry or a LUT.
      let pixelFormat = ids.count == 1 && !hasColor
        ? (value.lutPath == nil ? "yuva444p16le" : "gbrap16le") : "rgba"
      var filters = ["format=\(pixelFormat)"]
      if let crop = value.crop {
        guard crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0 else { return nil }
        // Decoded dimensions can differ from demux metadata; clamp crop to the incoming frame.
        filters.append("crop=w='min(iw,\(crop.width))':h='min(ih,\(crop.height))':" +
                       "x='min(iw-ow,\(crop.x))':y='min(ih-oh,\(crop.y))':exact=1")
      }
      if value.aspect != "Default" {
        guard let aspect = ratio(value.aspect) else { return nil }
        filters.append("setsar=sar=\(number(aspect))*h/w:max=1000000")
      }
      switch value.rotation {
      case 90: filters.append("transpose=clock")
      case 180: filters += ["hflip", "vflip"]
      case 270: filters.append("transpose=cclock")
      default: break
      }

      if let path = value.lutPath { filters.append(lutFilter(path: path)) }

      if hasColor {
        // eq drops alpha; preserve it on a separate branch and restore it before padding.
        parts.append("[vid\(id)]" + filters.joined(separator: ",") +
                     ",split[vc\(index)][va\(index)]")
        parts.append("[va\(index)]alphaextract[valpha\(index)]")
        let eq = "eq=brightness=\(number(Double(value.brightness) / 100)):" +
          "contrast=\(number(Double(value.contrast + 100) / 100)):" +
          "saturation=\(number(Double(value.saturation + 100) / 100)):" +
          "gamma=\(number(pow(8, Double(value.gamma) / 100)))"
        parts.append("[vc\(index)]format=yuv444p,\(eq)," +
                     "hue=h=\(number(Double(value.hue) * 1.8)),format=rgb24[vcolor\(index)]")
        parts.append("[vcolor\(index)][valpha\(index)]alphamerge[vprocessed\(index)]")
      } else {
        parts.append("[vid\(id)]" + filters.joined(separator: ",") + "[vprocessed\(index)]")
      }
      // Use DAR after rotation and convert every layer to the bottom canvas's SAR.
      parts.append("[vprocessed\(index)]" +
                   "scale=w='max(1,trunc(min(\(width),\(height)*dar/\(number(pixelAspect)))))':" +
                   "h='max(1,trunc(min(\(height),\(width)*\(number(pixelAspect))/dar)))'," +
                   "setsar=sar=\(number(pixelAspect)):max=1000000," +
                   "format=\(pixelFormat),pad=w=\(width):h=\(height):x=(ow-iw)/2:y=(oh-ih)/2:color=black@0" +
                   "[vlayer\(index)]")
    }
    if ids.count == 1 {
      parts.append("[vlayer0]null[vo]")
    } else {
      for index in 1..<ids.count {
        let base = index == 1 ? "vlayer0" : "vcombined\(index - 1)"
        let output = index == ids.count - 1 ? "vo" : "vcombined\(index)"
        parts.append("[\(base)][vlayer\(index)]overlay=x=0:y=0:format=auto:" +
                     "alpha=straight:eof_action=pass[\(output)]")
      }
    }
    return parts.joined(separator: ";")
  }

  /// A filename crosses the AVOption parser and then the filtergraph parser.
  /// Escape both layers; mpv's outer graph value is quoted separately.
  static func lutFilter(path: String) -> String {
    func escape(_ value: String, special: String) -> String {
      value.reduce(into: "") { result, character in
        if special.contains(character) || character.isWhitespace { result.append("\\") }
        result.append(character)
      }
    }
    let option = escape(path, special: "\\':")
    let graph = escape(option, special: "\\'[],;")
    return "lut3d=file=\(graph):interp=tetrahedral"
  }

  private static func ratio(_ text: String) -> Double? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]),
          numerator.isFinite, denominator.isFinite, numerator > 0, denominator > 0 else { return nil }
    let result = numerator / denominator
    return result.isFinite && result > 0 ? result : nil
  }

  private static func number(_ value: Double) -> String {
    String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), value)
  }
}
