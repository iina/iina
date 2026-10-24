import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  checks += 1
  print("PASS \(message)")
}
func cube(inverted: Bool = false) -> Data {
  var text = "TITLE \"LUT test\"\nLUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n"
  for b in 0...1 { for g in 0...1 { for r in 0...1 {
    text += inverted ? "\(1-r) \(1-g) \(1-b)\n" : "\(r) \(g) \(b)\n"
  } } }
  return Data(text.utf8)
}
let identity = cube(), inverse = cube(inverted: true)
let preparedSource = output.appendingPathComponent("Prepared.cube")
try identity.write(to: preparedSource)
let prepared = try VideoLUTLibrary.prepareImport(preparedSource)
try inverse.write(to: preparedSource)
let preparedLibrary = VideoLUTLibrary(directory: output.appendingPathComponent("Prepared library"))
let preparedEntry = try preparedLibrary.importPreparedFile(prepared)
check(try! Data(contentsOf: preparedEntry.url) == identity,
      "prepared imports commit the exact validated bytes even if the source later changes")
check(VideoLUTLibrary.isValidCube(identity), "identity cube imports")
check(VideoLUTLibrary.isValidCube(inverse), "creative cube imports")
for invalid in ["", "LUT_3D_SIZE 0\n", "LUT_3D_SIZE 2\n0 0 0\n", "LUT_1D_SIZE 2\n0 0 0\n1 1 1\n",
                String(data: identity, encoding: .utf8)! + "0 0 0\n",
                String(data: identity, encoding: .utf8)!.replacingOccurrences(of: "DOMAIN_MAX 1 1 1", with: "DOMAIN_MAX 0 0 0"),
                String(data: identity, encoding: .utf8)!.replacingOccurrences(of: "0 0 0\n1 0 0", with: "nan 0 0\n1 0 0")] {
  check(!VideoLUTLibrary.isValidCube(Data(invalid.utf8)), "invalid cube rejected before applying")
}
let source = output.appendingPathComponent("Look's [тест], blue; a:b\\c.cube")
let library = VideoLUTLibrary(directory: output.appendingPathComponent("Application Support/LUTs"))
try identity.write(to: source)
let first = try library.importFile(source)
check(first.url != source, "import owns a persistent copy")
let repeated = try library.importFile(source)
check(first.url == repeated.url, "reimport does not duplicate a LUT")
try inverse.write(to: source)
let second = try library.importFile(source)
check(second.url != first.url && second.name.hasSuffix(" 2"), "same filename preserves distinct LUTs")
let firstData = try Data(contentsOf: first.url)
check(firstData == identity, "a new LUT never overwrites the first")
try FileManager.default.removeItem(at: source)
let entries = try library.entries()
check(entries.count == 2, "library survives removal of the source")
let reloaded = try VideoLUTLibrary(directory: library.directory).entries()
check(reloaded.count == 2, "library is rediscovered after relaunch")
var profile = VideoTrackProcessing()
profile.lutPath = second.url.path
check(!profile.isNeutral, "LUT activates processing even with neutral sliders")
let trackGraph = ProcessedVideoGraph.make([1], width: 64, height: 48, settings: [1: profile])!
check(trackGraph.contains(second.graph), "track LUT enters the source graph")
profile.rotation = 90
var state = TrackProcessingState()
state.video[1] = profile
state.reset(.videoGeometry)
check(state.video[1]?.lutPath == second.url.path, "geometry reset preserves the LUT")
state.video[1] = profile
state.reset(.videoColor)
check(state.video[1]?.lutPath == nil && state.video[1]?.rotation == 90, "color reset clears the LUT and preserves geometry")
let cases: [[String: String]] = [
  ["name": "identity", "path": first.url.path, "graph": first.graph],
  ["name": "inverse", "path": second.url.path, "graph": second.graph],
  ["name": "track-inverse", "graph": trackGraph]
]
try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("graphs.json"))
let removalLibrary = VideoLUTLibrary(directory: output.appendingPathComponent("Removal/LUTs"))
let original = output.appendingPathComponent("Removal original.cube")
try identity.write(to: original)
let removable = try removalLibrary.importFile(original)
let storedData = try Data(contentsOf: removable.url)
let trashed = try removalLibrary.remove(removable)!
check(FileManager.default.fileExists(atPath: original.path) && !FileManager.default.fileExists(atPath: removable.url.path),
      "Delete clears the library directory and preserves the original")
check(try! Data(contentsOf: trashed) == storedData, "Trash preserves the exact managed LUT bytes")
check(try! removalLibrary.entries().isEmpty, "deleted LUT leaves the menu")
let rediscovered = VideoLUTLibrary(directory: removalLibrary.directory)
check(try! rediscovered.entries().isEmpty, "deleted LUT stays absent after relaunch")
try FileManager.default.moveItem(at: trashed, to: removable.url)
check((try! rediscovered.entries()).count == 1, "restoring the file from Trash restores its library entry")
let trashedAgain = try rediscovered.remove(removable)!
let restored = try rediscovered.importFile(original)
check(restored.url == removable.url && (try! rediscovered.entries()).count == 1,
      "reimport after deletion restores the name without a duplicate suffix")
// Recover our test-only trash item into the output folder, leaving Trash clean.
try FileManager.default.moveItem(at: trashedAgain, to: output.appendingPathComponent("Recovered library copy.cube"))
check(try! Data(contentsOf: original) == identity, "original import file remains byte-for-byte intact")
do {
  try rediscovered.remove(.init(url: original))
  preconditionFailure("outside deletion must fail")
} catch { check(FileManager.default.fileExists(atPath: original.path), "Delete rejects unmanaged original files") }
let unavailable = restored.url.appendingPathExtension("away")
try FileManager.default.moveItem(at: restored.url, to: unavailable)
do {
  try rediscovered.remove(restored)
  preconditionFailure("missing file deletion must fail")
} catch { check(true, "missing library files report deletion failure") }
try FileManager.default.moveItem(at: unavailable, to: restored.url)
// Existing hidden files remain recoverable; changing deletion does not purge them.
let legacyIndex = removalLibrary.directory.appendingPathComponent(".removed.json")
try JSONEncoder().encode([restored.url.lastPathComponent]).write(to: legacyIndex)
check((try! rediscovered.entries()).isEmpty && FileManager.default.fileExists(atPath: restored.url.path),
      "legacy hidden copies remain on disk without automatic deletion")
let legacyRestored = try rediscovered.importFile(original)
check(legacyRestored.url == restored.url && (try! rediscovered.entries()).count == 1,
      "reimport still recovers a legacy hidden copy")
print("LUT library and scoped state: \(checks) checks passed.")
