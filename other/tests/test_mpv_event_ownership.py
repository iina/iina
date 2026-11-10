#!/usr/bin/env python3
"""Exercise the production property-event dispatch with libmpv's C types.

Run with Python 3 and Xcode installed. --source-root can point to an unpatched
checkout to verify that the regression check detects the original bug.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.source_root.resolve()
    source = (root / "iina/MPVController.swift").read_text()
    start = source.index("  private func handlePropertyChange(")
    end = source.index("  // MARK: - User Options", start)
    body = source[start:end]
    # Isolate the production dispatch tail from the unrelated player/UI cases.
    markers = ["    // mpv invalidates property.data", "    // This code is running"]
    tail = body[min(body.index(marker) for marker in markers if marker in body):]
    harness = """
import Foundation
import JavaScriptCore

final class Player {
  let events = EventController()
}

final class Controller {
  let player = Player()
  func handlePropertyChange(_ name: String, _ property: mpv_event_property) {
""" + tail + "\n}\n" + r'''

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}

final class Listener: EventCallable {
  var values: [Any] = []
  func call(withArguments args: [Any]) {
    check(Thread.isMainThread, "callback must run on the main thread")
    check(args.count == 1, "one callback argument")
    values.append(args[0])
  }
}

func drain(_ listener: Listener, count: Int) {
  let deadline = Date(timeIntervalSinceNow: 3)
  while listener.values.count < count && Date() < deadline {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
  }
  check(listener.values.count == count, "callback delivery count")
}

let controller = Controller()
let listener = Listener()
let eventName = EventController.Name("mpv.probe.changed")
_ = controller.player.events.addListener(listener, for: eventName)

func send<T>(_ original: T, replacingWith replacement: T, format: mpv_format) -> Any {
  let count = listener.values.count + 1
  var value = original
  withUnsafeMutablePointer(to: &value) { pointer in
    controller.handlePropertyChange("probe", mpv_event_property(
      name: nil, format: format, data: UnsafeMutableRawPointer(pointer)))
    check(listener.values.count == count - 1, "delivery must remain asynchronous")
    pointer.pointee = replacement
    drain(listener, count: count)
  }
  return listener.values.last!
}

check(send(Int64(42), replacingWith: 99, format: MPV_FORMAT_INT64) as? Int64 == 42,
      "integer must survive reuse of native storage")
check(send(1.25, replacingWith: 9.5, format: MPV_FORMAT_DOUBLE) as? Double == 1.25,
      "double must survive reuse of native storage")
check(send(Int32(0x100), replacingWith: 0, format: MPV_FORMAT_FLAG) as? Bool == true,
      "flags use the full C int, including noncanonical true values")
check(send(Int32(0), replacingWith: 1, format: MPV_FORMAT_FLAG) as? Bool == false,
      "false flags are copied")

for text in ["", "IINA – 日本語", String(repeating: "owned", count: 1000)] {
  let native = strdup(text)!
  var string: UnsafePointer<CChar>? = UnsafePointer(native)
  withUnsafeMutablePointer(to: &string) { pointer in
    controller.handlePropertyChange("probe", mpv_event_property(
      name: nil, format: MPV_FORMAT_STRING, data: UnsafeMutableRawPointer(pointer)))
  }
  free(native)
  string = nil
  drain(listener, count: listener.values.count + 1)
  check(listener.values.last as? String == text, "string must outlive native storage")
}

for format in [MPV_FORMAT_NONE, MPV_FORMAT_FLAG, MPV_FORMAT_INT64,
               MPV_FORMAT_DOUBLE, MPV_FORMAT_STRING] {
  controller.handlePropertyChange("probe", mpv_event_property(name: nil, format: format, data: nil))
  drain(listener, count: listener.values.count + 1)
  check(listener.values.last is NSNull, "unavailable data becomes null")
}
var nullString: UnsafePointer<CChar>? = nil
withUnsafeMutablePointer(to: &nullString) { pointer in
  controller.handlePropertyChange("probe", mpv_event_property(
    name: nil, format: MPV_FORMAT_STRING, data: UnsafeMutableRawPointer(pointer)))
}
drain(listener, count: listener.values.count + 1)
check(listener.values.last is NSNull, "a null string becomes null")

let offset = listener.values.count
let reader = DispatchQueue(label: "mpv-event-test-reader")
reader.sync {
  var number = 0.0
  withUnsafeMutablePointer(to: &number) { pointer in
    for value in 0..<1000 {
      pointer.pointee = Double(value)
      controller.handlePropertyChange("probe", mpv_event_property(
        name: nil, format: MPV_FORMAT_DOUBLE, data: UnsafeMutableRawPointer(pointer)))
    }
  }
}
drain(listener, count: offset + 1000)
for index in 0..<1000 {
  check(listener.values[offset + index] as? Double == Double(index), "queued values retain order and contents")
}

let context = JSContext()!
check(JSValue(object: listener.values[2], in: context)!.isBoolean, "flags bridge as JavaScript booleans")
check(JSValue(object: listener.values[4], in: context)!.isString, "strings bridge as JavaScript strings")
check(JSValue(object: NSNull(), in: context)!.isNull, "unavailable values bridge as JavaScript null")
print("PASS: owned numeric/string payloads, C flags, nulls, main-thread dispatch, 1000 queued events and JS bridging")
'''
    with tempfile.TemporaryDirectory(prefix="iina-mpv-event-test-") as folder:
        folder = Path(folder)
        (folder / "main.swift").write_text(harness)
        subprocess.run([
            "xcrun", "swiftc", "-swift-version", "5", "-import-objc-header",
            str(root / "deps/include/mpv/client.h"), str(root / "iina/EventController.swift"),
            str(folder / "main.swift"), "-o", str(folder / "probe"),
        ], check=True, timeout=60)
        subprocess.run([str(folder / "probe")], check=True, timeout=15)


if __name__ == "__main__":
    main()
