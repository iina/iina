#!/usr/bin/env python3
"""Exercise production subtitle matching, weighted distance and FileInfo lifetimes."""

import argparse
from pathlib import Path
import subprocess
import tempfile


SUPPORT = r'''
import Foundation

enum Logger {
  struct Subsystem {}
  enum Level { case debug, verbose, warning, error }
  static func makeSubsystem(_ name: String, _ icons: [String]) -> Subsystem { Subsystem() }
  static func log(_ text: @autoclosure () -> String, level: Level = .debug, subsystem: Subsystem) {}
}
@propertyWrapper final class Locked<Value> {
  var wrappedValue: Value
  var projectedValue: Locked { self }
  init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
  func withLock(_ body: (inout Value) -> Void) { body(&wrappedValue) }
}
final class Info { @Locked var matchedSubs: [String: [URL]] = [:] }
final class Player { let info = Info() }
enum Cancelled: Error { case ticket }
final class WeakFile {
  weak var file: FileInfo?
  init(_ file: FileInfo) { self.file = file }
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
final class MatcherProbe {
  let player = Player()
  var unmatchedVideos: [FileInfo] = []
  var subtitles: [FileInfo] = []
  var mediaFiles: [FileInfo] = []
  var checksRemaining = Int.max
  func checkTicket() throws {
    if checksRemaining == 0 { throw Cancelled.ticket }
    checksRemaining -= 1
  }
  func log(_ text: @autoclosure () -> String, level: Logger.Level = .debug) {}
  func run() throws { try forceMatchUnmatchedVideos() }
'''

HARNESS = r'''
func file(_ name: String) -> FileInfo { FileInfo(URL(fileURLWithPath: "/fixture/" + name)) }
func run(_ videos: [String], _ subs: [String], expected: [String: [String]], cancelAfter: Int? = nil, related: Bool = false, preMatched: Set<Int> = []) throws {
  var references: [WeakFile] = []
  try autoreleasepool {
    let matcher = MatcherProbe()
    matcher.unmatchedVideos = videos.map(file)
    matcher.mediaFiles = matcher.unmatchedVideos
    matcher.subtitles = subs.map(file)
    for index in preMatched { matcher.subtitles[index].isMatched = true }
    references = (matcher.mediaFiles + matcher.subtitles).map(WeakFile.init)
    if related { matcher.mediaFiles[0].relatedSubs = matcher.subtitles }
    if let count = cancelAfter { matcher.checksRemaining = count }
    do {
      try matcher.run()
      check(cancelAfter == nil, "cancellation must throw")
    } catch Cancelled.ticket {
      check(cancelAfter != nil, "unexpected cancellation")
    }
    let actual = Dictionary(uniqueKeysWithValues: matcher.player.info.matchedSubs.map {
      (URL(fileURLWithPath: $0.key).lastPathComponent, $0.value.map(\.lastPathComponent))
    })
    check(actual == expected, "matching results: \(actual), expected \(expected)")
    if related {
      check(matcher.mediaFiles[0].relatedSubs.count == subs.count, "UI subtitle relationships survive matching")
      check(matcher.mediaFiles[0].relatedSubs[0] === matcher.subtitles[0], "UI keeps the original subtitle objects")
    }
  }
  check(references.allSatisfy { $0.file == nil }, "FileInfo objects must be released after matching, including cancellation")
}

// Exact and fuzzy mutual nearest neighbours, and two equally close subtitles.
try run(["Episode01.mkv", "Episode02.mkv"], ["Episode01.srt", "Episode02.srt"], expected: ["Episode01.mkv": ["Episode01.srt"], "Episode02.mkv": ["Episode02.srt"]], related: true)
try run(["Episode01.mkv"], ["Episode01.en.srt", "Episode01.fr.srt"], expected: ["Episode01.mkv": ["Episode01.en.srt", "Episode01.fr.srt"]])
try run(["abcdefgh01.mkv", "abcdefgh02.mkv"], ["abcdefgh03.srt"], expected: ["abcdefgh01.mkv": ["abcdefgh03.srt"], "abcdefgh02.mkv": ["abcdefgh03.srt"]])
try run(["A.mkv"], ["Z.srt"], expected: [:])
// Production distance is 4 and the threshold is 4: only strictly smaller distances match.
try run(["ABCD.mkv"], ["ABXY.srt"], expected: [:])
try run([], ["Episode01.srt"], expected: [:])
try run(["Episode01.mkv"], [], expected: [:])
try run(["Episode01.mkv"], ["Episode01.srt"], expected: [:], preMatched: [0])
// Throw after partially populating the distance tables.
try run(["Episode01.mkv", "Episode02.mkv"], ["Episode01.srt", "Episode02.srt"], expected: [:], cancelAfter: 3)
try run((0..<100).map { "Episode\($0).mkv" }, (0..<100).map { "Episode\($0).srt" }, expected: [:])
for _ in 0..<100 {
  try run(["Episode01.mkv"], ["Episode01.srt"], expected: ["Episode01.mkv": ["Episode01.srt"]])
}
print("PASS: production weighted distance, matching results and ties, exact-threshold rejection, empty inputs, already matched subtitles, file-count guard, UI relationships, cancellation and 100 released matching sessions")
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.source_root.resolve()
    matcher = (root / "iina/AutoFileMatcher.swift").read_text()
    start = matcher.index("  private func forceMatchUnmatchedVideos() throws {")
    method = matcher[start:matcher.index("\n  func startMatching()", start)]
    with tempfile.TemporaryDirectory(prefix="iina-subtitle-ownership-") as folder:
        folder = Path(folder)
        # Compile unchanged production files with only the unrelated application bridge stubbed.
        for name in ("ObjcUtils.m", "ObjcUtils.h"):
            (folder / name).write_bytes((root / "iina" / name).read_bytes())
        (folder / "iina-Bridging-Header.h").write_text("")
        (folder / "bridge.h").write_text('#import <Foundation/Foundation.h>\n#import "ObjcUtils.h"\n')
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-c", str(folder / "ObjcUtils.m"), "-o", str(folder / "ObjcUtils.o")], check=True, timeout=60)
        (folder / "main.swift").write_text(SUPPORT + method + "\n}\n" + HARNESS)
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5", "-import-objc-header", str(folder / "bridge.h"),
            str(root / "iina/FileGroup.swift"), str(folder / "main.swift"), str(folder / "ObjcUtils.o"),
            "-o", str(folder / "probe"),
        ], check=True, timeout=60)
        subprocess.run([str(folder / "probe")], check=True, timeout=15)


if __name__ == "__main__":
    main()
