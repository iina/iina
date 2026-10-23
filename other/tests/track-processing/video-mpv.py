"""Optional exact bundled-libmpv rendering probe, after video-run.sh.

Usage: python3 video-mpv.py OUTPUT /Applications/LYINA.app/Contents/Frameworks/libmpv.2.dylib
No window or audio output device is opened.
"""
import ctypes as C
import json
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
library = Path(sys.argv[2]).resolve()
fixture = root / "tracks.mkv"
args = ["ffmpeg", "-v", "error", "-y"]
for source in ["front.rgba", "back.rgba"]:
    args += ["-stream_loop", "1", "-f", "rawvideo", "-pixel_format", "rgba",
             "-video_size", "64x48", "-framerate", "1", "-i", str(root / source)]
subprocess.run(args + ["-map", "0:v", "-map", "1:v", "-c:v", "ffv1", "-pix_fmt", "bgra", str(fixture)], check=True)
m = C.CDLL(str(library))
class Event(C.Structure):
    _fields_ = [("event_id", C.c_int), ("error", C.c_int), ("reply_userdata", C.c_ulonglong), ("data", C.c_void_p)]
m.mpv_create.restype = C.c_void_p
for name, args, result in [
    ("mpv_set_option_string", [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ("mpv_initialize", [C.c_void_p], C.c_int),
    ("mpv_command", [C.c_void_p, C.POINTER(C.c_char_p)], C.c_int),
    ("mpv_wait_event", [C.c_void_p, C.c_double], C.POINTER(Event)),
    ("mpv_terminate_destroy", [C.c_void_p], None),
    ("mpv_get_property_string", [C.c_void_p, C.c_char_p], C.c_void_p),
    ("mpv_free", [C.c_void_p], None),
]:
    function = getattr(m, name); function.argtypes = args; function.restype = result

checks = 0
for case in json.loads((root / "graphs.json").read_text()):
    if len(case["ids"]) < 2:
        continue
    folder = root / ("mpv-" + case["name"])
    folder.mkdir(exist_ok=True)
    for previous in folder.glob("*.png"):
        previous.unlink()
    p = m.mpv_create()
    assert p
    options = {"config": "no", "terminal": "no", "audio": "no",
               "vo": "image", "vo-image-format": "png", "vo-image-outdir": str(folder),
               "untimed": "yes", "length": "1", "lavfi-complex": case["graph"]}
    try:
        for key, value in options.items():
            assert m.mpv_set_option_string(p, key.encode(), value.encode()) >= 0, key
        assert m.mpv_initialize(p) >= 0
        command = (C.c_char_p * 3)(b"loadfile", str(fixture).encode(), None)
        assert m.mpv_command(p, command) >= 0
        end = time.monotonic() + 20
        while time.monotonic() < end:
            event = m.mpv_wait_event(p, .1).contents
            if event.event_id == 7:
                assert event.error >= 0, (case["name"], event.error)
                break
        else:
            raise AssertionError(("mpv timeout", case["name"]))
    finally:
        m.mpv_terminate_destroy(p)
    frame = next(folder.glob("*.png"))
    actual = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(frame), "-frames:v", "1",
                                      "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
    expected = (root / (case["name"] + ".rgba")).read_bytes()
    assert len(actual) == 64 * 48 * 3
    for x, y in [(0, 24), (10, 10), (32, 24), (50, 30)]:
        a = actual[(y * 64 + x) * 3:(y * 64 + x) * 3 + 3]
        e = expected[(y * 64 + x) * 4:(y * 64 + x) * 4 + 3]
        assert all(abs(v - w) <= 3 for v, w in zip(a, e)), (case["name"], x, y, tuple(a), tuple(e))
    checks += 1
    print("PASS exact libmpv rendered pixels:", case["name"])
assert checks == 4, checks
print("PASS exact libmpv decoded FFV1 alpha, applied track processing and composited all 4 graph cases")

# Keep the source open so the exact engine's negotiated format and HDR metadata
# can be queried while the decoded frame is still live.
high_fixture = root / "high-depth.mkv"
subprocess.run(["ffmpeg", "-v", "error", "-y", "-stream_loop", "1", "-f", "rawvideo",
    "-pixel_format", "yuv444p16le", "-video_size", "64x48", "-framerate", "1",
    "-color_primaries", "bt2020", "-color_trc", "smpte2084", "-colorspace", "bt2020nc",
    "-i", str(root / "high-depth.yuv"), "-c:v", "ffv1", str(high_fixture)], check=True)
folder = root / "mpv-high-depth"; folder.mkdir(exist_ok=True)
for previous in folder.glob("*.png"):
    previous.unlink()
case = next(c for c in json.loads((root / "graphs.json").read_text()) if c["name"] == "geometry-high-depth")
p = m.mpv_create()
def get(key):
    pointer = m.mpv_get_property_string(p, key.encode())
    if not pointer:
        return None
    result = C.string_at(pointer).decode(); m.mpv_free(pointer); return result
try:
    for key, value in {"config": "no", "terminal": "no", "audio": "no", "vo": "image",
        "vo-image-format": "png", "vo-image-high-bit-depth": "yes", "vo-image-outdir": str(folder),
        "untimed": "yes", "length": "1", "keep-open": "yes", "lavfi-complex": case["graph"]}.items():
        assert m.mpv_set_option_string(p, key.encode(), value.encode()) >= 0, key
    assert m.mpv_initialize(p) >= 0
    command = (C.c_char_p * 3)(b"loadfile", str(high_fixture).encode(), None)
    assert m.mpv_command(p, command) >= 0
    end = time.monotonic() + 20
    while time.monotonic() < end:
        m.mpv_wait_event(p, .05)
        if list(folder.glob("*.png")):
            break
    else:
        raise AssertionError("high-bit-depth libmpv timeout")
    params = json.loads(get("video-out-params"))
    (folder / "video-out-params.json").write_text(json.dumps(params, indent=2))
    assert "16" in params["pixelformat"], params
    assert params["gamma"] == "pq" and params["primaries"] == "bt.2020", params
finally:
    m.mpv_terminate_destroy(p)
frame = next(folder.glob("*.png"))
image_params = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(frame)]))
assert image_params["streams"][0]["pix_fmt"] in ("rgb48be", "rgba64be"), image_params
print("PASS exact libmpv single-track geometry retains 16-bit output, BT.2020/PQ metadata and a 16-bit PNG")
