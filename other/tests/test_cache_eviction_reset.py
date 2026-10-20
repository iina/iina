#!/usr/bin/env python3
"""Run CacheManager against disposable directories, without application state."""

import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.source_root.resolve()
    harness = r'''
import Cocoa

enum Utility {
  static var thumbnailCacheURL = URL(fileURLWithPath: CommandLine.arguments[1])
}
enum Preference {
  enum Key { case maxThumbnailPreviewCacheSize }
  static var limit = 1
  static func integer(for key: Key) -> Int { limit }
}
enum FloatingPointByteCountFormatter {
  enum PrefixFactor: Int { case mi = 1048576 }
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}

let manager = CacheManager()
let files = FileManager.default
let cache = Utility.thumbnailCacheURL

// Directory enumeration fails; a later cleanup must still be allowed.
manager.clearOldCache()
check(!manager.isJobRunning, "enumeration failure must reset the running flag")
try files.createDirectory(at: cache, withIntermediateDirectories: true)
for index in 0..<4 {
  try Data(repeating: UInt8(index), count: 262144).write(to: cache.appendingPathComponent("\(index)"))
}
check(manager.getCacheSize() == 1048576, "fixture size")
manager.clearOldCache()
check(!manager.isJobRunning, "successful cleanup must reset the running flag")
check(manager.getCacheSize() == 524288, "first cleanup removes half the configured maximum")
manager.clearOldCache()
check(manager.getCacheSize() == 0, "a second cleanup must run in the same session")
check(!manager.isJobRunning, "second cleanup must reset the running flag")

manager.clearOldCache()
check(!manager.isJobRunning, "an empty directory must reset the running flag")
Preference.limit = 0
manager.clearOldCache()
check(!manager.isJobRunning, "a zero budget must reset the running flag")

// The existing guard must not clear another job's state.
manager.isJobRunning = true
manager.clearOldCache()
check(manager.isJobRunning, "an already-running job retains ownership of its flag")
manager.isJobRunning = false
print("PASS: failed enumeration, repeated eviction, half-budget pruning, empty directory, zero budget and running-job guard")
'''
    with tempfile.TemporaryDirectory(prefix="iina-cache-eviction-test-") as folder:
        folder = Path(folder)
        (folder / "main.swift").write_text(harness)
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5", str(root / "iina/CacheManager.swift"),
            str(folder / "main.swift"), "-o", str(folder / "probe"),
        ], check=True, timeout=60)
        subprocess.run([str(folder / "probe"), str(folder / "cache")], check=True, timeout=15)


if __name__ == "__main__":
    main()
