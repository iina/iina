# Initial window geometry sheet checks

Run on macOS with Xcode command-line tools:

```sh
bash other/tests/window-geometry-preview/run.sh
```

This standalone AppKit harness compiles the actual window geometry sheet, draft
model, geometry parser, shared template drawing, UI helper and constraint helper.
The helper loads the repository's actual English localization strings and native
popup titles.
It uses separate windows, a prohibited activation policy, and a UUID-suffixed
`window-geometry-preview-harness` preferences suite per process, removed at exit.
Build output and a separate Foundation home are under
`build/window-geometry-preview-tests`. No installed
IINA, media, plugins, production preferences or player services are used.
Unrelated layout services and the current AppData minimum (285×120) are stubbed.

Checks cover explicit presentation, actual preview dimensions, conditionally visible
editable fields, absence of in-editor switches, all four external enable-state
combinations, preserved disabled draft values, Save/Cancel, invalid integer
rejection, and no-op preservation of raw geometry. Disabled-position dragging is inert; hidden groups shrink the fitted sheet.

Synthetic preview checks verify physical anchor movement without RTL mirroring,
out-of-screen drag bounds, mode-specific movement/resizing, centered percentage
resize, free resize corners for point anchors, production minimum and screen-fit
limits, and cleared interaction state. A focused edit→drag→Save check prevents a
field editor from restoring stale coordinates.

The registered Return default button uses normal AppKit behavior; actual Return
routing and mouse tracking require isolated application verification because the
prohibited harness cannot become a key window. Template pixels, cursor appearance,
accessibility presentation, the settings integration, actual media aspect/display
behavior and applied player geometry are also application-level checks. Tests do
not launch or mutate a real player.

Preview context checks cover real-context selection, a one-row Custom size editor, positive integer validation, and unchanged geometry after context-only edits and Save. Monitor discovery and current-media lookup are verified in the isolated Lab.

Wallpaper checks cover system fit/fill/stretch modes, visible-frame cropping, retained Custom background, missing-background clearing, and bitmap rendering. Fixtures avoid dependence on the current desktop image; live loading is validated in the isolated Lab.
