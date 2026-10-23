# Interface shortcuts

Run `bash other/tests/interface-shortcuts/run.sh` on macOS with Xcode. The test
window briefly owns keyboard focus and closes when the harness finishes.

The harness compiles production command definitions, config parsing/serialization,
key normalization, editor criteria, interface command dispatch, the window event
entry point and layered Escape handling. Native window event dispatch verifies
that a sidebar dismissal does not exit fullscreen in the same press, and a held
key does not cascade. MPV, sidebar layout, OSC presentation and plugin content are
fixtures. Mustache rendering of unrelated mpv labels is a fixture; interface
commands do not use it.

Checks include legacy/default and explicitly overridden Escape, local editor/OSD
priority, argument validation, stable plugin IDs, panel targets, OSC routing and
config save/reload. The plugin selector, Custom Crop and OSC preview suites cover
their real implementations independently. Full-player UI checks remain necessary
for native popovers/sheets, web content focus and the Key Bindings editor.

The direct Custom Crop action preserves sidebar state. The harness also compiles
the separate existing menu entry method, covering its sidebar dismissal,
duplicate requests and interrupted-transition recovery. Both paths retain
active-editor/PiP guards where applicable. Full crop selection and state-based
Escape remain covered by the Custom Crop suite.
