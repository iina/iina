# Custom crop checks

Run from the repository root:

```sh
bash other/tests/custom-crop/run.sh
```

The harness compiles the production interactive-mode controller, crop selection
view, scrolling selector, constraints helpers, MPV filter serializer, crop
application/removal methods from PlayerCore, and the window-movement policy from
VideoView, plus the production video-constraint update method, against small doubles for unrelated playback and window services.
It creates hidden AppKit windows with full-size content views and constrained
child video containers, matching the player hierarchy, and renders the selection
overlay into a bitmap.

Checks cover source-pixel input, stable centering while typing, input limits,
free selection and corner/edge resizing, movement at image bounds, independent
X/Y scaling, rotation, nonsquare pixels, native-frame Reset, prior-crop Cancel,
exact odd-pixel filter serialization, crop-state clearing after Reset and Save,
failed-removal state preservation, scrolling/momentum, compact control
placement across wide/tall/minimum windows, inherited window geometry and aspect
lock, and preview geometry after a programmatic window resize. Native delegate
notifications and run-loop fitting verify that repeated resizes across row
breakpoints and wide/tall shapes preserve the requested frame and anchor.
Bidirectional width sweeps check continuous footer/preview reflow for landscape
and portrait sources while controls remain visible and nonoverlapping. Bitmap
checks verify untouched colors inside the selection and shading up to the thin
outline and unclipped corner strokes outside the preview. Native view hit-testing covers all four corner hit areas outside the
video bounds, the nine-point edge target, and background/control drag routing.
Mouse-event checks cover both arms of every thick corner, nearby diagonal hit
space, a fixed opposite corner, and single-axis resizing at straight-edge centers.
Movement policy checks cover entering/exiting crop mode.
Option-resize checks cover all four corners in both directions, all four edge
centers, symmetric image-boundary clamping, one/two-pixel parity limits, and
stationary integer or half-pixel centers. Modifier changes rebase the gesture
without jumping; zoomed source-pixel mapping, selection movement and new-selection
drawing retain their existing behavior.
Shift+Option checks cover uniform centered scaling from every corner and edge in
both directions, a common limit at the first image boundary, exact center and
integer-pixel parity, aspect preservation within symmetric pixel quantization,
live Shift switching, zoomed source mapping, and unchanged Shift-only resizing.
Footer checks verify dense centered rows in the minimum window, preview-edge
alignment in wide windows,
a usable minimum width for narrow portrait previews, and continuous preview/footer
sizing without feedback.
Width sweeps cover landscape, portrait, and ultrawide sources at three window
heights. Bidirectional diagonal sweeps vary both dimensions at locked landscape,
portrait, and ultrawide proportions; they bound preview growth and control
movement between row changes while retaining native frames and crop pixels. Margin checks
cover adaptive top (28–48 points), side/bottom (12–24), and preview/control
spacing (10–20), including the agreed window-size examples and top-band hit
routing. Footer checks cover horizontal W/H and progressive spreading and merging
into one row as the preview gains space. Bidirectional sweeps require bounded
control movement through the entire transition without breakpoint exceptions.
They verify many intermediate vertical positions, exact reversal at each width,
no timed reflow animations or movement after resizing stops, and continued
alignment to preview edges at increasing wide-window sizes. A screenshot-size
regression checks that available first-row space is used promptly and that the
longest two-digit ratio fits without changing preview geometry.
Ratio checks cover live W/H updates without preview shifts, nonsquare
pixels, tiny selections, Reset, and personal-preset cyclic scrolling.
Production starts with an empty personal list. Regression checks seed personal
ratios only in a unique isolated UserDefaults suite, removed when checks finish.
Personal-preset checks cover Add-only empty menus, one-click saving without a
dialog, exact display-aspect persistence, duplicates, malformed preferences,
sharing between player windows, resolution/pixel-aspect/rotation adaptation,
selection stability, and preserving presets after Cancel.
Deletion checks cover removing current/other/last ratios, stale callbacks,
persistence, unchanged crop/zoom/window geometry, safe empty-list cycling,
direct right-click and Control-click deletion, accessible actions, and keyboard
selection. Secondary clicks persist deletion immediately without a context menu
or undo registration; releasing Control-click must not select the deleted ratio.
The compact aspect list uses a height-limited scrollable popover above its control;
initial row sizing must keep hit and accessibility bounds inside the visible width.
Holding Option replaces Add with Delete for the checked preset; tests cover
restoring both Add states, dimmed Delete without a checkmark, pre-held Option,
unchanged popup geometry, accessibility refresh, exact deletion routing, and
Escape with an entirely disabled list. Parent-window modifier events and popup
responder flags both synchronize the temporary footer mode. Free-selection
labels use the nearest integer ratio with each component limited to 1–99;
checks cover reduction, approximation, portrait symmetry, extreme proportions,
and rotated nonsquare pixels. W/H and the saved crop retain exact pixel dimensions.
During pointer drags or dimension typing the ratio label remains stable; checks
verify publication on mouse release, field focus loss, and input confirmation,
while selection geometry and W/H continue updating immediately. Save uses the
current selection even before the displayed ratio is committed.
Animation checks exercise immediate expansion, equal-width digit updates during
growth, a 250ms shrink debounce that restarts on text changes, final title fitting,
stationary preview/outer actions, centered controls, and Reduce Motion.
Digit-drum checks cover all 100 cyclic digit pairs, shortest paths across zero,
forward ties, independent numerator/denominator places, unchanged glyphs and
separator, added/removed tens, interruption, completion, Reduce Motion, and
cleanup on leaving crop mode. The crop selector opts into this animation;
the plugin selector retains its existing whole-title cylinder and timing.
Preset swipe checks verify whole-title direction, wraparound, menu selection,
and restoring digit drums for subsequent manual edits. Reset uses individual
digit drums and a 280ms cubic ease-out selection-frame transition. Checks cover an
immediate logical full-source target, intermediate presentation, exact final
edges, invariant window/preview geometry, repeated Reset, pointer/arrow/field/
preset/zoom exclusion during the transition, ignored presses remaining inert
after completion, restored editing, Reduce Motion, exit cleanup, Escape routing,
and Save/Cancel during the transition.
Preview navigation checks cover pointer-anchored zoom, the fitted minimum and
bounded maximum, two-axis pan and momentum, image-edge clamping, off-preview
gesture routing, cumulative pinch magnification, and edit/gesture exclusion.
They also verify invariant crop pixels and filter output, zoomed handle mapping,
live-layer clipping, indicator/menu state, cursor registration for offscreen
edges, resize preservation, Fit, session cleanup, and fresh-session reset.

Mouse navigation checks cover Option+wheel pointer-anchored zoom and limits,
ordinary vertical wheel pan, Shift horizontal pan (including macOS-remapped
horizontal deltas), modifier precedence, off-preview routing, and invariant crop
pixels. Keyboard checks use a native AppKit field editor to verify Return/keypad
Enter confirmation, preview focus after confirmation, and Return Save. Escape
resets a non-full selection and cancels from the full-source selection, regardless
of timing or intervening input. Checks cover same-aspect smaller crops, reediting
after Reset, untouched/empty selections, pending dimension confirmation, Escape
during Reset animation, original-crop restoration, repeat suppression, session
cleanup, window isolation, and delogo isolation.
Stale popover-close notifications must preserve another menu's keyboard routing
and an active dimension field's first responder.
Crop-entry failure checks retain the original player geometry/filter when mpv
rejects crop removal, then verify successful retry and Cancel restoration.

These checks do not replace live decoding, physical mouse/trackpad, HDR,
external-display, or older-macOS validation. See
[the implementation record](../../../docs/testing/2026-10-12-custom-crop.md).

Crop sizing integration also verifies entry/exit refresh and successful/failed
filter changes. The adjacent `crop-window-frame` suite exercises actual native
window sizing, aspect-lock and explicit-scale methods across reconfiguration.

Save and Cancel restoring a crop wait for MPV output geometry; no-filter exits
refresh immediately without an intermediate uncropped sizing pass.

## Exact crop color regression

To exercise the generated production filter through the installed custom engine:

```sh
mkdir -p build/crop-color-tests
CROP_FILTER_OUTPUT="$PWD/build/crop-color-tests/filters.json" bash other/tests/custom-crop/run.sh
python3 other/tests/custom-crop/engine.py build/crop-color-tests /Applications/LYINA.app/Contents/Frameworks/libmpv.2.dylib
```

An unsafe NV12 odd-x control must reproduce the color shift. The production filter
must retain normal colors at the exact odd coordinates for NV12, P010/P016,
planar YUV and RGB, with exact output dimensions. A separate HDR-tagged 16-bit
ramp checks source-pixel origin and adjacent luma values without an 8-bit hop.
Native tests also cover protected-filter readback, raw serialization, legacy
crop restoration, and the unchanged direct path for aligned rectangles.
