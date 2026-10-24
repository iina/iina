"""Render production Swift graphs and assert fixed canvas, display fit and alpha.

Requires ffmpeg/ffprobe on PATH. The optional exact libmpv probe is separate.
"""
import json
import array
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
ffmpeg = shutil.which("ffmpeg")
assert ffmpeg, "ffmpeg is required for the video pixel checks"
cases = json.loads((root / "graphs.json").read_text())
w, h = 64, 48
front = bytes(component for y in range(h) for x in range(w)
              for component in ((255, 0, 0, 128) if x < 32 else (0, 255, 0, 128)))
back = bytes((0, 0, 255, 255)) * (w * h)
(root / "front.rgba").write_bytes(front)
(root / "back.rgba").write_bytes(back)
results = {}
for case in cases:
    args = [ffmpeg, "-v", "error", "-filter_complex_threads", "1"]
    for track in case["ids"]:
        args += ["-f", "rawvideo", "-pixel_format", "rgba", "-video_size", "64x48",
                 "-framerate", "1", "-i", str(root / ("front.rgba" if track == 1 else "back.rgba"))]
    graph = case["graph"]
    for index, track in enumerate(case["ids"]):
        graph = graph.replace(f"[vid{track}]", f"[{index}:v]")
    if case["name"] in ("source-sar", "canvas-sar"):
        graph = "[0:v]setsar=2[input];" + graph.replace("[0:v]", "[input]")
    raw = subprocess.check_output(args + ["-filter_complex", graph, "-map", "[vo]",
        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-"])
    assert len(raw) == w * h * 4, (case["name"], len(raw))
    (root / (case["name"] + ".rgba")).write_bytes(raw)
    results[case["name"]] = raw

def pixel(name, x, y):
    raw = results[name]
    return tuple(raw[(y * w + x) * 4:(y * w + x) * 4 + 4])

assert pixel("crop", 0, 24)[3] == 0
assert pixel("crop", 20, 24)[0] > 240 and pixel("crop", 44, 24)[1] > 240
assert abs(pixel("crop", 20, 24)[3] - 128) <= 1
assert pixel("aspect", 32, 0)[3] == 0 and abs(pixel("aspect", 32, 10)[3] - 128) <= 1
assert pixel("rotation", 0, 24)[3] == 0 and pixel("rotation", 32, 2)[0] > 240
assert pixel("rotation", 32, 46)[1] > 240
assert pixel("brightness", 10, 10)[0] > 240 and pixel("brightness", 10, 10)[1] > 20
assert pixel("brightness", 10, 10)[3] == 128
assert pixel("square-front", 0, 24) == (0, 0, 255, 255)
assert pixel("square-front", 32, 24)[2] > 120
assert pixel("square-bottom", 32, 24) == (0, 0, 255, 255)
assert pixel("color-pad", 0, 24) == (0, 0, 255, 255), "color must retain transparent padding"
for x, y in [(10, 10), (50, 30)]:
    solo = pixel("color-alpha-solo", x, y)
    actual = pixel("color-alpha", x, y)
    alpha = solo[3] / 255
    expected = tuple(round(solo[c] * alpha + (255 if c == 2 else 0) * (1 - alpha)) for c in range(3))
    assert solo[3] == 128 and actual[3] == 255
    assert all(abs(a - b) <= 2 for a, b in zip(actual[:3], expected)), (actual, expected)
assert pixel("source-sar", 32, 0)[3] == 0 and abs(pixel("source-sar", 32, 24)[3] - 128) <= 1
assert pixel("canvas-sar", 32, 0)[3] == 128, "source and canvas SAR must cancel when equal"
print(f"PASS {len(cases)} rendered video graphs: crop/aspect/rotation/color, fixed canvas, source/canvas SAR and alpha")

# A 16-bit luma ramp with adjacent code values catches an accidental 8-bit hop.
# Full-frame crop deliberately engages the geometry processing path.
planes = [10000 + x for y in range(h) for x in range(w)] + [32768] * (w * h * 2)
source = array.array("H", planes).tobytes()
(root / "high-depth.yuv").write_bytes(source)
case = next(c for c in cases if c["name"] == "geometry-high-depth")
graph = case["graph"].replace("[vid1]", "[0:v]")
raw = subprocess.check_output([ffmpeg, "-v", "error", "-f", "rawvideo", "-pixel_format", "yuv444p16le",
    "-video_size", "64x48", "-framerate", "1", "-color_primaries", "bt2020", "-color_trc", "smpte2084",
    "-colorspace", "bt2020nc", "-i", str(root / "high-depth.yuv"), "-filter_complex", graph,
    "-map", "[vo]", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "yuva444p16le", "-"])
output = array.array("H"); output.frombytes(raw)
assert list(output[:w * h]) == planes[:w * h], "single geometry must preserve all 16-bit luma code values"
assert set(output[w * h * 3:]) == {65535}, "opaque input must remain opaque"
print("PASS 16-bit HDR-tagged geometry preserves adjacent luma code values without an 8-bit conversion")
