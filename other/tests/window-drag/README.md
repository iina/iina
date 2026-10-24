# Window drag lifecycle regression

Run `bash other/tests/window-drag/run.sh` from the repository root.

The harness extracts production MainWindow mouse handlers, focus cancellation and
window event routing. Native NSEvents and an invisible AppKit window provide
event identity/coordinates. Window Server handoff, plugin actions, sidebar/control
ownership and the current button bitmap are fixture boundaries; events are never
posted into the user's UI. A native handoff deliberately returns immediately
without delivering mouseUp, matching the documented API contract.

Checks cover one original mouse-down handoff per gesture, queued movement after
release, missing mouseUp followed by a new click, consumed releases, focus loss,
click jitter, repeated drags, wrong-window/right-button events, sidebar/OSC and
editor ownership. These deterministic failures do not establish the exact
physical trackpad sequence behind a reported intermittent Window Server latch.

`WINDOW_DRAG_MAIN_SOURCE` and `WINDOW_DRAG_WINDOW_SOURCE` can select matching older
sources; `WINDOW_DRAG_OUTPUT_DIR` isolates output. The old controller's unused
state fields and absent cancellation helper are fixture compatibility only.
`run.sh repeat` and `run.sh released` isolate the two pre-fix regressions.
