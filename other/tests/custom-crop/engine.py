"""Check exact crop color and precision with the bundled libmpv and FFmpeg."""
import array
import ctypes as C
import json
import subprocess
import sys
import time
from pathlib import Path

out = Path(sys.argv[1]).resolve()
lib = C.CDLL(str(Path(sys.argv[2]).resolve()))
crop = json.loads((out / "filters.json").read_text())["filter"]

class Event(C.Structure):
    _fields_ = [("event_id", C.c_int), ("error", C.c_int),
                ("reply_userdata", C.c_ulonglong), ("data", C.c_void_p)]

lib.mpv_create.restype = C.c_void_p
for name, args, result in [
    ("mpv_set_option_string", [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ("mpv_initialize", [C.c_void_p], C.c_int),
    ("mpv_command", [C.c_void_p, C.POINTER(C.c_char_p)], C.c_int),
    ("mpv_wait_event", [C.c_void_p, C.c_double], C.POINTER(Event)),
    ("mpv_terminate_destroy", [C.c_void_p], None),
]:
    function = getattr(lib, name)
    function.argtypes, function.restype = args, result

raw = out / "color.rgb"
raw.write_bytes(bytes([180, 60, 30]) * 64 * 48)
fixture = out / "color.mkv"
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pixel_format", "rgb24",
                "-video_size", "64x48", "-framerate", "1", "-i", str(raw),
                "-c:v", "ffv1", "-pix_fmt", "yuv420p", str(fixture)], check=True)

results = []
for fmt in ["nv12", "p010le", "p016le", "yuv420p", "yuv420p10le", "gbrp"]:
    for protected in ([False, True] if fmt == "nv12" else [True]):
        name = fmt + ("-protected" if protected else "-unsafe-control")
        folder = out / name
        folder.mkdir(exist_ok=True)
        for old in folder.glob("*.png"):
            old.unlink()
        player = lib.mpv_create()
        assert player
        try:
            for key, value in {"config": "no", "terminal": "no", "audio": "no", "vo": "image",
                               "vo-image-format": "png", "vo-image-outdir": str(folder),
                               "untimed": "yes", "frames": "1", "keep-open": "yes"}.items():
                assert lib.mpv_set_option_string(player, key.encode(), value.encode()) >= 0
            assert lib.mpv_initialize(player) >= 0
            def command(*args):
                values = (C.c_char_p * (len(args) + 1))(*[str(a).encode() for a in args], None)
                assert lib.mpv_command(player, values) >= 0, args
            command("vf", "add", "@input_format:lavfi=[format=" + fmt + "]")
            command("vf", "add", "@iina_crop:" + (crop if protected else "crop=31:21:5:7:exact=1"))
            command("loadfile", fixture)
            deadline = time.monotonic() + 10
            while not list(folder.glob("*.png")):
                event = lib.mpv_wait_event(player, .05).contents
                assert event.event_id != 7 or event.error >= 0, (name, event.error)
                assert time.monotonic() < deadline, name
            image = next(folder.glob("*.png"))
            pixels = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(image),
                "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
            assert len(pixels) == 31 * 21 * 3, (name, len(pixels))
            actual = tuple(pixels[(10 * 31 + 15) * 3:(10 * 31 + 15) * 3 + 3])
            error = max(abs(a - b) for a, b in zip(actual, (180, 60, 30)))
            assert (error <= 5) if protected else (error > 50), (name, actual)
            results.append({"case": name, "pixel": actual, "maximum_channel_error": error})
            print("PASS", name, actual, flush=True)
        finally:
            lib.mpv_terminate_destroy(player)

planes = [10000 + x + y * 64 for y in range(48) for x in range(64)] + [32768] * (64 * 48 * 2)
ramp = out / "precision.yuv"
ramp.write_bytes(array.array("H", planes).tobytes())
graph = crop.split("[", 1)[1][:-1]
rendered = subprocess.check_output(["ffmpeg", "-v", "error", "-f", "rawvideo",
    "-pixel_format", "yuv444p16le", "-video_size", "64x48", "-framerate", "1",
    "-color_primaries", "bt2020", "-color_trc", "smpte2084", "-colorspace", "bt2020nc",
    "-i", str(ramp), "-vf", graph, "-frames:v", "1", "-f", "rawvideo",
    "-pix_fmt", "yuv444p16le", "-"])
values = array.array("H"); values.frombytes(rendered)
expected = [10000 + x + y * 64 for y in range(7, 28) for x in range(5, 36)]
assert list(values[:31 * 21]) == expected
print("PASS odd source coordinates and adjacent 16-bit HDR-tagged luma values remain exact", flush=True)
alpha = out / "alpha.gbrap16"
alpha.write_bytes(array.array("H", [value for value in [10000, 20000, 30000, 12345] for _ in range(64 * 48)]).tobytes())
rendered = subprocess.check_output(["ffmpeg", "-v", "error", "-f", "rawvideo", "-pixel_format", "gbrap16le",
    "-video_size", "64x48", "-framerate", "1", "-i", str(alpha), "-vf", graph,
    "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "gbrap16le", "-"])
values = array.array("H"); values.frombytes(rendered)
assert list(values) == [value for value in [10000, 20000, 30000, 12345] for _ in range(31 * 21)]
print("PASS exact crop retains all 16-bit RGB and alpha components", flush=True)
(out / "engine-results.json").write_text(json.dumps(results, indent=2) + "\n")
