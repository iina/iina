# Player integration audit — 24 October 2026

## Scope and publication

The audit covers the recent window/OSC, sidebar/input, geometry/Crop/PiP,
source-processing, accent/restart and screenshot-feedback changes. The six
existing drafts are updated in place: #6550, #6551, #6552, #6553, #6555 and
#6541. Each prerequisite fix is carried forward through the cumulative series.
Screenshot feedback now depends on #6552; its incremental comparison is
`codex/ui-video-geometry...codex/screenshot-sound-feedback`.

The upstream branches retain IINA's identity and stock dependency declarations.
The canonical development checkout also receives the applicable corrections,
preserving its branding, custom-engine differences and unrelated working files.
OpenSubtitles/provider implementation, unrelated lifecycle/thumbnail work and
installed applications are outside this publication. Non-English translations
stay local in accordance with CONTRIBUTING.md.

## Confirmed defects and corrections

| Area | Trigger and corrected behavior |
| --- | --- |
| Window/input | Background clicks release native OSC dragging before applying click policy. Key-record notification observers are released correctly. Plugin input replacement/unregistration/expired values and empty overlay hit testing preserve event delivery. |
| Plugin subprocesses | Output hooks execute on main, output collection is synchronized and both streams drain before promise settlement. Unqualified executables resolve without an empty launch path; arguments remain literal. |
| Crop/PiP/fullscreen/music | Editor entry validates the actual video host and player state. Music mode cannot steal an editor-owned view. Fullscreen and PiP settle the prior Crop presentation before acquiring it. Asynchronous PiP preparation revalidates state, generation and host before transfer. |
| Alternate commands | Public video selection/output setters, menu/filter actions, raw shortcuts and plugin mpv writes enforce editor ownership. Structural commands are checked after parsing prefixes, aliases and compound lists; ordinary seeking, pause, volume, frame stepping and nonreplacing playlist edits remain available. Empty mappings are harmless. Already-open video filter windows and deferred filter sheets enforce the same ownership. |
| Player lifetime | Late playback/source commands reject retiring players. Stop finishes before a requested shutdown; background completion remains supported and quit is sent once. Native property/node boundaries reject a nil engine handle. Filter removal validates its index/node and reports rejected writes. |
| Source processing | Repeated scoped EQ edits/reset rebuild the graph when the stock engine lacks the runtime extension. Deferred attachment choices retain their original media generation and do not retain a closed player. |
| Window sizing | The existing resize-timing preference applies once per file generation. Output transforms retain established scale; an explicitly restored restart frame consumes that file's sizing opportunity. |
| Restart | Explicit Settings Restart restores current output processing, source profiles/targets, audio/video membership/order, subtitle roles and external-source identities. Committed Crop is captured after normal editor cleanup. Newly requested initialization/selection policy wins over an older runtime override. Later creates no ordinary-launch handoff. |
| Screenshot | Per-request sound preference and capture correlation survive asynchronous completion. Saved-file feedback does not depend on preview decoding; clipboard-only sound requires a successful copy. Stale/cancelled requests remain silent. |
| Cleanup | Removed proven-unused window/title helpers, legacy LUT methods, old crop-fill asset, a default-only framebuffer argument, inert plugin stubs, unreachable shell code and debugging output. Retained legacy LUT-index migration and comments explaining native/unsafe ownership. |

## Fresh validation

Environment: arm64, macOS 27.0.1, stock libmpv 0.41.0 for the normalized app.
Build-input manifests record 2,404 production files. Build and runtime receipts
are retained locally under `build/player-audit-2026-10-24/` in the development
checkout; no user media or personal profile is included in the public report.

- Release builds: normalized combined app and canonical development checkout.
- Twenty-four additional focused suites passed 22,521 runtime/model assertions,
  plus production wiring and fresh-process persistence checks. They cover native
  editing/layout, shortcuts, OSC/preview, Crop/fullscreen, OSD, window bounds and
  geometry/resize models. These counts are assertions, not independent media
  scenarios or compositor frames.
- Expanded ownership regressions: Crop 629; geometry motion 298; media geometry
  session 68; multitrack/processing 483; PiP 393 lifecycle +36 render geometry
  +10 transaction checks; Crop exit 130 +33; fullscreen six focused groups.
- Alternate-command routing: 280 checks with real bundled libmpv, hidden native
  Crop/Delogo hosts, both shortcut dispatch layers, raw JS APIs and menu actions.
- Filter windows/menu validation: 103 checks, including five mutation paths, stale
  rows and deferred player/media/mode/handle changes.
- Lifecycle/native boundary: 156 +23 checks over all nine PlayerState values,
  deferred/repeated teardown, live idle initialization and invalid filter nodes.
  Fourteen real JavaScriptCore/native checks verify exactly-once hook continuation,
  including retained, reentrant, parallel and released-handle callbacks.
- Real Process/JavaScriptCore output: 60 checks; deferred attachment choosers:
  100; malformed keybinding parsing: 24; finite plugin frames: 15.
- Screenshot: 189 silent checks using the actual state enum, production callback
  and asynchronous request pipeline. Native sound creation/policy is exercised;
  playback is intercepted. No sound was played during these tests.
- Restart: 168 model/bridge checks +23 lifecycle placement checks. Accent policy
  passed 1,728 assertions across four appearances/22 processes; appearance APIs
  passed 51 JavaScriptCore/WKWebView checks. Stock-engine probes verify real
  audio mixes, video graphs, aspect fill and LUT behavior.

Negative controls reproduced the earlier host-constraint crash, music/Crop
ownership corruption, raw-command geometry mutation, stale PiP transfer,
fullscreen ownership overlap, late/repeated engine calls, observer crash,
stock-engine EQ failure and malformed configuration crash. The corresponding
corrected production paths pass their focused regressions.

The full normalized app was run with a unique disposable bundle/profile and
synthetic multitrack media. An actual Settings Restart changed the process and
passed 18 comparisons of path, time/pause, ordinary-window render dimensions,
volume/mute/speed, output filters/geometry, audio mix, video layers and scoped
EQ/aspect. Restart from an active source Crop restored committed output.
Crop-to-PiP returned to rendered ordinary video. A screenshot saved and decoded
successfully; Later followed by normal Quit/launch opened Welcome without a
media/Settings handoff. Final shortcut acceptance exercised raw rotate/aspect and
compound commands, Music Mode and Custom Crop while the editor or PiP owned the
video. Safe mute, ordinary rotation and Music Mode remained available in their
valid states. Native video/None, Music Mode and Delogo menu availability was
checked during Crop. Escape closed the real Crop zoom popup without cancelling
the editor. Expanded results are recorded in the retained runtime receipts.

An apparent native-menu Escape failure was excluded after an independent Cocoa
probe showed that Accessibility expansion had not started native menu tracking.
Real native tracking handled Escape correctly. The speculative observer change
and its synthetic test were removed.

## Reproduction and limits

Focused runners are under `other/tests/`, including `video-editing-command-routing`,
`music-mode-ownership`, `player-lifecycle-guards`, `plugin-process-output`,
`external-track-chooser`, `keybinding-parser`, `custom-crop`, `pip-transition`,
`restart-session` and `screenshot-sound`. Read each README for its real native
boundaries, controlled collaborators and cache/output arguments.

This is bounded evidence, not a guarantee that every player/media/plugin
combination is free of defects. Intel, older supported macOS releases, long-run
resource behavior, arbitrary network/media/plugin combinations and subjective
composited smoothness remain unverified. Native PiP pixels could not be captured;
its ownership/state and ordinary-window return were exercised. General HDR/Dolby
Vision composition, physical full-app color-panel editing, exact fullscreen/Spaces
restoration and WebKit back/forward-cache history return need separate acceptance.
macOS owns PiP placement. The screenshot sound's system asset was checked only on
the test OS. Optional engine patches are documented, not bundled or applied.

Restart restores current media processing; dormant per-playlist processing caches
and arbitrary plugin-owned graphs/windows are not serialized. Missing external
files/LUTs are skipped. Direct external mpv IPC and commands generated inside arbitrary mpv scripts are
outside application command dispatch and cannot inherit its UI-mode restrictions.
