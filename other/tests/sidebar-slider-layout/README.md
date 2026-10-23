# Sidebar slider layout

Run `bash other/tests/sidebar-slider-layout/run.sh [OUTPUT]`.

Compiles the production `SidebarSliderView`, constraint helpers and circular
buttons against AppKit, with a lightweight player/UI factory double. It checks
card height and slider position through repeated default/nondefault transitions,
and uses AudioDelayView's production visibility overrides to check that its
numeric input reaches the trailing edge without an inline reset control.

The Reset menu rendering checks live in `other/tests/track-processing/run.sh`.
They render the production menu control with a deterministic window pointer
position, including stale enter events, highlighted cells and inactive windows.
