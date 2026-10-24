# Adaptive crop transition resolution

Run `bash other/tests/crop-adaptive-resolution/run.sh` from the repository root on macOS.

The runner extracts the actual `NativeCropVideoPresentation` and crop overlay.
It checks endpoint demand for Retina and ordinary screens, full-frame/shrinking
transitions, both source axes for anamorphic and rotated video, source-detail
limits, the 4K area and 8192 edge budgets, existing large-raster preservation,
rounding, invalid metadata, and tiny crops/8K sources. Native-layer cases cover
preparation before presentation and a one-time upgrade of an active editor
raster, using larger logical bounds at the normal screen density. They verify
physical pixel coverage at 1x and 2x, unchanged projected image/aperture across
the allocation boundary, fixed logical bounds/density through 101 projection
updates, a single layout acquisition/restoration, floating-point contents
precision, and restoration/canonical ownership.

Separate source integration checks require Save preparation inside the native
handoff after readiness and before movement, entry/preset endpoint planning,
allocation-free projection ticks, and transition retirement before a backing
scale change. They check production wiring structurally; the complete window
and asynchronous controller lifecycle is covered by the existing
`crop-exit-transition`, `crop-window-frame`, and `geometry-motion` suites.

Artifacts, exact source copies, and SHA-256 hashes are saved under
`build/crop-adaptive-resolution-tests/`. The tests open no window and create no
renderer. `.RGBA16Float` preservation checks the native layer contract; visible
HDR/color correctness, GL surface allocation, compositor cadence, and real
CPU/GPU/memory cost require live player measurements.
