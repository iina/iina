# Floating controller position sheet checks

Run from the repository root on macOS with Xcode command-line tools:

```sh
bash other/tests/osc-position-preview/run.sh
```

The harness compiles the actual `OSCPositionSettingsSheetController.swift`,
`UIHelper.swift` and `ConstraintsSugar.swift` into a standalone AppKit process.
It uses a dedicated `osc-position-preview-harness` preference suite, its own
windows and a prohibited activation policy. It does not use the installed IINA
application, production preferences, media, plugins or player services.
Compilation output and a separate Foundation home are under
`build/osc-position-preview-tests`.

Checks cover first presentation of a programmatic sheet, actual Auto Layout
preview dimensions, accessible preview role and label, compact input/percent column
layout in LTR and RTL, local draft isolation, Cancel/reopen, active field editor
commit on Save, invalid number rejection, Escape while an incomplete edit is
active, comma decimal parsing, preview drag conversion in LTR/RTL, visible
boundary placement, mouse-up state, and default-only preference writes.
A second process verifies persistence and unchanged current-position values.

The tests inspect the registered Return default button, but do not prove actual
Return routing: the prohibited harness is not a key window. Dragging uses
synthetic events delivered directly to the production preview. Hardware pointer
tracking, cursor appearance, visual drawing, accessibility presentation, settings
button placement/enabled state and the full IINA reset interaction still require
isolated application verification. Unrelated helper preferences and image tinting
are stubbed.

Boundary checks inspect the actual preview frame in LTR/RTL: 16pt side gaps,
flush vertical endpoints and containment below the sample titlebar. The initial
model explicitly uses 50% horizontal and 16pt from bottom. Each axis independently
selects percent or point, with a physical edge selector visible for both units. Percent values measure
travel from that selected edge; changing the edge complements the value and
preserves visible position.
Conversions preserve visible placement; drags retain units and anchors. Point
input accepts values above 100; distances use the preview's logical scale.
Save writes only the versioned default dictionary; live current state is unchanged.
Legacy percent defaults remain readable. Cancel discards unit/anchor changes.

Preview context checks cover portrait/wide/compact aspect fitting, centered percentage placement, physical point gaps under scaling, and unchanged position values when reference dimensions change.

The OSC preview uses shared native panel metrics instead of scaling a captured panel frame. Coverage checks nominal dimensions at 80%, intermediate and 100% scale for regular/compact UI, minimum-window containment, and Custom dimension clamping/commit. The native layout harness separately compares those nominal heights with real AppKit panel frames across both compact modes and material styles.
