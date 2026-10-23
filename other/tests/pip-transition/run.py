#!/usr/bin/env python3
from pathlib import Path
import subprocess
import os

root = Path(__file__).resolve().parents[3]
tests = Path(__file__).resolve().parent
out = root / "build/pip-transition-tests"
out.mkdir(parents=True, exist_ok=True)


def extract(source, marker):
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


main = (root / "iina/MainWindowController.swift").read_text()
start = main.index("  func enterPIP() {")
end = main.index("  func pipActionPlay(", start)
methods = main[start:end] + extract(main, "  func showUI() {")
methods += "\n" + "\n".join(extract(main, marker) for marker in [
    "  func beginOperationFeedback()", "  func endOperationFeedback(", "  private func cancelOperationFeedback()",
    "  private func relocateOperationFeedback(",
])
assert "captureSnapshot" not in methods
support = (tests / "Support.swift").read_text().replace("// PRODUCTION_PIP_METHODS", methods)
interactive = (root / "iina/InteractiveMode.swift").read_text()
support += "\n" + "\n".join(extract(interactive, marker) for marker in [
    "final class DelayedPreparationFeedback {", "final class PreparationFeedbackView:",
])
support += (root / "iina/FadeableViewController.swift").read_text()
lifecycle = support + (tests / "main.swift").read_text()

layer = Path(os.environ.get("PIP_TRANSITION_LAYER_SOURCE", root / "iina/ViewLayer.swift")).read_text()
geometry = "\n".join(extract(layer, marker) for marker in [
    "  private var pixelSize: CGSize", "  func invalidatePIPDisplay()", "  override func canDraw(",
]).replace("videoView.$isUninited", "videoView.uninitialized")
render = (tests / "RenderSupport.swift").read_text().replace("// PRODUCTION_GEOMETRY", geometry)

display = extract(layer, "  override func display() {")
display = display[:display.index("    guard isUpdate && needsFlip")] + "    _ = isUpdate\n  }"
transaction = (tests / "TransactionSupport.swift").read_text().replace("// PRODUCTION_DISPLAY", display)

for name, source in [("lifecycle", lifecycle), ("geometry", render), ("transactions", transaction)]:
    if os.environ.get("PIP_TRANSITION_TEST_SUITE") and os.environ["PIP_TRANSITION_TEST_SUITE"] != name: continue
    generated = out / f"{name}.swift"
    binary = out / name
    generated.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(generated), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
