"""Extract actual production geometry and verify its controller integration."""
from pathlib import Path
import hashlib
import json
import os
import re
import sys

repo, tests, output = map(Path, sys.argv[1:])
paths = {
    "InteractiveMode.swift": Path(os.environ.get("CROP_ADAPTIVE_INTERACTIVE_SOURCE", repo / "iina/InteractiveMode.swift")),
    "MainWindowController.swift": Path(os.environ.get("CROP_ADAPTIVE_MAIN_SOURCE", repo / "iina/MainWindowController.swift")),
}
sources = {name: path.read_text() for name, path in paths.items()}
interactive = sources["InteractiveMode.swift"]
controller = sources["MainWindowController.swift"]


def extract(text, marker):
    start = text.index(marker)
    end = text.index("{", start) + 1
    balance = 1
    while balance:
        balance += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


checks = 0


def check(condition, message):
    global checks
    if not condition:
        raise AssertionError(message)
    checks += 1
    print("PASS:", message)


finish = extract(controller, "  func finishCropExitTransition(")
readiness = "afterNativeCropFrame(overlay, preparing: overlay.isPlayerTransition,"
ready_tail = finish[finish.index(readiness):]
handoff = extract(ready_tail, "      videoView.videoLayer.withCropFrameHandoff {")
check("overlay.nativeVideo?.prepareRaster(" in handoff,
      "Custom Save prepares density inside the native handoff after frame readiness")
check("overlay.transformedImage(fitting: clip)" in handoff and
      "overlay.imageFrame.width * overlay.selection.width / overlay.sourceSize.width" in handoff and
      "overlay.imageFrame.height * overlay.selection.height / overlay.sourceSize.height" in handoff,
      "Custom Save derives full-source endpoint density from both crop fractions")
check(ready_tail.index("prepareRaster(") < ready_tail.index("startCropExitAnimation()"),
      "Custom Save prepares its raster before starting motion")
check("CropTransitionOverlay.fit(selectionSize, in: bounds)" in handoff,
      "Custom Save preparation uses the final minimum-window/letterboxed viewport")

entry = extract(interactive, "  func finishEntryTransition(")
entry_tail = entry[entry.index("main.afterNativeCropFrame("):]
entry_handoff = extract(entry_tail, "      main.videoView.videoLayer.withCropFrameHandoff {")
check(entry_handoff.index("prepareRaster(") < entry_handoff.index("overlay.presentTransition("),
      "entry prepares density before its first native transition presentation")
check("overlay.entryImageFrame" in entry_handoff and
      "overlay.transformedImage(fitting: overlay.playerVideoFrame)" in entry_handoff,
      "entry considers both the editor viewport and expanded player source endpoint")

player_target = extract(interactive, "  func setPlayerTargetFrame(")
check("prepareRaster(for: [from.sourceFrame, to.sourceFrame])" in player_target and
      player_target.index("prepareRaster(") < player_target.index("presentPlayerTransition("),
      "preset crop prepares both full-source endpoints before presentation")

for text, marker in [(controller, "  private func startCropExitAnimation("),
                     (interactive, "  func presentTransition("),
                     (interactive, "  func presentPlayerTransition("),
                     (interactive, "  func present(frame:")]:
    body = extract(text, marker)
    check("prepareRaster(" not in body and not re.search(r"maximumRasterFrameSize\s*=(?!=)", body),
          marker.strip() + " does not replan density on animation ticks")

backing = extract(controller, "  func windowDidChangeBackingProperties(")
check(backing.index("cancelCropExitTransition()") < backing.index("contentsScale ="),
      "backing-scale change retires the fixed-density owner before normal screen sizing")
geometry = extract(controller, "  func geometryVideoOutputDidChange(")
check("prepareRaster(" not in geometry,
      "aspect/rotation transitions retain their existing nonadaptive allocation policy")

production = "\n".join(extract(interactive, marker) for marker in [
    "final class NativeCropVideoPresentation {",
    "final class DelayedPreparationFeedback {",
    "final class CropTransitionOverlay:",
])
(output / "main.swift").write_text((tests / "main.swift").read_text().replace("// PRODUCTION_GEOMETRY", production))
for name, source in sources.items():
    (output / ("source-" + name)).write_text(source)
(output / "inputs.json").write_text(json.dumps({name: {
    "path": str(paths[name]), "sha256": hashlib.sha256(source.encode()).hexdigest()
} for name, source in sources.items()}, indent=2) + "\n")
print(f"PASS: {checks} production integration wiring checks")
