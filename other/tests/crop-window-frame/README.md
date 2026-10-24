# Crop, transforms and track/output window sizing regression

Run `bash other/tests/crop-window-frame/run.sh` from the repository root.
The AppKit harness extracts the actual MainWindow video-size handler, aspect
setter, explicit scale action, screen/minimum clamp and NSSize/NSRect helpers.
It also extracts the actual PlayerCore Aspect Ratio/Rotation and track setters,
video reconfiguration handler and audio track-change handler.
Playback, preferences, UI refresh and MPV synchronization are fixture boundaries.

Locked windows fit the cropped display aspect inside a retained reference window,
subject to existing minimum and screen limits. Manual resizing while cropped
scales both dimensions of that original reference; Reset recovers its proportions
at the updated scale. Programmatic minimum/screen clamps and intermediate crop
animation frames cannot replace the reference. Unlocked windows retain their
freely chosen frame. Checks cover wide/portrait/tiny/uncropped output,
logical/physical resolution, centering, repeated reconfiguration, fullscreen
prior geometry, startup sizing of the next file and explicit scale commands.
A concrete 874×525 → 874×492 case protects against the rejected fixed-frame
letterboxing behavior. PiP receives the cropped display aspect independently.
The wide-crop regression rejects area preservation (960×540 → 960×240).
Further checks cover manual shrink/enlarge, minimum-clamped portrait resizing,
explicit scale while cropped, repeated transforms and deferred animation targets.
When a resize removes minimum padding, the original reference follows the fitted
video scale rather than the padded outer frame; Reset retains that image scale.

`CROP_WINDOW_MAIN_SOURCE=/absolute/path/to/MainWindowController.swift` selects an
alternative controller source with compatible fixture state. Older revisions
that predate the reference-window fields need their matching fixture. The
retained `window-before.log` for the 2026-10-20 reference change records the
wide-crop assertion failing against the previous area-preserving policy.
Editor Save/Cancel and filter success/failure integration
remain in `custom-crop`; these harnesses do not replace physical acceptance.

Transform coverage includes every supported rotation, 4:3/Default/invalid aspect,
locked/unlocked and physical/logical resolution. The fixture invokes the native
size handler synchronously from MPV property writes to ensure the policy is
selected before output notification, and compares identical starting windows
with 720p and 4K sources. `TRANSFORM_PLAYER_SOURCE` selects a previous PlayerCore
source for the regression; `CROP_WINDOW_OUTPUT_DIR` isolates its binary output.


Track/output coverage starts without a transform-setter flag, switches video
between None and 720p/4K/portrait tracks, checks direct MPV video output changes,
and audits audio None/1/2 selection and native volume control visibility. Ordinary
new-file initialization and explicit scale actions remain covered separately.
