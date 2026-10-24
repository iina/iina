# OSC toolbar feedback — 2026-10-24

The runtime OSC toolbar now gives each enabled icon its own hover glow and
immediate native press feedback. Existing normal and alternate symbols are
preserved. Sidebar selection updates when a show, hide or replacement is
accepted, before the panel animation completes. PiP, fullscreen, Live Text and
rebuilt toolbars derive their selected state from their own window or preference.
Notifications from another player window cannot overwrite local selection.

Only brightness and glow interpolate; symbol selection is synchronous. Native
AppKit dispatch remains responsible for actions and cancellation. Disabled,
hidden or detached controls clear transient feedback. Reduce Motion and Disable
animations apply feedback immediately.

## Validation

- `python3 other/tests/osc-toolbar-feedback/run.py`: 183 native AppKit checks and
  four source placement checks passed on the extracted Part 1 branch. The suite
  compiles the production button, symbols, toolbar reconstruction/state methods
  and PiP/fullscreen property observers.
- `bash other/tests/sidebar-stacking/run.sh`: 98 native background-panel, titlebar
  and WebKit checks passed on the extracted Part 1 branch.
- The same production change passed a local combined arm64 Release build and
  isolated app checks for hover, Settings/Playlist selection and Escape closure.
- Deterministic checks cover accepted/rejected/disabled actions, press cancellation,
  interrupted feedback, two-window isolation, toolbar rebuilds and accessibility
  animation preferences. The test README describes the fixture boundaries.

Full hardware mouse tracking, compositor cadence, Intel and older macOS remain
outside this verification. OpenSubtitles is excluded from this change.
