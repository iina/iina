# Floating OSC reset checks

Run from the repository root:

```sh
bash other/tests/osc-position-reset/run.sh
```

The runner compiles the actual production floating OSC, placement model,
translucent wrapper and constraints into a standalone AppKit process. It uses
an isolated preference suite and deterministic native row heights instead of
unrelated playback controls. Output is under `build/osc-position-reset-tests`.

The current harness covers the approved shared travel area: 16pt side gaps,
flush bottom/top placement below the titlebar, physical horizontal coordinates
in both LTR and RTL, and explicit 50% / 16pt mixed-unit initial position. It compares actual default and manual placement trajectories through
small, laptop, 16:9, 21:9 and square windows, including adaptive panel sizing.
It also verifies sidebar-independent placement, collapsed-axis intent, canonical
persistent default and temporary session state, ignoring historical manual state and absence of new writes to legacy
coordinate formats. A second process verifies persistence.

Native group layout and proposed-size callbacks remain covered by the separate
`floating-osc-scale` runner. Superseded harnesses are excluded.

Synthetic AppKit input and direct native size changes do not prove physical
pointer tracking, actual live resize or monitor transfer. Those remain isolated
full-app / hardware acceptance.

## Isolated full-app lab

Build with `xcodebuild -project iina.xcodeproj -scheme iina -configuration Nightly -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES`,
then run `python3 other/tests/osc-position-reset/prepare-lab.py` once. It copies
only the built app, changes its bundle ID, signs the copy ad hoc, creates a
synthetic Y4M fixture and seeds only `org.iina.osc-position-lab`. CF preferences
stores that dedicated domain under the normal user's Preferences directory;
`CFFIXED_USER_HOME` isolates Foundation application support and caches. The
production `com.colliderli.iina` domain and installed bundle are untouched.

Start the lab's executable directly (keep the process alive while testing):

```sh
CFFIXED_USER_HOME="$PWD/build/osc-lab/home" TMPDIR="$PWD/build/osc-lab/tmp/" \
  "$PWD/build/osc-lab/IINA OSC Lab.app/Contents/MacOS/IINA" \
  "$PWD/build/osc-lab/fixture.y4m"
```

Bind Computer Use to the already running `org.iina.osc-position-lab` app. Opening
by bundle path after the process exits can launch a new process without the
isolation environment; restart with the command above instead. The preparation
script refuses to overwrite an existing lab bundle/profile. Do not copy plugins
or production settings into this lab.

## Current dual-unit contract

Player, preview and resize use the same `FloatingOSCPlacement.frame` and
`capturing` functions. Each axis stores its unit, anchor and value in a versioned
dictionary. Percent divides physical safe travel; point measures from the panel
edge to the selected usable-window edge. The initial model is 50% horizontal and
16pt from bottom. Preview drag retains each axis's unit and anchor. Live player drag converts both temporary axes to percentages; the saved default retains its configured units. Resize clamps display
without changing requested values. Numeric/manual percent trajectories are
compared across native materials and RTL; all 16 unit/edge combinations are checked
through small, laptop, 16:9, 21:9 and square windows. Legacy saved defaults remain readable; historical manual positions are ignored.
New drags write no preferences. A second process starts at the saved default.

## Window-session lifetime

Current placement is owned by each `OSCFloatingView`. It survives layout refresh,
media replacement in the same window, resize, sidebar changes and showing an
active window. Closing ends the session; late layout callbacks cannot reactivate
it. Showing the reused player window begins from the latest saved default.
The harness covers independent windows, default-only persistence, no drag writes,
close/reopen, and a separate process starting from default despite historical
manual settings. MainWindowController routes close/show into these hooks.

## Protected return motion

A successful reset uses one continuous spring-launch/stretch/rebound curve,
with zero endpoint velocity and one smooth reversal. The launch supplies force
immediately instead of slowly building acceleration; final acceleration settles
to zero. After crossing the
saved position it progressively slows into the stretch; the gentler rebound
settles without secondary oscillations. Desired overshoot is 20% of total travel,
capped at 96pt, with its components limited independently by physical window
room. A crowded axis no longer suppresses a free axis. Excursions smaller than
12pt or 40% of the requested component are omitted; that axis instead uses the
limiting monotonic spring, preserving a quick launch without a tiny arrival shake.
The original 270–495ms time basis and quadratic launch are preserved until
crossing the target. Stretch gains up to 12% of that basis (32–59ms), with a
minimum-jerk clock offset that gradually slows the approach to the same peak.
A small source-phase interval limits that addition to avoid a late acceleration.
The soft rebound trajectory is retained and shifted by the added stretch time;
its existing 8% settling extension remains. Total allocated time is 324–594ms.
A monotonic/crowded axis retains its physical trajectory and holds the endpoint
for the extra tail. The source/reference rationale is documented in
`docs/testing/2026-10-15-osc-return-tension-time.md`.

Sidebar visibility and layer order do not affect OSC geometry. Reset can travel
through an open sidebar; manual dragging is limited only by physical window
containment. Opening a sidebar during a reset starts immediately and does not
redirect, reject or defer the reset. There is no sidebar rejection shake.

During return, OSC shields controls and rejects dragging, scrolling, secondary
clicks and repeated reset. Motion uses one common-mode timer. A resize contains
the current OSC before the next animation tick without replacing session intent.

The geometry matrix disables animation deliberately. Motion checks exercise real
run-loop ticks, hit routing, bounded overshoot/reversal, tracking mode, resizing
and lifecycle interruptions. `sidebar-window-frame/run.sh --panel-depth-only`
additionally exercises native sidebar slide/fade transitions and header actions.
Fixture results do not replace full-player gesture/motion acceptance.
Deterministic trajectory samples additionally check progressive braking, a single
turn, gentle endpoint settling and distance/room-dependent amplitude. A settling
regression requires at least the final two thirds of the rebound to decelerate;
fixed pre-change samples verify the launch at the same elapsed times and the
soft rebound shifted by the stretch extension. A separate check requires a
longer target-to-peak interval at the same amplitude and no repeated reversals. Native long
and short horizontal returns verify the visible stretch in both directions. A native
diagonal bottom-edge regression checks a substantial horizontal rebound and
monotonic vertical settling; deterministic paths mirror that case across both axes.
Edge/corner samples cover actual OSC/material frames in both native styles and
minimum-size windows. The resize regression checks immediate containment and
every subsequent sampled frame rather than only the final landing.
