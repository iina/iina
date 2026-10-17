#!/usr/bin/env python3
"""Read malformed cache fixtures through the production ThumbnailCache class."""

import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.source_root.resolve()
    extensions = (root / "iina/Extensions.swift").read_text()
    start = extensions.index("extension FileHandle {")
    file_handle = extensions[start:extensions.index("\nextension String {", start)]
    start = extensions.index("  init<T: BitwiseCopyable>(bytesOf thing: T)")
    data_init = extensions[start:extensions.index("\n  }", start) + 4]
    harness = r'''
import Cocoa

enum Logger {
  enum Level { case debug, error, warning }
  static func makeSubsystem(_ name: String, _ icons: [String]) -> String { name }
  static func log(_ message: () -> String, level: Level, subsystem: String) {}
}
enum Utility {
  static var thumbnailCacheURL = URL(fileURLWithPath: CommandLine.arguments[1])
  static func createDirIfNotExist(url: URL) {
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
}
enum Preference {
  enum Key { case maxThumbnailPreviewCacheSize }
  static func integer(for key: Key) -> Int { 1 }
}
enum FloatingPointByteCountFormatter {
  enum PrefixFactor: Int { case mi = 1048576 }
}
final class CacheManager {
  static let shared = CacheManager()
  var needsRefresh = true
  func getCacheSize() -> Int { 0 }
  func clearOldCache() {}
}
final class FFThumbnail {
  var realTime = 0.0
  var image: NSImage?
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}
''' + file_handle + "\nextension Data {\n" + data_init + "\n}\n" + r'''

let files = FileManager.default
let cache = Utility.thumbnailCacheURL
Utility.createDirIfNotExist(url: cache)
let metadata = Data(repeating: 0, count: 17)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
  bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<2 {
  for x in 0..<2 {
    bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y)
  }
}
let jpeg = bitmap.representation(using: .jpeg, properties: [:])!

func block(_ length: Int64, timestamp: Double = 1.25, payload: Data = Data()) -> Data {
  Data(bytesOf: length) + Data(bytesOf: timestamp) + payload
}
func reject(_ name: String, _ data: Data) throws {
  let url = cache.appendingPathComponent(name)
  try data.write(to: url)
  check(ThumbnailCache.read(forName: name) == nil, "\(name) must be rejected")
  check(!files.fileExists(atPath: url.path), "\(name) must be deleted")
}

// All bytes are controlled; no real cache files or preferences are touched.
for (index, length) in [Int64.min, -1, 0, 1, 7, 8, Int64.max].enumerated() {
  try reject("invalid-length-\(index)", metadata + block(length))
}
for size in 0..<metadata.count {
  try reject("short-metadata-\(size)", metadata.prefix(size))
}
for size in 1..<8 {
  try reject("short-length-\(size)", metadata + Data(repeating: 0, count: size))
}
for size in 0..<8 {
  try reject("short-timestamp-\(size)", metadata + Data(bytesOf: Int64(9)) + Data(repeating: 0, count: size))
}
// A decodable JPEG must still be rejected if its declared block extends past EOF.
try reject("oversized-valid-image", metadata + block(Int64(9 + jpeg.count), payload: jpeg))
try reject("short-image", metadata + block(Int64(8 + jpeg.count), payload: jpeg.prefix(jpeg.count / 2)))
try reject("bad-image", metadata + block(12, payload: Data(repeating: 0, count: 4)))

let validBlock = block(Int64(8 + jpeg.count), payload: jpeg)
let valid = metadata + validBlock + block(Int64(8 + jpeg.count), timestamp: 2.5, payload: jpeg)
try valid.write(to: cache.appendingPathComponent("valid"))
let thumbnails = ThumbnailCache.read(forName: "valid")
check(thumbnails?.count == 2, "valid multi-image cache")
check(thumbnails?[0].realTime == 1.25 && thumbnails?[1].realTime == 2.5, "timestamps preserved")
check(thumbnails?.allSatisfy { $0.image != nil } == true, "images decoded")
check(files.fileExists(atPath: cache.appendingPathComponent("valid").path), "valid cache retained")
try reject("valid-then-bad", metadata + validBlock + block(-1))
try reject("trailing-byte", metadata + validBlock + Data([0]))

try metadata.write(to: cache.appendingPathComponent("empty"))
check(ThumbnailCache.read(forName: "empty")?.isEmpty == true, "metadata-only cache remains valid")
check(ThumbnailCache.read(forName: "missing") == nil, "missing file is handled")

// Exercise the unmodified writer and real metadata verification for compatibility.
let video = cache.appendingPathComponent("video")
try Data([1, 2, 3]).write(to: video)
let thumbnail = FFThumbnail()
thumbnail.realTime = 3.75
thumbnail.image = NSImage(data: jpeg)
ThumbnailCache.write([thumbnail], forName: "roundtrip", forVideo: video)
check(ThumbnailCache.fileIsCached(forName: "roundtrip", forVideo: video), "writer metadata accepted")
let roundtrip = ThumbnailCache.read(forName: "roundtrip")
check(roundtrip?.count == 1 && roundtrip?[0].realTime == 3.75, "writer/reader roundtrip")
print("PASS: 44 malformed caches deleted; valid, empty, missing and writer/reader roundtrip cases")
'''
    with tempfile.TemporaryDirectory(prefix="iina-thumbnail-cache-test-") as folder:
        folder = Path(folder)
        (folder / "main.swift").write_text(harness)
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5", str(root / "iina/ThumbnailCache.swift"),
            str(folder / "main.swift"), "-o", str(folder / "probe"),
        ], check=True, timeout=60)
        subprocess.run([str(folder / "probe"), str(folder / "cache")], check=True, timeout=15)


if __name__ == "__main__":
    main()
