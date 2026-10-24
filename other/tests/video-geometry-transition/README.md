# Native video geometry transition

Run `bash other/tests/video-geometry-transition/run.sh` on macOS.

The fixture extracts the production `NativeCropVideoPresentation` and pure
`VideoGeometryTransition` helper from `iina/InteractiveMode.swift`. It compiles
with warnings treated as errors and creates native views/layers without opening
windows or creating a renderer.

Coverage includes asymmetric corner/interior-marker mapping at0/90/180/270,
noncentral anchors for the nonzero-angle branch, full inverse-affine clip corners
at quarter and arbitrary angles with nonuniform scale, a constant raster and
layer identity, shortest signed quarter turns, swapped initial rectangles,
positive area through180° motion, and full-quad containment across changing
minimum and portrait viewports. The old zero-angle rectangular aperture and
transform formulas are checked separately, including default and explicit zero
calls. Restoration from either mask type is idempotent and must preserve a newer
canonical mask installed by another handoff.

API conventions:

- `shortestQuarterTurnDelta(from:to:)` accepts user rotation degrees and returns
  signed degrees in[-180,180], choosing+180 for a tie.
- `startFrame(oldVisibleRect:quarterTurnDelta:)` swaps width/height about the old
  center for odd quarter turns; the argument is in degrees.
- `sample(from:to:viewport:progress:initialRotation:)` accepts already-eased
  progress from the shared window clock and rotation in radians. It interpolates
  angle, center and positive dimensions, then contains the rotated quadrilateral
  in the current viewport. It returns `Sample(frame:rotation:)`.
- `present(frame:clip:rotation:)` uses radians, with positive CALayer CCW rotation
  compensating positive mpv clockwise rotation. Omitting rotation retains the
  existing crop branch. Nonzero angles use a polygonal mask; zero retains the
  existing rectangular mask.

These checks establish model geometry and ownership. They do not establish
native mpv readiness, live compositor cadence, visible transition quality, or
HDR/color continuity; those need the root's integrated runtime checks.
