import Foundation

@main
struct VideoProcessingChecks {
  static func main() throws {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
      precondition(condition(), label)
      count += 1
    }
    func graph(_ ids: [Int] = [1], _ settings: [Int: VideoTrackProcessing] = [:]) -> String? {
      ProcessedVideoGraph.make(ids, width: 64, height: 48, settings: settings)
    }
    check(VideoTrackProcessing().isNeutral, "defaults")
    var displayOnly = VideoTrackProcessing()
    displayOnly.cropDescription = "Previous UI label"
    check(displayOnly.isNeutral, "UI labels do not engage processing")
    check(graph() == "[vid1]null[vo]", "single passthrough")
    check(graph([1, 2]) == VideoTrackLayerGraph.make([1, 2], width: 64, height: 48), "native default graph")
    for ids in [[], [0], [-1], [1, 1]] { check(graph(ids) == nil, "invalid IDs \(ids)") }
    check(ProcessedVideoGraph.make([1], width: 0, height: 48, settings: [:]) == nil, "invalid canvas")
    var cases: [[String: Any]] = []
    func record(_ name: String, _ value: VideoTrackProcessing, ids: [Int] = [1], settingsID: Int = 1) {
      let result = graph(ids, [settingsID: value])
      check(result != nil, "valid graph \(name)")
      cases.append(["name": name, "ids": ids, "graph": result!])
    }
    var value = VideoTrackProcessing()
    value.crop = TrackVideoCrop(x: 16, y: 0, width: 32, height: 48)
    record("crop", value)
    value.aspect = "2:1"
    record("aspect", value)
    value.rotation = 90
    record("rotation", value)
    value = VideoTrackProcessing(); value.brightness = 25
    record("brightness", value)
    value.saturation = -100; value.gamma = 25; value.contrast = 10; value.hue = 50
    record("color-alpha", value, ids: [1, 2])
    record("color-alpha-solo", value)
    value.aspect = "1:1"
    record("color-pad", value, ids: [1, 2])
    value = VideoTrackProcessing(); value.aspect = "1:1"
    record("square-front", value, ids: [1, 2])
    record("square-bottom", value, ids: [2, 1])
    value.aspect = "Default"; value.brightness = 1
    record("source-sar", value)
    let anamorphic = ProcessedVideoGraph.make([1], width: 64, height: 48,
      settings: [1: value], pixelAspect: 2)!
    cases.append(["name": "canvas-sar", "ids": [1], "graph": anamorphic])
    for sar in [0, -1, Double.infinity, Double.nan] {
      check(ProcessedVideoGraph.make([1], width: 64, height: 48,
        settings: [1: value], pixelAspect: sar) == nil, "invalid canvas SAR")
    }
    value = VideoTrackProcessing()
    value.crop = .init(x: 0, y: 0, width: 64, height: 48)
    record("geometry-high-depth", value)
    for aspect in ["", "1:0", "NaN:1", "1:inf", "-1:2", "1:1:1", "1;null:1"] {
      value = VideoTrackProcessing(); value.aspect = aspect
      check(graph([1], [1: value]) == nil, "invalid aspect \(aspect)")
    }
    for rotation in [-90, 45, 360] {
      value = VideoTrackProcessing(); value.rotation = rotation
      check(graph([1], [1: value]) == nil, "invalid rotation")
    }
    value = VideoTrackProcessing(); value.crop = .init(x: -1, y: 0, width: 20, height: 20)
    check(graph([1], [1: value]) == nil, "invalid crop")
    for keyPath in [\VideoTrackProcessing.brightness, \.contrast, \.saturation, \.gamma, \.hue] {
      value = VideoTrackProcessing(); value[keyPath: keyPath] = 101
      check(graph([1], [1: value]) == nil, "invalid color value")
      value[keyPath: keyPath] = -100
      check(graph([1], [1: value]) != nil, "valid color minimum")
      value[keyPath: keyPath] = 100
      check(graph([1], [1: value]) != nil, "valid color maximum")
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("graphs.json"))
    print("\(count) video processing checks passed")
  }
}
