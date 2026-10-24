# Crop entry and exit rendering boundary

Run `bash other/tests/crop-exit-transition/run.sh` from the repository root.

The harness compiles the production crop overlay, MainWindow transition methods
and ViewLayer snapshot queue methods and shadow-copy initializer. A controlled rendering boundary releases
image continuations explicitly; native AppKit supplies views and image drawing.

Checks cover unchanged editor presentation during preparation, duplicate Save, obsolete
restart events, actual overlay painting, selection-to-output mapping without
stretching, intermediate wide/portrait/extreme/zoomed aperture coverage with a gray surround, bounded input blocking, new-frame readiness, a separate render after
the final window layout, unchanged/full-source exits, failed
filters/captures, media replacement and cancellation. Concurrent snapshot readers
share one draw across model and Core Animation shadow layers; renderer shutdown
from either layer releases pending and later requests exactly once.

Reverse overlay checks also cover entry aperture coverage, uniform scaling, late
outline and exact native control/image endpoints. Entry controller lifecycle
checks live in the adjacent custom-crop suite.

The adjacent crop-window-frame suite verifies output geometry is held until the
presentation can move the image and window together, and that video reconfiguration
uses actual filtered-output readiness, while no-op Save/Cancel does not wait for
a nonexistent filter restart. These checks
establish sequencing and geometry. Real compositor recording, including the
direct OpenGL snapshot path, remains a separate runtime check.

Custom-to-preset/None checks also exercise the player-frame bridge: source capture
precedes mutation, target capture uses the destination viewport, the previous
frame remains visible until readiness, and live rendering replaces the cover
only after the final layout. Cancellation, supersession, disabled motion,
startup, fullscreen/PiP bypass and opaque target padding are covered. Visible
players capture the next surface draw without another offscreen source render;
occluded players retain the offscreen path. Crossing source regions interpolate
a shared aperture with black padding excluded from the content blend. The routing
fixture extracts `applyCropChange` from PlayerCore and checks ordinary presets,
the owned audio-only mixer, while same-size changes and graphs that process video
retain their existing readiness paths.
