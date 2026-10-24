"""Render the production LUT graphs through the bundled libmpv; no UI/audio."""
import ctypes as C
import json
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
lib = C.CDLL(str(Path(sys.argv[2]).resolve()))

class Event(C.Structure):
    _fields_ = [("event_id", C.c_int), ("error", C.c_int),
                ("reply_userdata", C.c_ulonglong), ("data", C.c_void_p)]

lib.mpv_create.restype = C.c_void_p
for name, arguments, result in [
    ("mpv_set_option_string", [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ("mpv_initialize", [C.c_void_p], C.c_int),
    ("mpv_command", [C.c_void_p, C.POINTER(C.c_char_p)], C.c_int),
    ("mpv_wait_event", [C.c_void_p, C.c_double], C.POINTER(Event)),
    ("mpv_get_property_string", [C.c_void_p, C.c_char_p], C.c_void_p),
    ("mpv_free", [C.c_void_p], None),
    ("mpv_terminate_destroy", [C.c_void_p], None),
]:
    function = getattr(lib, name)
    function.argtypes, function.restype = arguments, result

raw = root / "source.rgb"
raw.write_bytes(bytes([64, 96, 128]) * 64 * 48)
fixture = root / "source.mkv"
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pixel_format", "rgb24",
                "-video_size", "64x48", "-framerate", "1", "-i", str(raw),
                "-c:v", "ffv1", "-pix_fmt", "gbrp", str(fixture)], check=True)
cases = json.loads((root / "graphs.json").read_text())
identity, inverse, track = cases

def vf(graph):
    return "@lyina_lut:lavfi=graph=%{}%{}".format(len(graph.encode()), graph)

results = []
for case in [{"name": "baseline"}, *cases]:
    folder = root / case["name"]
    folder.mkdir(exist_ok=True)
    for previous in folder.glob("*.png"):
        previous.unlink()
    player = lib.mpv_create()
    assert player
    def command(*args):
        values = (C.c_char_p * (len(args) + 1))(*[str(a).encode() for a in args], None)
        result = lib.mpv_command(player, values)
        assert result >= 0, (args, result)
    def get(key):
        pointer = lib.mpv_get_property_string(player, key.encode())
        if not pointer:
            return ""
        text = C.string_at(pointer).decode()
        lib.mpv_free(pointer)
        return text
    try:
        options = {"config": "no", "terminal": "no", "audio": "no", "vo": "image",
                   "vo-image-format": "png", "vo-image-outdir": str(folder),
                   "untimed": "yes", "frames": "1", "keep-open": "yes"}
        if case["name"] == "track-inverse":
            options["lavfi-complex"] = case["graph"]
        for key, value in options.items():
            assert lib.mpv_set_option_string(player, key.encode(), value.encode()) >= 0, key
        assert lib.mpv_initialize(player) >= 0
        # A labeled replacement must not accumulate LUTs or touch other filters.
        command("vf", "add", "@unrelated:hflip")
        command("vf", "add", vf(identity["graph"]))
        command("vf", "add", vf(inverse["graph"]))
        filters = get("vf")
        assert filters.count("@lyina_lut") == 1 and "@unrelated" in filters, filters
        command("vf", "remove", "@lyina_lut")
        assert "lyina_lut" not in get("vf") and "@unrelated" in get("vf")
        if case["name"] in ("identity", "inverse"):
            command("vf", "add", vf(case["graph"]))
        command("loadfile", fixture)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            event = lib.mpv_wait_event(player, .05).contents
            if list(folder.glob("*.png")):
                break
            if event.event_id == 7:
                assert event.error >= 0, (case["name"], event.error)
        else:
            raise AssertionError(("render timed out", case["name"]))
        frame = next(folder.glob("*.png"))
        pixels = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(frame),
                                         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
        actual = tuple(pixels[(24 * 64 + 32) * 3:(24 * 64 + 32) * 3 + 3])
        expected = (191, 159, 127) if "inverse" in case["name"] else (64, 96, 128)
        assert len(actual) == 3 and all(abs(a-b) <= 3 for a, b in zip(actual, expected)), (case, actual, expected)
        results.append({"case": case["name"], "pixel": actual, "expected": expected})
        print("PASS bundled engine:", case["name"], actual)
    finally:
        lib.mpv_terminate_destroy(player)
(root / "engine-results.json").write_text(json.dumps(results, indent=2) + "\n")
print("PASS replacement, removal, unrelated filters, special filenames and all four rendered frames")
