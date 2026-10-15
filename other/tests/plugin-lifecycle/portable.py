#!/usr/bin/env python3
"""Build and run the portable plugin lifecycle regression suite."""

import argparse
import base64
import http.server
import io
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import socket
import subprocess
import tarfile
import threading
import time
import uuid


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PRODUCTION_FILES = [
    "iina/AppDelegate.swift",
    "iina/JavascriptAPI.swift",
    "iina/JavascriptAPIEvent.swift",
    "iina/JavascriptAPIHttp.swift",
    "iina/JavascriptAPIMpv.swift",
    "iina/JavascriptAPIOverlay.swift",
    "iina/JavascriptAPIUtils.swift",
    "iina/JavascriptAPIWebSocket.swift",
    "iina/JavascriptMessageHub.swift",
    "iina/JavascriptPlugin.swift",
    "iina/JavascriptPluginInstance.swift",
    "iina/JavascriptPolyfill.swift",
    "iina/JustXMLRPC.swift",
    "iina/MPVController.swift",
    "iina/PlayerCore.swift",
    "iina/WebSocketServer.swift",
]
TEST_VIDEO = """AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAAIZnJlZQAAAyttZGF0AAACrQYF//+p3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NSByMzIyMiBiMzU2MDVhIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNSAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDExMyBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MSBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRzPTYgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0zIGJfcHlyYW1pZD0yIGJfYWRhcHQ9MSBiX2JpYXM9MCBkaXJlY3Q9MSB3ZWlnaHRiPTEgb3Blbl9nb3A9MCB3ZWlnaHRwPTIga2V5aW50PTI1MCBrZXlpbnRfbWluPTIgc2NlbmVjdXQ9NDAgaW50cmFfcmVmcmVzaD0wIHJjX2xvb2thaGVhZD00MCByYz1jcmYgbWJ0cmVlPTEgY3JmPTIzLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MToxLjAwAIAAAABBZYiEABX//uzPfgU3IDyL9ZQIdLVudeOY06aGeK6v9N6hcRjDjyW4ADcS20LxOJaF3F/wElAAAHgEJji2UyWbxpcAAAANQZojbEEv/rUqgABCwAAAAApBnkF4gn8AABZxAAAACgGeYmpBLwAAIOAAAANjbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAB9AAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAo50cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAB9AAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAUAAAAC0AAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAfQAABAAAABAAAAAAIGbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAgABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABsW1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAXFzdGJsAAAAwXN0c2QAAAAAAAAAAQAAALFhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAUAAtABIAAAASAAAAAAAAAABFExhdmM2My4xLjEwMSBsaWJ4MjY0AAAAAAAAAAAAAAAAGP//AAAAN2F2Y0MBZAAM/+EAGmdkAAys2UFBn58BEAAAAwAQAAADAEDxQplgAQAGaOvjyyLA/fj4AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAAAyMAAAAAAAAABhzdHRzAAAAAAAAAAEAAAAEAAAgAAAAABRzdHNzAAAAAAAAAAEAAAABAAAAKGN0dHMAAAAAAAAAAwAAAAEAAEAAAAAAAQAAgAAAAAACAAAgAAAAABxzdHNjAAAAAAAAAAEAAAABAAAABAAAAAEAAAAkc3RzegAAAAAAAAAAAAAABAAAAvYAAAARAAAADgAAAA4AAAAUc3RjbwAAAAAAAAABAAAAMAAAAGF1ZHRhAAAAWW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALGlsc3QAAAAkqXRvbwAAABxkYXRhAAAAAQAAAABMYXZmNjMuMS4xMDE="""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/held":
            time.sleep(0.18)
        if self.path == "/error":
            status, body, content_type = 503, b'{"error":"download-failed"}', "application/json"
        else:
            size = 8 * 1024 * 1024 if self.path == "/body" else 20
            status, body, content_type = 200, b"x" * size, "application/octet-stream"
        try:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dependencies-from", type=Path)
    parser.add_argument("--cloned-packages", type=Path)
    parser.add_argument("--package-cache", type=Path)
    return parser.parse_args()


def copy_checkout(source):
    archive = subprocess.check_output(["git", "archive", "HEAD"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(source, filter="data")
    for name in PRODUCTION_FILES:
        destination = source / name
        destination.write_bytes((ROOT / name).read_bytes())


def prepare_source(source, run):
    app_delegate = source / "iina/AppDelegate.swift"
    text = app_delegate.read_text()
    assert "@NSApplicationMain\n" in text
    app_delegate.write_text(
        text.replace("@NSApplicationMain\n", "", 1)
        + "\n"
        + (HERE / "PortableDriver.swift").read_text()
        + "\n"
        + (HERE / "ReviewTests.swift").read_text()
        + "\n"
        + (HERE / "FileReviewTests.swift").read_text()
    )

    utility = source / "iina/Utility.swift"
    old = "static let tempDirURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)"
    text = utility.read_text()
    assert old in text
    utility.write_text(text.replace(
        old,
        'static let tempDirURL: URL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["IINA_LIFECYCLE_TEST_ROOT"]! + "/tmp", isDirectory: true)',
        1,
    ))

    http = source / "iina/JavascriptAPIHttp.swift"
    text = http.read_text()
    assert text.count("        offset += count") == 1
    assert text.count("          offset += written") == 1
    text = text.replace("        offset += count", "        offset += count\n        LifecycleDownloadProbe.afterChunk()", 1)
    text = text.replace("          offset += written", "          offset += written\n          LifecyclePublicationProbe.afterBlock()", 1)
    http.write_text(text)

    mpv = source / "iina/MPVController.swift"
    mpv.write_text(mpv.read_text() + """

extension MPVController {
  func lifecycleInvokeHook(_ identifier: String, next: @escaping () -> Void) {
    let hook = $hooks.withLock { $0.values.first { $0.id == identifier } }
    precondition(hook != nil)
    hook!.call(withNextBlock: next)
  }

  func lifecycleHookCount(_ identifier: String) -> Int {
    $hooks.withLock { $0.values.filter { $0.id == identifier }.count }
  }
}
""")

    info = source / "iina/Info.plist"
    data = plistlib.loads(info.read_bytes())
    for key in ("CFBundleDocumentTypes", "CFBundleURLTypes", "NSServices", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations"):
        data.pop(key, None)
    data.update(SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
    info.write_bytes(plistlib.dumps(data))

    plugins = run / "home/Library/Application Support/org.iina.lifecycle-tests/plugins"
    plugins.mkdir(parents=True)
    for folder, identifier, name in (
        ("lifecycle.iinaplugin", "org.iina.lifecycle-test", "Plugin Lifecycle Test"),
        ("witness.iinaplugin", "org.iina.lifecycle-witness", "Plugin Lifecycle Witness"),
    ):
        destination = plugins / folder
        shutil.copytree(HERE / "portable-fixture", destination)
        manifest = json.loads((destination / "Info.json").read_text())
        manifest.update(identifier=identifier, name=name)
        (destination / "Info.json").write_text(json.dumps(manifest, indent=2) + "\n")


def prepare_dependencies(source, supplied):
    if supplied is None and (ROOT / "deps/lib").is_dir():
        supplied = ROOT / "deps"
    if supplied is not None:
        supplied = supplied.resolve()
        if not (supplied / "lib/libmpv.2.dylib").exists():
            raise SystemExit(f"Missing libmpv in dependency directory: {supplied}")
        generated = source / "deps"
        shutil.rmtree(generated)
        generated.symlink_to(supplied, target_is_directory=True)
        return
    subprocess.run([
        str(source / "other/download_libs.sh"), "--arch", platform.machine(),
        "--parallel", "3", "--skip-plugins",
    ], cwd=source, check=True)


def build(source, run, args):
    derived = run / "DerivedData"
    cloned = args.cloned_packages.resolve() if args.cloned_packages else run / "SourcePackages"
    cache = args.package_cache.resolve() if args.package_cache else run / "PackageCache"
    command = [
        "xcodebuild", "-project", str(source / "iina.xcodeproj"), "-scheme", "iina",
        "-configuration", "Debug", "-derivedDataPath", str(derived),
        "-clonedSourcePackagesDirPath", str(cloned), "-packageCachePath", str(cache),
        "-jobs", "3", "CODE_SIGNING_ALLOWED=NO",
        "PRODUCT_BUNDLE_IDENTIFIER=org.iina.lifecycle-tests", "build",
    ]
    with (run / "build.log").open("w") as log:
        result = subprocess.run(command, cwd=source, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        raise SystemExit(f"Build failed; see {run / 'build.log'}")
    app = derived / "Build/Products/Debug/IINA.app"
    shutil.rmtree(app / "Contents/PlugIns/OpenInIINA.appex", ignore_errors=True)
    for plugin in (app / "Contents/Resources/plugins").glob("*.iinaplgz"):
        plugin.unlink()
    sparkle = app / "Contents/Frameworks/Sparkle.framework"
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(sparkle)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", "--identifier", "org.iina.lifecycle-tests", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    return app


def sandbox_profile(run, executable, helper, http_port, ws_port):
    profile = """(version 1)
(allow default)
(deny network*)
(deny signal)
(deny file-write*)
"""
    profile += f'(allow file-write* (subpath "{run}") (literal "/dev/null"))\n'
    profile += f'(allow network-outbound (remote ip "localhost:{http_port}"))\n'
    profile += f'(allow network-bind network-inbound (local ip "*:{ws_port}"))\n'
    profile += '(allow signal (target children))\n(deny process-exec)\n'
    profile += f'(allow process-exec (literal "{executable}") (literal "{helper}") (literal "/usr/bin/true"))\n'
    path = run / "isolation.sb"
    path.write_text(profile)
    return path


def process_group_exists(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False


def run_mode(mode, app, run, profile, server_port, ws_port):
    case = run / mode
    case.mkdir()
    executable = app / "Contents/MacOS/IINA"
    environment = os.environ.copy()
    environment.update(
        CFFIXED_USER_HOME=str(run / "home"),
        TMPDIR=str(run / "tmp") + "/",
        IINA_LIFECYCLE_TEST_ROOT=str(run),
        IINA_LIFECYCLE_LAB=str(run),
        IINA_LIFECYCLE_REVIEW_RUN=str(case),
        IINA_LIFECYCLE_HTTP_URL=f"http://127.0.0.1:{server_port}",
        IINA_LIFECYCLE_WS_PORT=str(ws_port),
    )
    with (case / "test.log").open("w") as log:
        process = subprocess.Popen(
            ["/usr/bin/sandbox-exec", "-f", str(profile), str(executable), mode],
            cwd=run, env=environment, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            result = process.wait(timeout=45)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            raise AssertionError(f"{mode} timed out")
    remaining_group = process_group_exists(process.pid)
    if remaining_group:
        os.killpg(process.pid, signal.SIGKILL)
    assert result == 0, (case / "test.log").read_text()[-5000:]
    assert not remaining_group, f"{mode} left a test process behind"
    if mode == "file-exit":
        record = json.loads((case / "exit-check.json").read_text())
        assert record["writerPaused"] and record["stagingPaths"]
        assert not Path(record["target"]).exists()
        assert all(not Path(path).exists() for path in record["stagingPaths"])
    print(f"PASS {mode}")


def main():
    args = parse_args()
    run = ROOT / "build/plugin-lifecycle-tests" / (time.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8])
    source = run / "source"
    source.mkdir(parents=True)
    (run / "home").mkdir()
    (run / "tmp").mkdir()
    print(f"Plugin lifecycle test run: {run}", flush=True)
    copy_checkout(source)
    prepare_source(source, run)
    prepare_dependencies(source, args.dependencies_from)
    helper = run / "exec-probe"
    subprocess.run(["clang", str(HERE / "exec-probe.c"), "-o", str(helper)], check=True)
    (run / "lifecycle-test.mp4").write_bytes(base64.b64decode(TEST_VIDEO))
    app = build(source, run, args)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    with socket.socket() as temporary:
        temporary.bind(("127.0.0.1", 0))
        ws_port = temporary.getsockname()[1]
    profile = sandbox_profile(run, app / "Contents/MacOS/IINA", helper, server.server_port, ws_port)
    try:
        for mode in ("lifecycle", "files", "file-exit"):
            run_mode(mode, app, run, profile, server.server_port, ws_port)
    finally:
        server.shutdown()
        server.server_close()
    with socket.socket() as check:
        check.bind(("127.0.0.1", ws_port))
    result = {
        "modes": ["lifecycle", "files", "file-exit"],
        "productionFiles": PRODUCTION_FILES,
        "installedApplicationUsed": False,
        "testProcessesRemaining": False,
        "webSocketPortReleased": True,
    }
    (run / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"PASS portable plugin lifecycle suite: {run}")


if __name__ == "__main__":
    main()
