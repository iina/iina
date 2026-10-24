# OSC toolbar feedback

Run `python3 other/tests/osc-toolbar-feedback/run.py` on macOS. The default output
is `build/toolbar-icon-feedback-2026-10-24/focused`; an existing compiler cache is
reused. `--output` and `--module-cache` select other locations.

The fixture compiles the production button/cell, toolbar enum, SF Symbol lookup,
tint helper, animation-duration policy, toolbar reconstruction/state refresh and
PiP/fullscreen property observers. It uses real AppKit windows and button
cells with a prohibited application activation policy. Windows are never ordered
onto the screen; accessibility values and application preferences are controlled
in memory. No profile or system preference is written.

Checks observe all nine configured symbols, semantic state, native cell highlight
and cancellation, accepted/rejected native `performClick` actions, callback glyphs,
layer animation contracts, and state isolation between two controller/window
fixtures. Source placement checks cover early sidebar and Live Text refresh.
Animation durations and final model values are inspected directly, without timing sleeps.
Full hardware mouse tracking, live compositor cadence and app event delivery
remain separate checks; synthetic `mouseDown` tracking did not finish in a hidden
window fixture and is excluded from this deterministic suite.
