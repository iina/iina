# Sidebar window-frame regression

Run `bash other/tests/sidebar-window-frame/run.sh`.

Use `--panel-depth-only` for the independent position/depth policy. Checks cover
stationary OSC frames through native slide/fade opening and closing, independent
sidebar priority on opening/reopening/replacement, every primary click count, all three
sidebar bodies and header controls, secondary/titlebar exclusion, manual
overlap and reset while a sidebar opens. SidebarViewController header content is
a native fixture; the production SidebarController and OSCFloatingView are compiled.

Use `--seek-preview-only` for native hover-preview timing and cancellation checks.
These exercise the production 100ms entry, 150ms exit hold and 150ms fade timers, MainWindow mouse
handlers, and slider-cell tracking methods. They cover quick crossings, latest
position, reentry, stable hide deadlines, current occlusion, teardown, tracking
run-loop mode and immediate timestamp visibility during active seeking. Fade
checks cover intermediate opacity, synchronized image/time/chapter opacity,
reentry during both hold/fade, repeated leave, immediate lifecycle and active-seek
cancellation, animation opt-out and owner release while fading. They also
compile the production `TimePreviewView`, chapter text update and preview stack
placement: separate timestamp/chapter bubbles, thumbnail-width tail truncation,
short/blank/Unicode titles, endpoint containment, top/floating placement and both
visual-effect/liquid-glass styles. Optional `SEEK_PREVIEW_ARTIFACTS` writes native
bubble render artifacts; these do not replace a full-player hover recording.

The native AppKit harness compiles the actual `SidebarController`,
`SideBarContainer`, `TranslucentView`, and layout helpers. It injects the current
production `MainWindowController.setupVideoContainerConstraints` and OSD /
additional-info positioning constraints. Controller/player content are fixture
boundaries. Chrome uses a required internal width analogous to fixed titlebar
icons/accessories; its sidebar-responsive priorities are read from production
`Titlebar.swift` and `OSCBottomView.swift` at each run.

The fixture reproduces implicit AppKit window growth without calling `setFrame`:
a 390pt window becomes 480pt when a 300pt inset and required 180pt chrome row
combine at priority 750. Low inset priority alone can still affect native minimum
size when required physical chrome containment is present. Keeping chrome inset
desires below `fittingSizeCompression` removes them from that minimum-size chain,
while physical containment remains required.

Checks compare exact `NSWindow.frame` including origin through opening, hiding,
side switching, both panels, and resizing in a 390×220 pt stress frame below the
400×225 pt Floating minimum. They
cover edge-to-edge/inset video, RTL/LTR, real visual-effect/liquid-glass wrappers,
Disable animations, sliding, and Reduce motion fading. The harness also samples
the frame throughout animation, beyond final-state assertions. An additional
native top-OSC fixture injects the actual Titlebar constraints and MainWindow
stack visibility priorities, checking secondary-group detachment, retained
timeline, physical bounds in both directions, and restoration after expansion.
Animation checks briefly order fixture windows to sample actual presentation
layers; all preferences use in-memory stubs.

This establishes native constraint/controller behavior, not the full player UI,
real sidebar page content, hardware dragging, or user acceptance. Those remain
full-app checks.
