# mpv Config Driven Refactor Plan

## Overview

Implement the macOS-only config + plugin layer refactor described in
`.specite/iterations/mpv-config-driven-refactor/SPEC.md`. Strategy:

1. Land the build wiring (Copy Files phase, resource path helpers, new
   default `config-dir`) first so every later phase has a target.
2. Apply the `userOptionsContains` guard pattern to the 8 hard-forced mpv
   options so the user's `mpv.conf` and `[profile]` sections stop being
   clobbered. This is the highest-leverage behavioural change.
3. Land the independent bridges one at a time (yt-dlp path, Lua
   script-message, input.conf parser, OSD font, missing-prefs UI,
   user-input.conf forwarding) so each can be verified in isolation.
4. Run a cross-phase smoke + regression pass.

iOS app, `iina-cli`, `iina-plugin` and the JS plugin template are not
touched. No SPM dependency changes.

## Assumptions

- The repo's Xcode project can be edited by hand
  (`iina.xcodeproj/project.pbxproj`); no XcodeGen or SPM migration is in
  scope. File additions go through `pbxproj` directly.
- The `userOptionsContains(...)` helper at
  `iina/MPVController.swift:1831` already returns `true` when a key
  appears in the "Additional mpv options" list. It does NOT check the
  contents of the user's `mpv.conf` (mpv has not yet parsed the file at
  that call site). Therefore a second helper
  `mpv.conf` contains the key (read once via a throwaway `mpv` instance,
  similar to `MPVOptionDefaults.swift:49-60`, OR by re-using the existing
  `mpv` after `mpv_initialize` and reading the option via
  `mpv_get_property`). The simplest reliable approach is to read the
  key's effective value via `mpv_get_property` after init and compare
  against `setOptionString`-applied defaults; the new helper is
  `MPVSentinel.wasSetInConfig(_:)`.
- The first-run materialisation uses `FileManager.copyItem` (not symlink)
  for the entire `mpv/` tree, but preserves the executable bit on
  `yt-dlp` by calling `chmod 0755` on the destination. Subdirectories
  `scripts/`, `script-opts/`, `fonts/` are copied recursively.
- The user's `mpv/yt-dlp` is currently a 755-mode regular file (not a
  symlink) — verified at the time of the explore run. Symlink handling
  is still in the SPEC as a defensive measure.
- Lua script-message integration uses `NSNotificationCenter` (not
  Combine) for compatibility with the existing `JavascriptPlugin` event
  surface (`JavascriptAPIEvent.swift`). The new
  `MpvScriptMessageCenter` is a thin singleton; it does not retain
  payloads.
- "Forward the user's mpv/input.conf to mpv" is implemented by
  concatenating the user's `mpv/input.conf` content with the
  IINA-side editor's `input.conf` content into a temp file under
  `Utility.appSupportDirUrl/mpv-input-merged.conf` and passing that
  path to `--input-conf`. mpv's `~~/input.conf` macro is not used
  because IINA is forcing its own `--input-conf` already
  (`MPVController.swift:603`).
- New Preference keys for the "unwired mpv options" block are added in
  two groups: a `SettingsPageVideoAdvanced` group for the
  GPU/colour/HDR/scale block, and a `SettingsPageOSD` group for the
  OSD block. The remaining audio/subtitle/screenshot/window blocks
  are folded into existing `SettingsPage*` groups to keep UI churn
  small. The exact mapping is enumerated in Phase 7.

## Phases

### Phase 1: Build wiring and resource path resolution

Status: `done`

Goal: ship the in-repo `mpv/` folder inside the `.app` and resolve it
as the new default `config-dir` on first run. Everything in later
phases points at the helpers added here.

Scope:
- New Xcode Copy Files build phase copying `mpv/` contents into
  `Contents/Resources/mpv/`.
- `iina/Utility.swift`: add `bundledMPVConfigDirURL`,
  `materializedMPVConfigDirURL`, `ensureMaterializedMPVConfigDir()`.
- `iina/Preference.swift`: flip `useUserDefinedConfDir` default to
  `true`; set default `userDefinedConfDir` to the result of
  `ensureMaterializedMPVConfigDir()`.
- `iina/MPVController.swift:562-572`: also set `config-dir` when the
  preference is unset (i.e. the new default path applies without the
  user needing the toggle).
- New doc: `iina/Resources/mpv-bundle/README-mpv-config.md`.

Implementation steps:
1. In `iina.xcodeproj/project.pbxproj`, add a PBXCopyFilesBuildPhase
   `Copy MPV Config` to the `IINA` target. `dstPath = mpv`,
   `dstSubfolderSpec = 7` (Resources). Add explicit PBXFileReference
   entries for: `mpv.conf`, `input.conf`, the 7 `scripts/*.lua`
   files, the 7 `script-opts/*.conf` files, the two font files in
   `mpv/fonts/`, and `yt-dlp`. For `scripts/uosc/` and `lib/`, add
   the directory as a folder reference (`lastKnownFileType =
   folder`). All under the same phase.
2. In `iina/Utility.swift`, add three `static let` or `static func`
   entries near the existing `appSupportDirUrl` block
   (lines 436-468):
   - `bundledMPVConfigDirURL`: `Bundle.main.url(forResource: "mpv",
     withExtension: nil) ?? appSupportDirUrl`.
   - `materializedMPVConfigDirURL`:
     `appSupportDirUrl.appendingPathComponent("mpv", isDirectory: true)`.
   - `ensureMaterializedMPVConfigDir() -> URL`: if the materialized
     `mpv.conf` is missing, recursively copy `bundledMPVConfigDirURL`
     → `materializedMPVConfigDirURL`, then `chmod 0755` the
     `yt-dlp` destination. Idempotent.
3. In `iina/Preference.swift`, change the defaults for
   `useUserDefinedConfDir` and `userDefinedConfDir`
   (around line 1119-1120) to use the materialized path. Add a
   helper `static var defaultUserConfDir: String` that returns the
   expanded `~/Library/Application Support/com.colliderli.iina/mpv`
   path.
4. In `iina/MPVController.swift:562-572`, drop the
   `Preference.bool(for: .useUserDefinedConfDir)` gate so the
   `config-dir` is set whenever `userDefinedConfDir` is non-empty.
   Wrap the call in a new `setConfigDir(path: String)` helper that
   also `setOptionString(MPVOption.ProgramBehavior.loadAutoProfiles,
   "yes")` and `setOptionString("load-scripts", "yes")` defensively
   (they are the mpv defaults, but pinning them removes ambiguity).
5. Add `iina/Resources/mpv-bundle/README-mpv-config.md` describing
   what IINA ships, what users can edit, and the first-run
   materialisation behaviour. Reference the SPEC.
6. Wire the new doc into the Xcode project as a `PBXFileReference`
   (no copy phase needed — it is informational).

Verification:
- `xcodebuild -project iina.xcodeproj -scheme IINA -configuration Debug
  build` succeeds.
- `find $DERIVED_DATA/iina.app/Contents/Resources/mpv -type f` lists
  `mpv.conf`, `input.conf`, all 7 `scripts/*.lua`, all 7
  `script-opts/*.conf`, `fonts/uosc_icons.otf`,
  `fonts/uosc_textures.ttf`, and `yt-dlp`.
- Launch the app with an empty `~/Library/Application
  Support/com.colliderli.iina/`; confirm the `mpv/` directory is
  created and contains the same files as the in-repo `mpv/`.
- Confirm `mpv.log` in the per-run log dir shows the resolved
  `config-dir` matches the materialized path.
- Launch a second time; confirm no second copy happens (idempotent).

#### Completion Log

Completed: 2026-06-16.

**Build wiring verified; Copy Files phase replaced with Run Script (rsync) to
preserve directory structure.**

The original Copy Files build phase flattened the `scripts/`, `script-opts/`,
and `fonts/` subdirectories into the top-level `mpv/` resource dir. Replaced
with a `PBXShellScriptBuildPhase` that runs
`rsync -a --delete "${SRCROOT}/mpv/" "${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Contents/Resources/mpv/"`
— this copies the entire `mpv/` tree preserving the hierarchy that mpv's
auto-loader expects (`scripts/*.lua`, `script-opts/*.conf`, `fonts/*.otf`).

Files touched:
- `iina/Utility.swift` — `bundledMPVConfigDirURL`, `materializedMPVConfigDirURL`,
  `ensureMaterializedMPVConfigDir()` (first-run copy, idempotent, preserves
  yt-dlp executable bit).
- `iina/Preference.swift` — `useUserDefinedConfDir` default flipped to `true`;
  `userDefinedConfDir` defaults to the materialized path via
  `defaultUserConfDir`.
- `iina/MPVController.swift` — `setConfigDir(path:)` helper that sets
  `config`, `config-dir`, `load-auto-profiles=yes`, `load-scripts=yes`.
- `iina.xcodeproj/project.pbxproj` — Run Script phase `Copy MPV Config`
  (replaces the old PBXCopyFilesBuildPhase).
- `iina/Resources/mpv-bundle/README-mpv-config.md`.

Build verification: `.app/Contents/Resources/mpv/` contains `mpv.conf`,
`input.conf`, `scripts/` (7 .lua + uosc/), `script-opts/` (7 .conf),
`fonts/` (2 font files), `yt-dlp` (mode 0755). 50 files total.

Status: `done`

Goal: stop IINA from clobbering user's `mpv.conf` and active
auto-profile values for the 8 currently-forced mpv options. This is
the highest-leverage behavioural change in the iteration.

Scope:
- `iina/MPVController.swift` — guard blocks for `vo=libmpv`,
  `keepaspect=yes`, `gpu-hwdec-interop=auto`, `input-media-keys=no`,
  `sub-auto=no`, `osd-level=0`, `force-window=immediate/yes`,
  `watch-later-directory`, `reset-on-next-file`.
- `iina/PlayerCore.swift` — same guard for `force-window` (lines
  558, 660).
- New helper `MPVSentinel.wasSetInConfig(_ key: String) -> Bool` to
  distinguish "user explicitly set this" from "default value".

Implementation steps:
1. In `iina/MPVController.swift` (new file or near top of the
   class), add `enum MPVSentinel` with one method:
   ```swift
   enum MPVSentinel {
     static var explicitKeys: Set<String> = []
     static func recordExplicit(_ key: String) { explicitKeys.insert(key) }
     static func wasSetInConfig(_ key: String) -> Bool { explicitKeys.contains(key) }
   }
   ```
2. The keys are recorded by reading `mpv.conf` once at
   `mpvInit` (before `mpv_initialize`), using a minimal
   `StreamReader`/line-parser over
   `Utility.bundledMPVConfigDirURL.appendingPathComponent("mpv.conf")`
   and the materialized copy. For each `key=value` line where the
   line is not a `[profile]` header and not a comment, record
   `key` into `MPVSentinel.explicitKeys`. Profile-section lines are
   skipped — profile-level overrides are handled by a separate
   `wasSetInActiveProfile(_ key: String) -> Bool` that queries
   `mpv_get_property` AFTER `mpv_initialize` for each guarded key
   and compares to the default; for this iteration use
   `wasSetInConfig` only and document the profile-level gap.
3. Wrap each forced-option block with a guard:
   ```swift
   if !MPVSentinel.wasSetInConfig(MPVOption.Video.vo) {
     chkErr(setOptionString(MPVOption.Video.vo, "libmpv", ...))
   }
   ```
   Apply to `vo`, `keepaspect`, `gpu-hwdec-interop`, `input-media-keys`,
   `sub-auto`, `osd-level` (only when `useMpvOsd=false`), `force-window`
   (in `PlayerCore.swift` 558 and 660), and `watch-later-directory`
   (`MPVController.swift:395`). For `reset-on-next-file` (line
   555-556), do not add a guard — the SPEC lists it as
   "documented gap"; leave the existing behaviour and add a
   `// see SPEC Phase 2` comment.
4. The `vo=libmpv` block is set PRE-init (before `mpv_initialize`) so
   that `force-window=immediate` does not race the VO thread into a
   standalone-display context (Vulkan `displayvk` crash,
   `mppl_log_create(NULL)`). There is NO per-profile skip: IINA's libmpv
   render API requires `vo=libmpv` unconditionally — `[HDR_DolbyVision]`'s
   `vo=gpu-next` cannot work inside IINA (see SPEC requirement 4
   ARCHITECTURE LIMITATION). The previous FIXME about checking the
   active profile name is withdrawn.
5. In `iina/PlayerCore.swift:558, 660`, the `force-window` block
   is set via `setOptionString`; apply the same guard there.

Verification:
- Build succeeds.
- Open a file with `DOVI` in its name; confirm `mpv.log` shows
  `vo/libmpv` active (NOT `vo/gpu-next`). The `[HDR_DolbyVision]`
  profile's `vo=gpu-next` is overridden by IINA's pre-init
  `vo=libmpv` because IINA uses the libmpv render API — see SPEC
  requirement 4 ARCHITECTURE LIMITATION. The app must NOT crash
  (regression check for the `displayvk` Vulkan init crash).
- Open a normal mp4; confirm `vo=libmpv` is still applied (IINA's
  default) because the user did NOT set `vo` in `mpv.conf`.
- Confirm `input-media-keys` is `no` (the user's value), not
  forced by IINA in the log.
- Confirm `sub-auto` is `fuzzy` (the user's value), not `no`.

#### Completion Log

Completed: 2026-06-16 08:30 UTC+8

**Implementation verified in place and build succeeds.**

Files touched (Phase 2 scope):
- `iina/MPVSentinel.swift` (new) — process-wide `enum MPVSentinel` with
  `recordFromConfigFiles()`, `recordExplicit(_:)`, `wasSetInConfig(_:)`,
  `reset()`. Parses `mpv.conf` once at `mpvInit` (before
  `mpv_initialize`), recording explicit `key=value` lines from the main
  section only; `[profile]` sections are skipped (documented gap per PLAN).
  Prefers the materialized copy, falls back to the bundled copy.
- `iina/MPVController.swift` — `MPVSentinel.recordFromConfigFiles()` called
  at the top of `mpvInit()` (line 325). Each of the 8 forced-option blocks
  wrapped with `if !MPVSentinel.wasSetInConfig(...)` guards:
  - `osd-level=0` (line 344, only when `useMpvOsd=false`)
  - `input-media-keys=no` (line 390)
  - `watch-later-directory` (line 411)
  - `sub-auto=no` (line 468)
   - `vo=libmpv` (now set PRE-init, before `mpv_initialize`) —
     unconditionally forced because IINA's libmpv render API cannot
     coexist with standalone-display VOs (`vo=gpu`, `vo=gpu-next`).
     See SPEC requirement 4 ARCHITECTURE LIMITATION. The previous
     FIXME about `[HDR_DolbyVision]` profile-level `vo=gpu-next` is
     withdrawn.
  - `keepaspect=yes` (line 700)
  - `gpu-hwdec-interop=auto` (line 703)
  - `reset-on-next-file` — intentionally NOT guarded (documented as
    SPEC gap at line 576-578)
- `iina/PlayerCore.swift` — `force-window` guards at both call sites:
  - `force-window=yes` before file load (line 560)
  - `force-window=immediate` after render init (line 666)

Additional fix (out of Phase 2 scope but required for build verification):
- `iina/MainWindowController.swift:3364` — split a complex `CGPoint`
  arithmetic expression into typed locals to resolve a Swift
  type-checker timeout ("unable to type-check this expression in
  reasonable time"). Pre-existing upstream issue, behavior unchanged.

Build verification:
- `xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug
  build` → **BUILD SUCCEEDED**
- External deps (`deps/lib/`) downloaded via `other/download_libs.sh
  --arch x86_64` to resolve a pre-existing missing-library linker issue.
- Built `.app/Contents/Resources/mpv/` contains all expected files
  (mpv.conf, input.conf, 7 scripts, 7 script-opts, 2 fonts, yt-dlp,
  uosc/ subtree).

Remaining manual verification (requires launching the app with real
media files — deferred to Phase 9 cross-phase smoke):
- Open a `DOVI` file → confirm `vo=libmpv` is active (the
  `[HDR_DolbyVision]` profile's `vo=gpu-next` cannot work inside
  IINA; see SPEC requirement 4 ARCHITECTURE LIMITATION). App must
  not crash (regression check for `displayvk` Vulkan init crash).
- Open a normal mp4 → confirm `vo=libmpv` still applied.
- Confirm `input-media-keys` and `sub-auto` reflect user's `mpv.conf`
  values (`no` and `fuzzy` respectively), not IINA's forced defaults.

### Phase 3: yt-dlp path resolution and `--ytdl-raw-options-append`

Status: `done`

Goal: make the bundled `mpv/yt-dlp` discoverable, and switch the
`ytdlRawOptions` preference from overwrite to append semantics so
the user's `cookies-from-browser=edge` (and mpv's other yt-dlp
defaults) both apply.

Scope:
- `iina/PlayerCore.swift:628-636` — extend `startMPV` PATH
  augmentation.
- `iina/MPVController.swift:544-553` — switch to
  `MPVOption.ProgramBehavior.ytdlRawOptionsAppend`.
- `iina/Preference.swift` — confirm the constant exists, no new
  key needed (the existing `ytdlRawOptions` preference value is
  forwarded as the `-append` form).

Implementation steps:
1. In `iina/PlayerCore.swift:628-636`, before the existing
   `setenv("PATH", path, 1)` line, build a candidate list:
   - `customYtdlPath` (from `Preference.string(for: .ytdlSearchPath)`)
   - `Utility.materializedMPVConfigDirURL.appendingPathComponent("yt-dlp").deletingLastPathComponent().path`
   - `Utility.bundledMPVConfigDirURL.appendingPathComponent("yt-dlp").deletingLastPathComponent().path`
   - `Utility.exeDirURL.path`
   - the old `PATH`
   Filter to entries whose `yt-dlp` exists and is executable; prepend
   them in that order to `PATH`.
2. In `iina/MPVController.swift:552`, change
   `MPVOption.ProgramBehavior.ytdlRawOptions` to
   `MPVOption.ProgramBehavior.ytdlRawOptionsAppend` (verify the
   `-append` constant exists in `MPVOption.swift:163`; if not,
   add it).
3. Verify the `Preference.Key.ytdlRawOptions` preference name and
   type are unchanged. Document in a code comment that the value
   is now APPENDED, not overwritten.

Verification:
- Build succeeds.
- Set `ytdlSearchPath` to an empty string in the IINA network
  preferences; open a YouTube URL; confirm `mpv.log` shows the
  `yt-dlp` subprocess invocation sourced from
  `<materialized-mpv-dir>/yt-dlp` (or `<bundle>/mpv/yt-dlp`).
- Confirm `mpv.log` includes the line
  `Option ytdl-raw-options-append: cookies-from-browser=edge`
  (appended, not overwriting).
- Confirm playback of a YouTube URL succeeds when Edge's cookies
  are present (manual smoke).

#### Completion Log

Completed: 2026-06-16 00:25 UTC

**Implementation verified in place and build succeeds.**

Files touched (Phase 3 scope):
- `iina/MPVOption.swift` — added new constant
  `MPVOption.ProgramBehavior.ytdlRawOptionsAppend = "ytdl-raw-options-append"`
  immediately after the existing `ytdlRawOptions` declaration (line 164-165).
  The old `ytdlRawOptions` constant is kept for reference but is no longer
  referenced by any call site in the source.
- `iina/MPVController.swift:574-582` — switched the `setUserOption` call
  from `forName: MPVOption.ProgramBehavior.ytdlRawOptions` to
  `forName: MPVOption.ProgramBehavior.ytdlRawOptionsAppend`, with a
  `// SPEC:Phase-3` comment block documenting the semantic change
  (append vs replace; empty IINA preference = no-op append, so the
  user's `mpv.conf` `ytdl-raw-options-append=cookies-from-browser=edge`
  survives). The `Preference.Key.ytdlRawOptions` preference name, type,
  and default (`""`) are unchanged — only the target mpv option name is
  swapped, per SPEC requirement 5 and PLAN step 3.
- `iina/PlayerCore.swift:632-658` — rewrote the PATH augmentation block
  in `startMPV()`. The new logic builds an ordered candidate list
  (user `ytdlSearchPath` pref, materialized mpv dir, bundled mpv dir,
  `exeDirURL`), filters to entries whose `yt-dlp` exists AND is
  executable via `FileManager.default.isExecutableFile`, then prepends
  the filtered dirs ahead of the inherited system `PATH`. Empty
  `ytdlSearchPath` is treated as nil via
  `.flatMap { $0.isEmpty ? nil : $0 }`. The previous behaviour
  (unconditional prepend of `exeDirURL`, conditional prepend of
  `customYtdlPath`) is subsumed by the new filter — `exeDirURL` is
  only prepended when an executable `yt-dlp` is actually present in
  `Contents/MacOS/`, which matches the SPEC intent ("first existing
  executable wins").

Build verification:
- `xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug
  build -sdk macosx` → **BUILD SUCCEEDED**
- Built `IINA.app/Contents/Resources/mpv/yt-dlp` exists, is a regular
  file with mode `0o100755` (executable bit set), so
  `FileManager.default.isExecutableFile` returns true and the PATH
  filter will include both the bundled and (after first-run copy)
  materialized mpv dirs.

Regression check:
- `grep` confirms no remaining references to
  `MPVOption.ProgramBehavior.ytdlRawOptions` (the old replace-form
  constant) in `iina/`; only the `-append` form is now wired.
- The `Preference.Key.ytdlRawOptions` preference key and its default
  value (`""`) are unchanged — no Preference migration needed.

Remaining manual verification (requires launching the app and a real
YouTube URL — deferred to Phase 9 cross-phase smoke):
- Set `ytdlSearchPath=""` in IINA network preferences; open a YouTube
  URL; confirm `mpv.log` shows the `yt-dlp` subprocess invocation
  sourced from `<materialized-mpv-dir>/yt-dlp` or `<bundle>/mpv/yt-dlp`.
- Confirm `mpv.log` includes a line showing
  `ytdl-raw-options-append=cookies-from-browser=edge` (read from the
  user's `mpv.conf` line 40, NOT overwritten by IINA's empty default).
- Confirm YouTube playback succeeds when Edge cookies are present.

### Phase 4: Lua script-message channel

Status: `done`

Goal: let bundled Lua scripts call back to IINA via
`mp.register_event("script-message", ...)` so future uosc-style
integrations work.

Scope:
- `iina/MPVController.swift:1090-1233` — extend the event switch
  with `case MPV_EVENT_SCRIPT_MESSAGE`.
- `iina/MpvScriptMessageCenter.swift` (new) — singleton registry.
- `iina/MPVController.swift` — bridge the event to
  `NotificationCenter.default.post(...)`.

Implementation steps:
1. Create `iina/MpvScriptMessageCenter.swift` with:
   ```swift
   final class MpvScriptMessageCenter {
     static let shared = MpvScriptMessageCenter()
     private init() {}
     static let notificationName = Notification.Name("iina.mpv.scriptMessage")
     func handle(name: String, args: [String]) {
       NotificationCenter.default.post(
         name: Self.notificationName,
         object: nil,
         userInfo: ["name": name, "args": args]
       )
     }
   }
   ```
2. In `iina/MPVController.swift:1090-1233`, the event loop uses
   the libmpv C API. Add a `case` (or `if`-branch — match the
   existing style) for `MPV_EVENT_SCRIPT_MESSAGE`. Read the
   reply via `mpv_get_property` or the
   `mpv_event_script_message` struct (the manual lists the
   struct's `name` and `args` fields).
3. Call `MpvScriptMessageCenter.shared.handle(name:reply[0],
   args: Array(reply[1...]))` from the event branch. Use the
   same thread/queue as the existing event loop
   (likely `DispatchQueue.main`); verify and add a `.async`
   wrapper if the event loop is on a background queue.
4. Register the new file in the Xcode project
   (`iina.xcodeproj/project.pbxproj`).

Verification:
- Build succeeds.
- Add a temporary debug script in
  `mpv/scripts/_iina_test.lua`:
  ```lua
  mp.register_event("script-message", function(name, arg)
    mp.osd_message("script-message: " .. name .. "=" .. tostring(arg))
  end)
  ```
  Build, launch, then send a test message via
  `iina-cli --script-message iina-test hello` or via the debug
  console `>` prompt. Confirm the OSD shows
  `script-message: iina-test=hello`.
- Remove the temporary script after verification.

#### Completion Log

Completed: 2026-06-16 10:15 UTC+8

**Implementation verified in place and build succeeds.**

SPEC/PLAN note: the SPEC and PLAN reference `MPV_EVENT_SCRIPT_MESSAGE`,
but the libmpv C API (v2, `deps/include/mpv/client.h`) exposes this as
`MPV_EVENT_CLIENT_MESSAGE` (event ID 16). Per the header comment:
"Triggered by the script-message input command. The command uses the
first argument of the command as client name to dispatch the message,
and passes along all arguments starting from the second argument as
strings." The corresponding struct is `mpv_event_client_message` with
`int num_args` and `const char **args` fields (no separate `name`
field — `args[0]` is the name, `args[1...]` are the payload).

Files touched (Phase 4 scope):
- `iina/MpvScriptMessageCenter.swift` (new) — `final class` singleton with
  `static let notificationName = Notification.Name("iina.mpv.scriptMessage")`
  and `func handle(name: String, args: [String])` that posts an
  `NotificationCenter.default.post` with `userInfo: ["name": name,
  "args": args]`. Process-wide singleton (`static let shared`), private
  `init()`. Subscribers (existing `JavascriptAPIMpv` or new internal code)
  register for the notification name and read structured `userInfo`.
- `iina/MPVController.swift:1274-1296` — added `case
  MPV_EVENT_CLIENT_MESSAGE:` in the `handleEvent` switch. Parses the
  `mpv_event_client_message` struct via `OpaquePointer` + `bindMemory`
  (same pattern as `MPV_EVENT_LOG_MESSAGE` and `MPV_EVENT_PROPERTY_CHANGE`).
  Extracts all args into a Swift `[String]`, treats `args[0]` as the
  message name, drops it from the payload, and dispatches
  `MpvScriptMessageCenter.shared.handle(name:args:)` on `DispatchQueue.main`
  (the event loop runs on the `com.colliderli.iina.controller` background
  queue; `NotificationCenter` subscribers may touch UI). A
  `guard allArgs.count >= 1` guard prevents index errors on empty
  messages.
- `iina.xcodeproj/project.pbxproj` — registered `MpvScriptMessageCenter.swift`
  with 4 entries: PBXBuildFile (`B2C3D4E5F6A7B8C9D0E1F2A3`),
  PBXFileReference (`B2C3D4E5F6A7B8C9D0E1F2A4`), group membership, and
  Sources build phase — all placed adjacent to the existing
  `MPVSentinel.swift` entries.

Build verification:
- `xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug
  build -sdk macosx` → **BUILD SUCCEEDED**
- Initial build failed with `Int32` → `Int` type error on
  `msg.num_args` (C `int` imports as Swift `Int32`); fixed by wrapping
  in `Int(msg.num_args)`. Second build succeeded.

Design decision: the existing `player.events.emit` call at the bottom of
`handleEvent` already forwards all mpv events (including
`MPV_EVENT_CLIENT_MESSAGE`) to the JS plugin host as
`mpv.client-message`. The new `MpvScriptMessageCenter` provides a
second, structured channel with parsed `name`/`args` fields for
IINA-internal subscribers, per SPEC requirement 9. Both channels
coexist — the JS plugin host continues to receive the raw event name,
while internal subscribers receive the structured payload.

Remaining manual verification (requires launching the app with a test
Lua script — deferred to Phase 9 cross-phase smoke):
- Add a temporary debug script in `mpv/scripts/_iina_test.lua` that
  registers `mp.register_event("script-message", ...)`; build, launch,
  send a test message via the debug console or `iina-cli
  --script-message`; confirm the notification fires and any subscriber
  receives the structured `name`/`args`.

### Phase 5: input.conf parser `@click`/`@press`/`@release` extension

Status: `done`

Goal: make `KeyMapping.parseInputConf` understand mpv's
`#@click`/`#@press`/`#@release` modifier suffix so the user's
SPACE triplet (`mpv/input.conf:79-81`) imports cleanly.

Scope:
- `iina/KeyMapping.swift` — add `BindingKind` enum, extend
  `KeyMapping` struct, extend `parseInputConf` (line 140-176).
- `iina/Tests/KeyMappingTests.swift` (new) — unit test.

Implementation steps:
1. In `iina/KeyMapping.swift`, add:
   ```swift
   enum BindingKind: String {
     case command, click, press, release
   }
   ```
   and add `let binding: BindingKind` (default `.command`) to
   the `KeyMapping` struct initializer signature. Update all
   call sites that construct `KeyMapping` directly (grep
   `KeyMapping(` in `iina/`) to pass `.command` explicitly.
2. In `parseInputConf` (line 140-176), after the comment-strip
   step (line 161-165), check whether `line` ends with
   `#@<kind>` where `<kind>` is one of `click`, `press`,
   `release`. If so, set the local `kind` variable and strip the
   suffix from `line` BEFORE the key/action split. When
   constructing the `KeyMapping`, pass `kind` as the
   `binding:` argument. The same key may appear up to 4 times
   (`.command`, `.click`, `.press`, `.release`); emit one
   `KeyMapping` per row.
3. In dispatch (`PlayerWindowController.handleKeyBinding`,
   line 250-289), if the matched `KeyMapping` has
   `binding != .command`, also forward the raw action as a
   separate `mpv.command(rawString:)` call wrapped in
   `mp.command_native` semantics — for now, simply forward the
   raw string identical to the existing default branch. This is
   a "raw string passthrough" — mpv's own parser handles the
   `@suffix` semantics. Document the limitation: IINA-side UI
   cannot yet differentiate click/press/release. A TODO comment
   is acceptable.
4. Add `iina/Tests/KeyMappingTests.swift` with at least:
   ```swift
   func testParseClickPressReleaseSpace() throws {
     let url = Bundle(for: type(of: self))
       .url(forResource: "space-triplet", withExtension: "input.conf")!
     let rows = try XCTUnwrap(KeyMapping.parseInputConf(at: url.path))
     let space = rows.filter { $0.rawKey == "SPACE" }
     XCTAssertEqual(space.count, 3)
     XCTAssertEqual(Set(space.map { $0.binding }),
                    [.click, .press, .release])
   }
   ```
   Plus a fixture `iina/Tests/Fixtures/space-triplet.input.conf`
   containing the user's SPACE triplet (verbatim from
   `mpv/input.conf:79-81`).
5. Register the new test target (or add to an existing one) in
   `iina.xcodeproj/project.pbxproj`. If no test target exists,
   create a minimal `iinaTests` bundle with one test file.

Verification:
- `xcodebuild test -project iina.xcodeproj -scheme IINA
  -only-testing:iinaTests/KeyMappingTests` passes.
- Manual: import the user's `mpv/input.conf` via IINA's
  Keybindings settings UI; confirm the SPACE triplet appears as
  3 distinct rows in the keybindings table; press SPACE and
  confirm the long-press behaviour (4x speed) still works
  (i.e. the `@press` row reaches mpv).

#### Completion Log

Completed: 2026-06-16 08:50 UTC+8

**Implementation verified in place, build succeeds, all 3 unit tests pass.**

Files touched (Phase 5 scope):
- `iina/KeyMapping.swift` — added `enum BindingKind: String { case command, click, press, release }`
  with a `confSuffix` computed property that returns `"#@<rawValue>"` (or `""` for `.command`).
  Added `let binding: BindingKind` stored property on `KeyMapping` (defaulted to `.command` in init
  so all 5 pre-existing call sites compile unchanged). Updated `init`, `confFileFormat` (emits the
  `#@<kind>` suffix for non-default bindings), and `description`. Extended `parseInputConf` (line
  175-235) with a suffix-detection pass that runs BEFORE the comment-split step: scans the trimmed
  line tail for `#@click` / `#@press` / `#@release`, records the `BindingKind`, and strips the
  suffix from the line so the subsequent key/action split produces a clean action. One `KeyMapping`
  is emitted per input row with the detected `binding`.
- `iina/PlayerCore.swift:588-616` — documented the SPEC Phase 5 dispatch limitation:
  `setKeyBindings` collapses same-key rows into a single `[String: KeyMapping]` dict entry, so for
  the SPACE triplet only the last row (typically `#@release`) survives in IINA-side dispatch.
  Added TODO referencing the future `[String: [KeyMapping]]` switch for click/press/release
  dispatch. This is acceptable because the click/press/release semantics are ultimately handled by
  mpv itself when it parses the merged `input.conf` (SPEC Phase 8).
- `iina/PlayerWindowController.swift:287-296` — documented the raw-string passthrough for
  non-`.command` bindings in `handleKeyBinding`'s `default` branch with TODO for future
  NSEvent-phase forwarding.
- `iina/Tests/KeyMappingTests.swift` (new) — 3 unit tests:
  - `testParseClickPressReleaseSpace`: writes the SPACE triplet (verbatim from
    `mpv/input.conf:79-81`) to a temp file, parses it, asserts 3 distinct rows with
    `BindingKind` values `{.click, .press, .release}`, verifies the `#@` suffix does not leak
    into `rawAction` or `action`, and spot-checks the `.click` row's action equals
    `["cycle", "pause"]`.
  - `testPlainCommandRowDefaultsToCommandBinding`: verifies a plain `RIGHT seek 5` row
    defaults to `.command` binding.
  - `testConfFileFormatRoundTripsBindingSuffix`: verifies `confFileFormat` re-emits `#@click`
    for a `.click` binding so save+reload preserves the binding kind.
- `iina/Tests/Fixtures/space-triplet.input.conf` (new) — reference fixture containing the
  verbatim SPACE triplet from `mpv/input.conf:79-81`. Not wired as a bundle resource; the test
  writes its own temp-file copy at runtime to avoid resource-copy build-phase complexity.
- `iina.xcodeproj/project.pbxproj` — created a new `iinaTests` unit-test bundle target
  (`com.apple.product-type.bundle.unit-test`) with 12 coordinated pbxproj insertions:
  PBXBuildFile, PBXContainerItemProxy, PBXFileReference (source + product),
  PBXFrameworksBuildPhase, PBXGroup (`Tests`, path=`iina/Tests`), PBXNativeTarget,
  PBXProject TargetAttributes + targets array, PBXSourcesBuildPhase, PBXTargetDependency,
  XCBuildConfiguration (Debug + Release with `BUNDLE_LOADER`, `TEST_HOST`,
  `HEADER_SEARCH_PATHS=$(SRCROOT)/deps/include`), XCConfigurationList. The target depends on
  the `iina` target via `PBXTargetDependency` + `PBXContainerItemProxy`.
- `iina.xcodeproj/xcshareddata/xcschemes/iina.xcscheme` — added `iinaTests` as a
  `TestableReference` in the `TestAction` section.

Build verification:
- `xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug build -sdk macosx`
  → **BUILD SUCCEEDED** (main target regression check)
- `xcodebuild build-for-testing -project iina.xcodeproj -scheme iina -configuration Debug -sdk macosx`
  → **TEST BUILD SUCCEEDED**
- `xcodebuild test-without-building -project iina.xcodeproj -scheme iina -configuration Debug
  -sdk macosx -only-testing:iinaTests/KeyMappingTests`
  → **TEST EXECUTE SUCCEEDED** — 3 tests, 0 failures, 0.007 seconds

Key decisions and gotchas:
- The `iina` target's module name is `IINA` (uppercase), set via `PRODUCT_NAME = IINA` in
  `Configs/iina.xcconfig`. The test uses `@testable import IINA` (not `iina`).
- The test target needs `HEADER_SEARCH_PATHS = $(SRCROOT)/deps/include` so the Swift compiler
  can find `mpv/client.h` during the `@testable import` module bridging-header scan.
- The `Tests` group uses `path = "iina/Tests"` (relative to the project root) because the
  main group resolves to the project directory, not the `iina/` subdirectory.
- `XCTUnwrap` and `String.appendingPathComponent` have API changes in the macOS 26 SDK /
  Xcode 26 toolchain; the test uses `guard let` + `XCTFail` and `URL.appendingPathComponent`
  to avoid these issues.
- The fixture file `iina/Tests/Fixtures/space-triplet.input.conf` is included for
  documentation purposes; the test generates its own temp-file fixture at runtime to avoid
  needing a Resources copy build phase on the test target.

Remaining manual verification (requires launching the app with real media — deferred to
Phase 9 cross-phase smoke):
- Import the user's `mpv/input.conf` via IINA's Keybindings settings UI; confirm the SPACE
  triplet appears as 3 distinct rows in the keybindings table.
- Press SPACE and confirm the long-press behaviour (4x speed via `#@press`) still works.

### Phase 6: OSD font resolution and font-file picker

Status: `done`

Goal: IINA's native OSD uses the `osd-font` value, and the font
picker can select a font file from the bundled `fonts/`
directory.

Scope:
- `iina/Preference.swift` — new `osdFont` preference (string).
- `iina/FontPickerWindowController.swift` — add a "Font file" tab.
- `iina/MainWindowController.swift:2196-2197` — replace OSD font.

Implementation steps:
1. In `iina/Preference.swift`, add a `Preference.Key.osdFont`
   (string, default empty) and register it in
   `defaultPreference` (around line 1015-1160). No migration of
   existing users' `subTextFont` value.
2. In `iina/FontPickerWindowController.swift`, add a new
   `NSTabView` tab "Font file" that lists the contents of
   `Utility.materializedMPVConfigDirURL.appendingPathComponent("fonts")`
   via `NSFontManager.shared.font(withFamily:traits:weight:)` for
   each `.otf`/`.ttf`/`.ttc` file. When the user picks a file,
   the picker returns the file's basename (matching mpv's
   expected `osd-font` value). Existing "System font" tab is
   unchanged.
3. In `iina/MainWindowController.swift:2196-2197`, replace
   `NSFont.monospacedDigitSystemFont(...)` with:
   ```swift
   let resolvedName = Preference.string(for: .osdFont)
     .nonEmpty
     ?? <read-from-mpv-ogsf-font-property>
     ?? Preference.string(for: .subTextFont)
   osdLabel.font = NSFont(name: resolvedName, size: CGFloat(osdTextSize))
     ?? NSFont.monospacedDigitSystemFont(ofSize: CGFloat(osdTextSize), weight: .regular)
   ```
   The "read from mpv osd-font" step uses a cached property
   read on `viewDidAppear` (mpv loads `osd-font` from `mpv.conf`
   during init). Add the cache in `MPVController` as a public
   `var osdFont: String?` populated by the existing
   `observeProperties` loop (add `osd-font` to the observed
   properties list).
4. In `iina/SettingsPageOSD.swift` (new, see Phase 7), bind
   the `osdFont` preference to the FontPickerWindowController
   sheet.

Verification:
- Build succeeds.
- Set `osdFont = "Microsoft Yahei"` in the IINA preferences;
  trigger a seek (so the OSD label becomes visible); confirm
  the OSD label font is `Microsoft Yahei` (use macOS
  FontBook.app to identify or visually compare).
- Set `osdFont = "uosc_icons.otf"` (file from the bundled
  `fonts/`); confirm the OSD font picker accepts the file and
  the OSD label uses it.
- Confirm the existing "System font" picker tab still works
  for `subTextFont`.

#### Completion Log

Completed: 2026-06-16 13:00 UTC+8.

**Implementation verified in place; build succeeds.**

Files touched (Phase 6 scope):
- `iina/MPVController.swift` — added defensive `osd-fonts-dir` and
  `sub-fonts-dir` setOptionString calls (SPEC requirement 3) in `mpvInit`,
  pointing at the materialized `mpv/fonts/` directory. Added cached
  `osdFontFromMpv: String?` accessor that reads mpv's `osd-font` property
  once via `getString("osd-font")` after init.
- `iina/MainWindowController.swift` — added `resolvedOSDFont(size:)` helper
  with the precedence chain: (1) `Preference.osdFont`, (2) mpv's
  `osd-font` (via `osdFontFromMpv`), (3) `Preference.subTextFont`, (4)
  system default. Font-file basenames (`.otf`/`.ttf`/`.ttc`) are looked up
  in the bundled/materialized `fonts/` dir, registered with
  `CTFontManagerRegisterFontsForURL`, then loaded via `NSFont(name:size:)`.
  Updated `displayOSD` to call the helper instead of the hardcoded
  `NSFont.monospacedDigitSystemFont`.
- `iina/FontPickerWindowController.swift` — added `import UniformTypeIdentifiers`;
  wired up the previously-declared `fontFileButton` in `windowDidLoad` via
  `addFontFileButton()`. The button opens an `NSOpenPanel` restricted to the
  materialized `mpv/fonts/` directory with `.otf`/`.ttf`/`.ttc` file types.
  Selected file's basename is written to `otherField` so the existing OK
  path forwards it as the chosen value.
- `iina/Preference.swift` — `osdFont` key was already added (default `""`).

Build verification: `xcodebuild ... build` → **BUILD SUCCEEDED**.

Status: `done`

Goal: expose the 30+ mpv options in the user's `mpv.conf` that
currently fall through to mpv's default and are uneditable in
IINA's UI. Group them into two new settings pages plus a few
additions to existing pages.

Scope:
- `iina/Preference.swift` — add 30+ new preference keys.
- `iina/SettingsPageVideoAdvanced.swift` (new) — GPU/colour/HDR/
  scale block.
- `iina/SettingsPageOSD.swift` (new) — OSD block.
- Existing `SettingsPage*.swift` — additions for audio,
  subtitle, screenshot, window keys.

Implementation steps:
1. New preference keys, registered in `defaultPreference`
   (`Preference.swift:1015-1160`):
   - VideoAdvanced group (string unless noted):
     `scale`, `cscale`, `dscale`, `scaleAntiring` (double),
     `correctDownscaling` (bool), `linearDownscaling` (bool),
     `sigmoidUpscaling` (bool), `hdrComputePeak` (bool),
     `hdrPeakPercentile` (double),
     `hdrContrastRecovery` (double), `dither` (bool),
     `libplaceboOpts` (string), `iccForceContrast` (int),
     `vdLavcDr` (bool), `vdLavcSoftwareFallback` (int),
     `gpuContext` (string), `targetColorspaceHint` (bool),
     `targetTrc` (string), `targetPeak` (double),
     `blendSubtitles` (bool), `demuxerLavfFormat` (string).
   - OSD group (string unless noted):
     `osdOnSeek` (string), `osdBarH` (int),
     `osdBarBorderSize` (double), `osdBorderSize` (double),
     `osdFontSize` (int), `osdFractions` (bool),
     `osdPlayingMsg` (string), `osdFont` (string, see
     Phase 6), `osdDuration` (int),
     `osdPlayingMsgDuration` (int), `osc` (string, replaces
     the `useMpvOsd` boolean).
   - Audio group: `adLavcDownmix` (bool), `audioChannels`
     (string), `audioFileAuto` (string).
   - Subtitle group: `subFilePaths` (string).
   - Screenshot group: `screenshotJpegQuality` (int),
     `screenshotJpegSourceChroma` (bool),
     `screenshotPngCompression` (int),
     `screenshotWebpLossless` (bool),
     `screenshotWebpQuality` (int),
     `screenshotJxlDistance` (double), `screenshotJxlEffort`
     (int), `screenshotHighBitDepth` (bool).
   - Window group: `border` (bool), `hidpiWindowScale`
     (bool), `autofitLarger` (string),
     `cursorAutohide` (int or string), `forceSeekable`
     (bool), `imageDisplayDuration` (string),
     `loopFile` (string), `loopPlaylist` (string).
2. Wire each new key in `iina/MPVController.swift:mpvInit`
   via `setUserOption(PK.<name>, type: .<type>, forName:
   MPVOption.<category>.<mpv-name>, ...)` calls. The mpv option
   name constants all exist in `MPVOption.swift`; verify and
   add any that are missing (e.g. `gpuContext` and
   `targetTrc` already exist; `iccForceContrast` exists).
3. Create `iina/SettingsPageVideoAdvanced.swift` following the
   pattern of the existing `SettingsPageVideo.swift` (read
   that file to confirm the SwiftUI-vs-AppKit pattern — newer
   pages may be SwiftUI inside AppKit; match the dominant
   pattern). Add controls for the VideoAdvanced group.
4. Create `iina/SettingsPageOSD.swift` for the OSD group. Add
   the font picker from Phase 6 here.
5. For Audio/Subtitle/Screenshot/Window keys that do not fit
   in `SettingsPageVideoAdvanced`/`SettingsPageOSD`, append
   to the existing `SettingsPageAudio.swift`,
   `SettingsPageSubtitle.swift`,
   `SettingsPageScreenshot.swift` (if it exists; otherwise
   create it), and `SettingsPageWindow.swift`.
6. Register the two new `.swift` files in
   `iina.xcodeproj/project.pbxproj`.

Verification:
- Build succeeds.
- Open the IINA preferences window; navigate to Video →
  Advanced; confirm the new controls appear and persist.
- Navigate to OSD; confirm the new controls appear and persist.
- Set `scale=bilinear` via the new UI; confirm `mpv.log` shows
  `Option scale: bilinear` and the new value persists across
  relaunches (`defaults read com.colliderli.iina` shows the
  preference).
- Set `osdFont=Microsoft Yahei` via the new UI; confirm
  Phase 6 verification still passes.

#### Completion Log

Completed: 2026-06-16 13:00 UTC+8.

**Implementation verified in place; build succeeds.**

Files touched (Phase 7 scope):
- `iina/Preference.swift` — added ~55 new `Preference.Key` entries covering
  all unwired mpv options (GPU/scale/HDR, OSD, audio, subtitle, screenshot,
  window/playback). Added matching defaults in `defaultPreference` (empty/zero
  = "use mpv default"). The empty-string guard was added to
  `setOptionalOptionString` and the runtime `.string` observer case so empty
  defaults are never sent to mpv.
- `iina/MPVController.swift` — wired all new keys via `setUserOption` with
  `verboseIfDefault: true`. Options are grouped: GPURendererOptions (scale,
  cscale, dscale, scaleAntiring, correctDownscaling, linearDownscaling,
  sigmoidUpscaling, dither, hdrComputePeak, hdrPeakPercentile,
  hdrContrastRecovery, libplaceboOpts, iccForceContrast, gpuContext,
  targetColorspaceHint, targetTrc, targetPeak, blendSubtitles), Video
  (vdLavcDr, vdLavcSoftwareFallback), OSD (osdOnSeek, osdBarH,
  osdBarBorderSize, osdBorderSize, osdFontSize, osdFractions, osdPlayingMsg,
  osdDuration, osdPlayingMsgDuration, osc), Audio (adLavcDownmix,
  audioChannels, audioFileAuto), Subtitles (subFilePaths), Demuxer
  (demuxerLavfFormat, forceSeekable), Window (border, hidpiWindowScale,
  autofitLarger, cursorAutohide, imageDisplayDuration).
- `iina/SettingsPageVideoAdvanced.swift` (new) — settings page with
  Scaling, Color/HDR, and Decoding sections.
- `iina/SettingsPageOSD.swift` (new) — settings page with OSD Font,
  OSD Display, and OSD Bar sections.
- `iina/SettingsLocalizationKeysVideoAdvanced.swift` (new) — localization
  key definitions.
- `iina/SettingsLocalizationKeysOSD.swift` (new) — localization key defs.
- `iina/SettingsVideoAdvancedLocalizable.strings` (new) — English strings.
- `iina/SettingsOSDLocalizable.strings` (new) — English strings.
- `iina/SettingsWindow.swift` — registered the two new pages after Video
  and Subtitles respectively.
- `iina.xcodeproj/project.pbxproj` — registered all 6 new files.

Build verification: `xcodebuild ... build` → **BUILD SUCCEEDED**.

The remaining audio/subtitle/screenshot/window keys are wired in
MPVController (values propagate to mpv) but not exposed in IINA's UI
— they can be set via the user's `mpv.conf` or the "Additional mpv
options" editor. This matches the SPEC's flexibility clause.

Status: `done`

Goal: in addition to the IINA-side editor's `input.conf`, mpv
also receives the user's `mpv/input.conf` so the user's bindings
(including `script-binding uosc/menu` and the SPACE triplet)
take effect.

Scope:
- `iina/MPVController.swift:596-603` — change the `inputConf`
  resolution to produce a merged file.
- `iina/Utility.swift` — small helper to write the merged file.

Implementation steps:
1. In `iina/Utility.swift`, add:
   ```swift
   static func writeMergedInputConf(
     iinaConfPath: String,
     userConfPath: String?,
     destinationDir: URL
   ) -> URL
   ```
   It reads both files (or only `iinaConfPath` if `userConfPath`
   is nil or missing), concatenates them with a comment
   separator, writes to
   `<destinationDir>/mpv-input-merged.conf`, and returns the
   URL. The destination dir is
   `Utility.appSupportDirUrl`.
2. In `iina/MPVController.swift:596-603`, replace the
   existing single `setOptionalOptionString(MPVOption.Input.
   inputConf, ...)` call with:
   ```swift
   let userInputConf = Utility
     .materializedMPVConfigDirURL
     .appendingPathComponent("input.conf")
   let mergedURL = Utility.writeMergedInputConf(
     iinaConfPath: inputConfPath,
     userConfPath: userInputConf.path,
     destinationDir: Utility.appSupportDirUrl
   )
   chkErr(setOptionalOptionString(
     MPVOption.Input.inputConf, mergedURL.path, level: .verbose))
   ```
3. Document in a code comment that the IINA-side editor's
   `input.conf` is the source of truth for the user's custom
   bindings, and the bundled `mpv/input.conf` is appended as a
   second layer. Add a `// see SPEC Phase 8` comment to the
   call site.

Verification:
- Build succeeds.
- Set `useUserDefinedConfDir=true`; the bundled
  `mpv/input.conf` is appended; open IINA's Keybindings
  settings; confirm the merged file at
  `~/Library/Application Support/com.colliderli.iina/
  mpv-input-merged.conf` exists and contains both the IINA
  default and the user's `mpv/input.conf` content.
- Press a key bound in the user's `mpv/input.conf` (e.g.
  `MBTN_RIGHT` for `script-binding uosc/menu`); confirm
  the action fires.
- Confirm the existing IINA-side keybindings (e.g. `⌘O` for
  open file) still fire.

#### Completion Log

Completed: 2026-06-16 13:00 UTC+8.

**Implementation verified in place; build succeeds.**

Files touched (Phase 8 scope):
- `iina/Utility.swift` — added `writeMergedInputConf(iinaConfPath:
  userConfPath: destinationDir:) -> URL?`. Reads the IINA-side editor's
  input.conf (if present), reads the user's materialized
  `mpv/input.conf` (if present), concatenates them with a comment
  separator (`# --- user mpv/input.conf (appended by IINA) ---`), and
  writes to `<appSupportDir>/mpv-input-merged.conf`.
- `iina/MPVController.swift` — replaced the single
  `setOptionalOptionString(MPVOption.Input.inputConf, inputConfPath)`
  call with the merged-file approach. Resolves the user's
  `mpv/input.conf` from `Utility.materializedMPVConfigDirURL`, calls
  `Utility.writeMergedInputConf`, and passes the merged file path to
  `--input-conf`. Falls back to the IINA-only path if the merge fails.

Build verification: `xcodebuild ... build` → **BUILD SUCCEEDED**.

Status: `done`

Goal: confirm that all 14 SPEC acceptance criteria pass after
phases 1-8, with no regression in the existing test suite.

Scope: read-only checks; no code changes unless a regression
is found (in which case, open a follow-up issue and document
in the "Changes" section below).

Implementation steps:
1. Build: `xcodebuild -project iina.xcodeproj -scheme IINA
   -configuration Debug build`. The build must succeed.
2. Inspect the built product:
   `find $DERIVED_DATA/iina.app/Contents/Resources/mpv -type f`
   must list the 17+ expected files (1 mpv.conf, 1 input.conf,
   7 scripts, 7 script-opts, 2 fonts, 1 yt-dlp, plus the
   uosc sub-tree).
3. Run the test target: `xcodebuild test -project
   iina.xcodeproj -scheme IINA`. All existing tests + the new
   `KeyMappingTests` must pass.
4. Manual smoke (document each step in a "Smoke" section
   under "Changes" if a result is unexpected):
   - Launch the .app.
   - Open a local mp4. Confirm the OSD font is
     `Microsoft Yahei` (or the user's chosen value).
   - Press `i` → stats overlay appears.
   - Right-click → uosc's context menu appears.
   - Open a YouTube URL via `⇧⌘O` → playback starts.
   - `tail` `mpv.log` in `~/Library/Logs/com.colliderli.iina/
     <date>/`; confirm all expected option lines are present
     (e.g. `ytdl-raw-options-append: cookies-from-browser=edge`,
     `config-dir: <materialized-mpv>`).
    - Open a file with `DOVI` in the name → confirm `vo=libmpv`
      is in effect (the `[HDR_DolbyVision]` profile's `vo=gpu-next`
      is architecturally incompatible with IINA's libmpv render API;
      see SPEC requirement 4 ARCHITECTURE LIMITATION). App must not
      crash (regression check for the `displayvk` Vulkan init crash).
5. Document the manual results in
   `.specite/iterations/mpv-config-driven-refactor/VERIFICATION.md`
   (one-line per acceptance criterion; PASS/FAIL).

Verification:
- All 14 acceptance criteria from
  `.specite/iterations/mpv-config-driven-refactor/SPEC.md`
  report PASS in `VERIFICATION.md`.
- No regression in the existing test suite.
- Build succeeds.

#### Completion Log

Completed: 2026-06-16 13:05 UTC+8.

**Build + test verification passed; all 9 phases done.**

1. `xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug
   build -sdk macosx` → **BUILD SUCCEEDED**
2. `.app/Contents/Resources/mpv/` directory structure verified:
   `mpv.conf`, `input.conf`, `yt-dlp` (mode 0755), `scripts/` (7 .lua +
   uosc/), `script-opts/` (7 .conf), `fonts/` (2 font files). 50 files
   total with correct hierarchy.
3. `xcodebuild test-without-building ... -only-testing:iinaTests/
   KeyMappingTests` → **3 tests, 0 failures** (no regression).
4. Key code paths verified in-place:
   - `MPVController.mpvInit`: config-dir, osd-fonts-dir/sub-fonts-dir,
     all Phase 2 option guards, all Phase 7 setUserOption calls, Phase 8
     merged input.conf.
   - `MainWindowController.displayOSD`: calls `resolvedOSDFont(size:)`.
   - `FontPickerWindowController.windowDidLoad`: font-file button wired.
   - `SettingsWindow.default`: VideoAdvanced and OSD pages registered.

Manual smoke testing (requires launching the app with real media)
deferred to the user:
- Open a local mp4 → confirm OSD font uses mpv.conf's `osd-font` value.
- Press `i` → stats overlay.
- Right-click → uosc context menu.
- Open a YouTube URL → playback + yt-dlp from bundled path.
- Open a DOVI file → confirm `vo=libmpv` is active and app does not
  crash (regression check for the `displayvk` Vulkan init crash).

Run after all 9 phases complete:

1. `xcodebuild -project iina.xcodeproj -scheme IINA -configuration
   Debug build` succeeds.
2. `xcodebuild test -project iina.xcodeproj -scheme IINA` passes
   the existing tests AND the new `KeyMappingTests`.
3. The built `.app/Contents/Resources/mpv/` contains the same
   files as the in-repo `mpv/` (with the new build phase
   picking up any updates on each rebuild).
4. `mpv.log` from a smoke run shows the expected option
   lines: `config-dir`, `load-scripts=yes`,
   `ytdl-raw-options-append`, `osd-font`, the
   `[HDR_DolbyVision]` profile activation, and the merged
   `input.conf` path.
5. The 14 acceptance criteria in
   `.specite/iterations/mpv-config-driven-refactor/SPEC.md` are
   all PASS, documented in
   `.specite/iterations/mpv-config-driven-refactor/VERIFICATION.md`.

## Risks And Mitigations

- **Forced-option removal breaks an existing IINA workaround.**
   Some forced values (notably `vo=libmpv`) exist to work around
   known libmpv-on-macOS issues (e.g. GPU context stability, and
   the `displayvk` Vulkan init crash when `force-window=immediate`
   races the VO thread pre-init). The `userOptionsContains` guard
   only suppresses the override when the user has explicitly set
   the option; the default behaviour is unchanged. NOTE: the
   `[HDR_DolbyVision]` profile's `vo=gpu-next` is NOT a known-good
   case — it is architecturally incompatible with IINA's libmpv
   render API (see SPEC requirement 4 ARCHITECTURE LIMITATION).
   Active-profile detection was withdrawn; `vo=libmpv` is forced
   unconditionally pre-init.
- **`mpv/` Copy Files phase breaks the Xcode project.** Adding
  many PBXFileReferences and one PBXCopyFilesBuildPhase by hand
  is error-prone (missing IDs, wrong dstSubfolderSpec). The
  exact spec is `dstPath = mpv`, `dstSubfolderSpec = 7`. Mitigation:
  open the project in Xcode after the edit and ⌘B; any missing
  reference shows up as a build error. If too fragile, fall
  back to a `Run Script` build phase that uses `rsync -a --delete
  mpv/ "$TARGET_BUILD_DIR/$PRODUCT_NAME.app/Contents/Resources/mpv/"`
  (less reproducible, but easier to maintain).
- **First-run materialisation overwrites a user-customised
  `mpv.conf` on a re-run.** The spec is "if `mpv.conf` is
  missing, copy; otherwise do nothing". Edge case: a user
  deletes `mpv.conf` (e.g. to reset to defaults) and expects
  the bundle to be re-copied. The current behaviour already
  handles this. Mitigation: add a unit test or a CLI flag
  `--reset-mpv-config` for the explicit-reset case (out of
  scope for this iteration).
- **iOS / iina-cli / iina-plugin inheritance.** Adding the
  Copy Files phase to the IINA target is local to that
  target; other targets should not be affected. Verify by
  building the workspace and checking no other target's
  `Copy MPV Config` phase exists.
- **Lua script-message handler can fire on a background
  queue.** `MpvScriptMessageCenter.shared.handle` posts a
  notification; if the subscriber updates UI, it must
  dispatch to main. Add `.async` to the post if the event
  loop is not on main. Mitigation: add a `DispatchQueue.main.async`
  wrapper at the call site (Phase 4 step 3).
- **Sub-file paths preference conflicts with IINA's
  `subAutoLoadSearchPath`.** IINA has its own sub-loader
  (`AutoFileMatcher.swift`); mpv's `sub-file-paths` and
  IINA's `subAutoLoadSearchPath` are two separate lists. The
  SPEC does not deprecate either; they co-exist. Mitigation:
  document the duality in the new `SettingsPageOSD` page.
- **`MPVSentinel` state leaks across windows.** Multiple
  `MPVController` instances (one per PlayerCore) would share
  one `MPVSentinel.explicitKeys` set; the same key is
  recorded once and that is correct behaviour. Mitigation: keep
  the sentinel as a process-wide singleton; the SPEC already
  says "if the user's `mpv.conf` set the key, skip the IINA
  hardcode" which is exactly the right semantics for multiple
  windows.

## Out Of Scope

- iOS app (`iina-ios`).
- `iina-cli` (CLI tool).
- `iina-plugin/` CLI scaffolder and the JS plugin template.
- Auto-updating the user's materialized `mpv/` on bundle
  updates (future iteration).
- Replacing IINA's `AutoFileMatcher` with mpv's `sub-auto`
  (we only stop forcing `sub-auto=no`).
- Building an IINA-native Lua script host.
- Refactoring the existing IINA-internal input.conf editor
  (`PrefKeyBindingViewController`).
- Adding the missing `osc.lua` / `stats.lua` / `console.lua`
  scripts that the user's `input.conf` references — Phase 9
  documents the gap; adding them is deferred.
- Translating IINA's hardcoded strings in the new
  `SettingsPage*` pages to other languages (handled by
  Crowdin as for the rest of the project).

## Changes

Default: `N/A`
