# Native PiP handoff checks

Run `python3 other/tests/pip-transition/run.py` from any directory.

The lifecycle harness extracts the current PiP and UI-reveal methods from
`MainWindowController.swift`. Real AppKit reparenting and coordinate conversion
are combined with a controlled native-controller boundary. Checks cover Hide,
Minimize, Do Nothing, fullscreen, playing/paused state, modern preparation and
legacy entry, duplicate/stale preparation, cancellation, concealed return,
video attachment before reveal, and transaction ownership release.

Geometry checks execute the current layer invalidation and `canDraw` methods
for paused shrink/enlargement, same-size host replacement, Retina changes,
playing frames, stable geometry, teardown and live resize. Transaction checks
execute the current `display` prefix with a transaction spy, preserving the
ordinary-player and background flush contracts.

These checks validate code contracts; they do not simulate native compositor
pixels, private flight animation, frame pacing, HDR or multiple macOS versions.
Full-app recording and physical interaction checks remain separate. Use media
with an audio track when checking volume controls.
