#!/usr/bin/env python3
"""Compile the production Process helper and exercise disposable child processes."""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


HARNESS = r'''
import Foundation

func bytes(_ value: Data) -> Data { value }
// Keep the baseline runnable, so failure is a deadlock rather than an API mismatch.
func bytes(_ value: Pipe) -> Data { value.fileHandleForReading.readDataToEndOfFile() }
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let python = CommandLine.arguments[1]
let child = CommandLine.arguments[2]
let directory = URL(fileURLWithPath: CommandLine.arguments[3]).resolvingSymlinksInPath()
for mode in ["both", "stdout", "stderr", "empty", "failure", "arguments"] {
  let (process, output, errors) = Process.run([python, child, mode, "a b", "字幕"], at: directory)
  let out = bytes(output)
  let err = bytes(errors)
  check(process.terminationReason == .exit, "normal termination: \(mode)")
  check(process.terminationStatus == (mode == "failure" ? 17 : 0), "exit status: \(mode)")
  if mode == "arguments" {
    let lines = String(data: out, encoding: .utf8)!.components(separatedBy: "\n")
    check(lines.count == 4 && lines[1] == "a b" && lines[2] == "字幕", "arguments")
    // macOS may spell the temporary folder using either /var or /private/var.
    let actualDirectory = try FileManager.default.attributesOfItem(atPath: lines[0])
    let expectedDirectory = try FileManager.default.attributesOfItem(atPath: directory.path)
    for key in [FileAttributeKey.systemNumber, .systemFileNumber] {
      check(actualDirectory[key] as? NSNumber == expectedDirectory[key] as? NSNumber, "working directory")
    }
    check(err.isEmpty, "argument fixture stderr")
  } else {
    let count = 2 * 1024 * 1024
    check(out == ((mode == "both" || mode == "stdout" || mode == "failure") ? Data((0..<count).map { UInt8($0 % 251) }) : Data()), "complete binary stdout: \(mode)")
    check(err == ((mode == "both" || mode == "stderr" || mode == "failure") ? Data((0..<count).map { UInt8(250 - $0 % 251) }) : Data()), "complete binary stderr: \(mode)")
  }
}
let (killed, _, _) = Process.run(["/bin/sh", "-c", "kill -TERM $$"])
check(killed.terminationReason == .uncaughtSignal, "signal termination")
check(killed.terminationStatus == SIGTERM, "signal status")
print("PASS: concurrent binary output, individual streams, empty output, nonzero exit, working directory, Unicode arguments, repeated calls and signal status")
'''

CHILD = r'''
import os
import sys
mode = sys.argv[1]
if mode == "arguments":
    print(os.getcwd())
    print(sys.argv[2])
    print(sys.argv[3])
else:
    # Alternate streams and exceed pipe capacity in each direction.
    out = bytes(i % 251 for i in range(2 * 1024 * 1024))
    err = bytes(250 - i % 251 for i in range(2 * 1024 * 1024))
    for offset in range(0, len(out), 4096):
        if mode in ("both", "stdout", "failure"):
            sys.stdout.buffer.write(out[offset:offset + 4096])
            sys.stdout.buffer.flush()
        if mode in ("both", "stderr", "failure"):
            sys.stderr.buffer.write(err[offset:offset + 4096])
            sys.stderr.buffer.flush()
sys.exit(17 if mode == "failure" else 0)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    source = (args.source_root / "iina/Extensions.swift").read_text()
    start = source.index("extension Process {")
    helper = source[start:source.index("\nextension CGImage {", start)]
    with tempfile.TemporaryDirectory(prefix="iina-pipe-test-") as directory:
        folder = Path(directory)
        (folder / "main.swift").write_text("import Foundation\n" + helper + HARNESS)
        (folder / "child.py").write_text(CHILD)
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(folder / "main.swift"), "-o", str(folder / "probe")], check=True, timeout=60)
        child = subprocess.Popen([str(folder / "probe"), sys.executable, str(folder / "child.py"), str(folder)], start_new_session=True)
        try:
            child.wait(timeout=20)
            if child.returncode:
                raise SystemExit(child.returncode)
        except subprocess.TimeoutExpired:
            raise SystemExit("FAIL: Process.run blocked while the child filled its output pipes")
        finally:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()


if __name__ == "__main__":
    main()
