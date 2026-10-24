#!/usr/bin/env python3
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[3]
tests = Path(__file__).resolve().parent
out = Path(os.environ.get("FULLSCREEN_TEST_OUTPUT", root / "build/fullscreen-transition-tests"))
out.mkdir(parents=True, exist_ok=True)
source_root = Path(os.environ.get("FULLSCREEN_TEST_SOURCE", root / "iina"))
main = (source_root / "MainWindowController.swift").read_text()
layer = (source_root / "ViewLayer.swift").read_text()
player = (source_root / "PlayerCore.swift").read_text()


def extract(source, marker):
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("private func", "func")


prefix = extract(layer, "  override func display() {")
prefix = prefix[:prefix.index("    guard isUpdate && needsFlip")] + "    _ = isUpdate\n  }"
render_methods = [prefix, extract(layer, "  private var pixelSize:")]
for name in ["beginFullscreenTransition", "endFullscreenTransition", "scheduleFullscreenDisplay",
             "completeFullscreenTransitionIfReady", "displayForCropHandoff", "setCropFramePreparation", "withCropFrameUpdate", "withCropFrameHandoff"]:
    marker = ("  private func " if name.startswith(("schedule", "complete")) else "  func ") + name + "("
    signature = ("cancelled: Bool = false" if name == "endFullscreenTransition" else
                 "_ updateLayout: () -> Void" if name == "withCropFrameHandoff" else "")
    method = extract(layer, marker) if marker in layer else f"  func {name}({signature}) {{}}"
    if name == "withCropFrameHandoff":
        method = method.replace("CATransaction.", "HandoffTransaction.")
    render_methods.append(method)
render_methods.append(extract(layer, "  func update(force:"))
copies = "\n".join(line for line in layer.splitlines() if any(
    line.strip().startswith("_" + name + " = previousLayer.")
    for name in ["fullscreenTransition", "fullscreenDisplayQueued", "lastRenderedPixelSize", "isAnimatingWindowResize", "isDrawingGeometryHandoff"]))
atomics = (root / "iina/Atomic.swift").read_text()
render = (tests / "Render.swift").read_text().replace("// PRODUCTION_ATOMIC", atomics)
render = render.replace("// PRODUCTION_COPY", copies)
render = render.replace("// PRODUCTION_RENDER", "\n".join(render_methods))

geometry_methods = []
for name in ["beginFullscreenVideoTransition", "finishFullscreenVideoTransition"]:
    marker = "  private func " + name + "("
    geometry_methods.append(extract(main, marker) if marker in main else f"  func {name}() {{}}")
geometry = (tests / "Geometry.swift").read_text().replace("// PRODUCTION_GEOMETRY", "\n".join(geometry_methods))

time_start = player.index("    case .time:", player.index("  func syncUI(_ option:"))
time_end = player.index("      let isNetworkStream", time_start)
time_guard = player[time_start:time_end].replace("    case .time:", "")
time = (tests / "Time.swift").read_text().replace("// PRODUCTION_TIME_GUARD", time_guard)

chrome_methods = []
for name in ["windowWillEnterFullScreen", "windowWillExitFullScreen", "windowDidFailToExitFullScreen"]:
    method = extract(main, "  func " + name + "(")
    end = (method.index("    // When playback") if name.startswith("windowWill")
           else method.index("    titleBarView.update"))
    chrome_methods.append(method[:end] + "  }")
chrome = (tests / "Chrome.swift").read_text().replace("// PRODUCTION_CHROME", "\n".join(chrome_methods))

def property_source(name):
    marker = "  @Atomic var " + name
    start = layer.index(marker)
    line = layer[start:layer.index("\n", start)]
    return extract(layer, marker) if "{" in line else line

scheduling = (tests / "CropScheduling.swift").read_text().replace("// PRODUCTION_ATOMIC", atomics)
scheduling = scheduling.replace("// PRODUCTION_SCHEDULING", "\n".join(property_source(name) for name in
    ["isAnimatingWindowResize", "isInCropTransition", "inLiveResize"]))

deadline_methods = [extract(layer, "  override func canDraw("), extract(layer, "  private var pixelSize:")]
for marker in ["  private func takeCropFrameHandlers(", "  func afterNextCropFrame(",
               "  private func takePreparedCropFrameHandlers(", "  func cancelCropFrameRequests(",
               "  private func deferCropDisplay(until"]:
    deadline_methods.append(extract(layer, marker))
# Keep the real post-display latch and fallback guard. The marker represents
# consuming an undrawn frame after those guards, without touching native GL.
deadline_display = extract(layer, "  override func display() {")
deadline_display = deadline_display[:deadline_display.index("    // Must lock the OpenGL context")] + "    skippedRenders += 1\n  }"
deadline_methods.append(deadline_display)
deadline = (tests / "RenderDeadline.swift").read_text().replace("// PRODUCTION_ATOMIC", atomics)
deadline = deadline.replace("// PRODUCTION_CROP_FRAME_STATE",
                            layer[layer.index("  private final class CropFrameState"):layer.index("  private func takeCropFrameHandlers(")])
deadline = deadline.replace("// PRODUCTION_DEADLINE_METHODS", "\n".join(deadline_methods))

selected = os.environ.get("FULLSCREEN_TEST_SUITE")
for name, source in [("render", render), ("geometry", geometry), ("time", time), ("chrome", chrome), ("crop-scheduling", scheduling), ("crop-deadline", deadline)]:
    if selected and selected != name:
        continue
    path = out / (name + ".swift")
    path.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(path), "-o", str(out / name)], check=True)
    subprocess.run([str(out / name)], check=True)
