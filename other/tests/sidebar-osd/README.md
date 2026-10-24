# Sidebar OSD provenance

Run `bash other/tests/sidebar-osd/run.sh` on macOS. No window, player, renderer or
physical input is opened. Warnings are treated as errors. Source snapshots,
SHA-256 hashes, generated Swift, executable and results are written to
`build/sidebar-osd-tests/`.

The fixture extracts the actual provenance origin/value/locked ledger,
`OSDMessage` cases and setting/preference classification, PlayerCore context and
deferred-origin APIs, and `sendOSD`. It also extracts all four typed MPV setters,
typed-observation bookkeeping filter, native property-value copying,
observation-time origin capture and main-queue wrapper, representative
speed/brightness/mute/audio-delay/hwdec observer branches, and actual
`speedChanged` handling.

The C API is controlled: writes record typed values and can fail or interleave
another write; observations supply native flag/int/double/string buffers and free
them before queued UI delivery. This verifies attribution and copying without
claiming real engine timing. Rendering and unrelated sidebar view updates are
boundaries; retained cache, sync and notification calls are asserted.

Coverage includes direct sidebar versus ordinary commands with the panel open,
deferred mutation and nested context restoration, matching typed/string values,
property prefixes, mismatches and later returns, unrelated property interleaving,
origin capture before delayed delivery, rollback with stale/new tokens, locked
concurrent access, external plugin feedback, errors and playback notifications,
existing disabled/file-loading gates, and Stop between enqueue and delivery.
Typed setter tests assert provenance is recorded before the native write and
that quiet feedback does not skip UI synchronization or asynchronous notifications.
Ordered, coalesced, duplicate, repeated and toggle slider acknowledgements are
tested separately, including failed latest writes retaining an earlier valid
intent. Unobserved graph options and NONE/NODE observations forward native writes
without retaining value-based quiet attribution. The observation-format map is a
controlled representative boundary; filtering itself is extracted production code.

The dedicated `geometry-seek-osd` fixture owns real SEEK/PLAYBACK_RESTART/event
drain ordering. This fixture's direct `.seek` delivery checks establish that
sidebar setting quieting does not classify deliberate progress feedback as a
setting; they do not replace seek-intent/event tests.

Alternate source snapshots can be supplied with `SIDEBAR_OSD_PLAYER_SOURCE`,
`SIDEBAR_OSD_MESSAGE_SOURCE`, `SIDEBAR_OSD_MPV_SOURCE` and a separate
`SIDEBAR_OSD_OUTPUT_DIR` for negative controls without editing production.

Run `bash other/tests/sidebar-osd/commands-run.sh` for the separate bounded
command integration executable. It reuses the fixtures above without changing
their entry or checks, and additionally extracts actual `prepareCommandOSD`,
`makeCArgs`, array/raw `command` overloads, `OSDCommandRouting`, and PlayerCore
seek intent/cancellation policy. Native C command calls copy their input before
returning a controlled status. Checks cover raw and array seek arming, typed
property acknowledgement, ordinary commands while the sidebar remains open,
token-specific failure rollback, mixed raw property/seek failure, and background
main-queue bookkeeping before a simulated resulting observation. Engine event
production and native error reporting remain controlled boundaries; this does
not replace real SEEK/PLAYBACK_RESTART validation.

The command runner accepts the same three source overrides, with separate
`SIDEBAR_OSD_COMMAND_OUTPUT_DIR` (default `build/sidebar-osd-command-tests/`).
`SIDEBAR_OSD_COMMAND_GENERATE_ONLY=1` writes source and hashes without compiling
or running it, for use while an unrelated timing benchmark is active.
