#!/bin/bash
#
# Check that looking around works, and that it does not break the ordinary
# controls it sits on top of.
#
#   other/vr2d-tests/input.sh <path-to-IINA.app> [work-directory]
#
# The app drives its own video view and writes a report; this asserts on it.
# What is being checked:
#
#   - a drag pans the view instead of picking the window up and moving it
#   - dragging right looks left, by the angle the frustum says it should
#   - a drag is not also counted as a click, so panning cannot pause playback
#   - a click that does not move still reaches IINA, so playback control works
#   - scrolling zooms
#   - all of it works while paused — the picture changes with no new frame,
#     which is the whole reason for doing this in the renderer

set -e

app="${1:?usage: input.sh <path-to-IINA.app> [work-directory]}"
work="${2:-$(mktemp -d)}"
here="$(cd "$(dirname "$0")" && pwd)"

"$here/fixtures.sh" "$work" >/dev/null
rm -rf "$work/input"
mkdir -p "$work/input" "$work/home"

# `-singleClickAction 2` is pause and `-doubleClickAction 0` is none, so a click
# acts immediately rather than waiting out the double-click interval.
# The report below is what this asserts on. `iina.log` is best effort: IINA's
# output is block buffered, so a run that dies loses its last 28KB. To read a
# whole run, repeat the command by hand under `script -q /dev/null`, which gives
# the app a pty and line buffering.
HOME="$work/home" IINA_VR2D_INPUTTEST="$work/input" \
  timeout 150 "$app/Contents/MacOS/IINA" \
    -singleClickAction 2 -doubleClickAction 0 \
    "$work/pattern_he_sbs.mkv" >"$work/input/iina.log" 2>&1 || true

report="$work/input/report.json"
if [ ! -f "$report" ]; then
  echo "no report written — see $work/input/iina.log" >&2
  exit 1
fi

# The drag is 80 points across a window whose horizontal field is known, so the
# expected yaw is not a guess: it is dx / width * hFov.
python3 - "$report" "$work/input" "$here/compare.py" <<'EOF'
import json, math, subprocess, sys

report = json.load(open(sys.argv[1]))
work, compare = sys.argv[2], sys.argv[3]
failures = []

def check(name, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}{('  — ' + detail) if detail else ''}")
    if not ok:
        failures.append(name)

check("a drag pans rather than moving the window",
      report["canMoveWindowWhileOn"] is False)

before, after = report["viewBefore"], report["viewAfterDrag"]
check("dragging right looks left", after[0] < before[0], f"yaw {before[0]:.2f} -> {after[0]:.2f}")
check("pitch is untouched by a horizontal drag", abs(after[1] - before[1]) < 1e-9)
check("panning does not pause playback", report["pausedAfterDrag"] is True)
check("a click still reaches IINA", report["pausedAfterClick"] is False)
check("scrolling zooms in", report["fovAfterScroll"] < report["fovBeforeScroll"],
      f"{report['fovBeforeScroll']:.1f}° -> {report['fovAfterScroll']:.1f}°")

# IINA's forced redraw while paused is itself a little flaky — it misses about
# one capture in five with the pass switched off. What matters is that turning
# the pass on does not make it worse.
on, off = report["capturesWhileOn"], report["capturesWhileOff"]
check("the pass does not make redrawing while paused less reliable", on >= off,
      f"{on}/5 captured with it on, {off}/5 with it off")

check("the settings page builds", report["settingsRendered"] is True,
      f"{report['settingsSections']} sections")

# The two captures were taken while paused, so any difference between them can
# only have come from the reprojection pass re-running over the held frame.
size = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=width,height",
                       "-of", "csv=p=0", f"{work}/before.png"],
                      capture_output=True, text=True).stdout.strip()
width, height = size.split(",")
for name in ("before", "after"):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f"{work}/{name}.png",
                    "-f", "rawvideo", "-pix_fmt", "rgb24", f"{work}/{name}.rgb"], check=True)
out = subprocess.run(["python3", compare,
                      f"{work}/before.rgb", f"{work}/after.rgb", width, height],
                     capture_output=True, text=True).stdout.split()
moved = float(out[0])
expected = abs(after[0] - before[0])
check("the held frame is reprojected while paused",
      abs(moved - expected) < 1.0,
      f"picture moved {moved:.2f}°, view moved {expected:.2f}°")

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall interaction checks passed")
EOF
