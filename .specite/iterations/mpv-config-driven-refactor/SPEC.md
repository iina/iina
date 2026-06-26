<!-- SUPERSEDED by ui-driven-mpv-options (see .specite/iterations/ui-driven-mpv-options/SPEC.md) -->

**This iteration is superseded.** Do not execute.

# mpv Config Driven Refactor

## Goal

Make IINA's macOS app fully respect the in-repo `mpv/` configuration folder
(`mpv.conf`, `input.conf`, `scripts/`, `script-opts/`, `fonts/`, `yt-dlp`) and
adopt it as the project's default mpv config layout. Eliminate the conflicts
between IINA's hard-coded mpv option overrides and the user-supplied
`mpv.conf`, ship the font assets and `yt-dlp` binary, support the
`ytdl-raw-options-append` semantics the user relies on, and expose the mpv
options the user's config uses but IINA's Preference layer currently drops on
the floor. Scope is the macOS app (`iina/`) only — config + plugin layer.

## Background

- The user placed a personal mpv config bundle (HOOKE007/MPV_lazy style) at
  `/Users/vec/workspace/swift/iina/mpv/`. Contents: `mpv.conf` (132 lines, 6
  `[profile]` sections: `[ontop_playback]`, `[Images]`, `[extension.vpy]`,
  `[HDR_generic]`, `[HDR_DolbyVision]`, `[HDR直通]`), `input.conf` (207 lines,
  heavy `script-binding uosc/*` / `stats/*` / `console/*` use, plus
  `@click`/`@press`/`@release` modifiers on the SPACE key), 7 Lua scripts
  (`autoload.lua`, `inputevent.lua`, `playlistmanager.lua`,
  `quality-menu.lua`, `SmartCopyPaste_II.lua`, `thumbfast.lua`, `uosc/` with
  `main.lua` + `lib/`), 7 `script-opts/*.conf` files, two font assets
  (`uosc_icons.otf`, `uosc_textures.ttf`), and a `yt-dlp` binary.
- IINA embeds mpv via `libmpv`. The single init entry point is
  `MPVController.mpvInit` at `iina/MPVController.swift:318`. mpv's
  `config-dir` is only set when the user enables Advanced → "Use another
  config dir" (`MPVController.swift:562`); default behaviour is mpv's built-in
  `~/.config/mpv`.
- IINA's plugin host is JavaScript-based (WKWebView). `iina-plugin/` at the
  repo root is a CLI scaffolder, not a runtime. Lua scripts run inside mpv
  itself; IINA does not need a Lua host.
- 13 hard-coded mpv option overrides currently fight the user's `mpv.conf`
  (see Explore Map, "What's missing"). The 4 "already works" patterns
  (scripts auto-load, fonts auto-found by uosc, auto-profiles applied by mpv,
  `script-binding` commands forwarded to mpv) are kept as-is.
- Research reports in `.specite/docs/`:
  - `mpv-script-loading.md` — `~~/fonts/`, `~~/scripts/`, `~~/script-opts/`,
    `~~osxbundle/` semantics, recommended libmpv option-setting sequence.
  - `uosc-integration.md` — uosc 5.12.0 install layout, required font
    assets, full list of `script-binding uosc/*` commands.
  - `yt-dlp-options.md` — `--cookies-from-browser BROWSER[+KEYRING][:PROFILE][::CONTAINER]`
    grammar, `Contents/Resources/yt-dlp_macos` bundling pattern,
    `--ytdl-raw-options-append` semantics.
- User-confirmed choices from intake Q&A: iteration name
  `mpv-config-driven-refactor`, scope = config layer + plugin layer, goals =
  full mpv.conf coverage + scripts/script-opts + fonts/yt-dlp path, macOS
  only, "可以直接替换默认路径" (default path can be replaced).

## Requirements

1. **Ship `mpv/` inside the app bundle and adopt it as the new default
   `config-dir`.** Add an Xcode Copy Files build phase that copies
   `mpv/{mpv.conf,input.conf,scripts,script-opts,fonts,yt-dlp}` into
   `Contents/Resources/mpv/`. On first run, if
   `~/Library/Application Support/com.colliderli.iina/mpv/mpv.conf` does not
   exist, materialize the bundled `mpv/` into that directory. Set
   `config-dir` to the materialized path by default. The existing
   `useUserDefinedConfDir` toggle still works and overrides the default.
2. **Stop hard-forcing mpv options that conflict with the user's
   `mpv.conf`.** The 8 currently-forced values are:
   - `vo=libmpv` (`MPVController.swift:664`)
   - `keepaspect=yes` (line 665)
   - `gpu-hwdec-interop=auto` (line 666)
   - `input-media-keys=no` (line 379)
   - `sub-auto=no` (line 448)
   - `osd-level=0` (line 337, only when `useMpvOsd=false`)
   - `force-window=immediate/yes` (`PlayerCore.swift:558, 660`)
   - `watch-later-directory` (line 395)
   - `reset-on-next-file` (line 555)

    Use the same `userOptionsContains` guard pattern that already exists for
    `hwdec-codecs` (`MPVController.swift:1831`): if the user's `mpv.conf` set
    the key, skip the IINA hardcode. For `vo=libmpv`, the forced value is
    applied PRE-init (before `mpv_initialize`) because IINA uses the libmpv
    render API which is incompatible with standalone-display VOs; see
    requirement 4 ARCHITECTURE LIMITATION for why the `[HDR_DolbyVision]`
    profile's `vo=gpu-next` cannot be honoured.
3. **Bundle the two uosc font assets** (`uosc_icons.otf`,
   `uosc_textures.ttf`) into `Contents/Resources/mpv/fonts/`. They live in
   the same `mpv/fonts/` directory as the user's input, so uosc's default
   `~~/fonts/` lookup picks them up. No additional `--osd-fonts-dir` or
   `--sub-fonts-dir` call is strictly required, but add a defensive
   `setOptionString("osd-fonts-dir", "<bundle>/mpv/fonts")` and
   `setOptionString("sub-fonts-dir", "<bundle>/mpv/fonts")` for the
   rare case where the user has no config-dir and runs mpv standalone.
4. **Auto-locate `yt-dlp`** from the bundled `mpv/yt-dlp`. In
   `PlayerCore.startMPV` (`iina/PlayerCore.swift:628-636`), prepend both
   `customYtdlPath` and the resolved `mpv/` dir to `PATH` in this order:
   `customYtdlPath > <materialized-mpv-dir> > <bundle>/mpv > Contents/MacOS`.
5. **Switch to `--ytdl-raw-options-append`.** Map
   `Preference.Key.ytdlRawOptions` to
   `MPVOption.ProgramBehavior.ytdlRawOptionsAppend` (the constant exists
   but is currently unused) at `MPVController.swift:552`. This makes
   `cookies-from-browser=edge` set in the user's `mpv.conf` (or in the
   IINA preference) append to mpv's defaults instead of overwriting them.
6. **Wire missing Preference keys + UI** for the unwired keys in the user's
   `mpv.conf`. These currently fall through to mpv's default and are
   uneditable in IINA's UI: `icc-force-contrast`, `vd-lavc-dr`,
   `vd-lavc-software-fallback`, `scale/cscale/dscale`, `scale-antiring`,
   `correct-downscaling`, `linear-downscaling`, `sigmoid-upscaling`,
   `hdr-compute-peak`, `hdr-peak-percentile`, `hdr-contrast-recovery`,
   `dither`, `libplacebo-opts`, `border`, `hidpi-window-scale`,
   `autofit-larger`, `cursor-autohide`, `osc`, `force-seekable`,
   `ad-lavc-downmix`, `audio-channels`, `audio-file-auto`, `sub-file-paths`,
   the `osd-*` block (`osd-on-seek`, `osd-bar-h`, `osd-bar-border-size`,
   `osd-border-size`, `osd-font-size`, `osd-fractions`, `osd-playing-msg`,
   `osd-font`, `osd-duration`, `osd-playing-msg-duration`),
   `gpu-context`, `target-colorspace-hint`, `target-trc`, `target-peak`,
   `blend-subtitles`, `demuxer-lavf-format`, `image-display-duration`,
   `loop-file`, `loop-playlist`, `icc-profile-auto` (commented out in
   user's config — already wired to `loadIccProfile`).

   For the GPU/colour and HDR block, add a new `SettingsPageVideoAdvanced`
   group. For OSD, add a new `SettingsPageOSD` group. For the rest, either
   add to existing pages or expose them through the existing
   "Additional mpv options" editor in `PrefAdvancedViewController`.
7. **Forward the user's `~~/input.conf` to mpv** in addition to IINA's
   own. The current code passes only one `--input-conf`
   (`MPVController.swift:603`). Use `--input-conf` for the IINA-side
   editor's file and inject the user's `mpv/input.conf` via the
   `--input-conf-append` list-option suffix (if supported by mpv) or
   concatenate them into a temp file under `Utility.appSupportDirUrl`
   before passing to mpv. Document the chosen approach in code.
8. **Extend `KeyMapping.parseInputConf`** (`iina/KeyMapping.swift:140`) to
   recognise mpv's `@click` / `@press` / `@release` modifier suffix.
   The user's `mpv/input.conf:79-81` has:
   ```
   SPACE  cycle pause                                 #@click
   SPACE  no-osd set speed 4; set pause no            #@press
   SPACE  ignore                                      #@release
   ```
   Add a `BindingKind` enum (`.command`, `.click`, `.press`, `.release`)
   to `KeyMapping`, parse the `#@suffix` prefix after the action, and
   store the per-modifier binding on the same `KeyMapping` row.
9. **Handle `MPV_EVENT_SCRIPT_MESSAGE`** in `MPVController.handleEvent`
   (`iina/MPVController.swift:1090`). The current handler does not
   include this case, so Lua scripts calling
   `mp.register_event("script-message", ...)` cannot reach IINA. Add a
   case that posts an `NSNotification.Name("iina.mpv.scriptMessage")`
   with `userInfo: ["name": String, "args": [String]]` (where `args` is
   the JSON-decoded payload or `[]` if absent). Both the existing
   JavaScript plugin host (via `JavascriptAPIMpv`) and a new internal
   `MPVScriptMessageCenter` can subscribe.
10. **Wire `osd-font` to IINA's own OSD.** Replace
    `NSFont.monospacedDigitSystemFont` at
    `MainWindowController.swift:2196-2197` with a font resolved from
    the active `osd-font` (preference OR user's `mpv.conf` value) and,
    for font-file paths, the bundled `fonts/` directory.
11. **OSD font picker** — extend `FontPickerWindowController` to allow
    picking a font *file* (`.otf`/`.ttf`/`.ttc`) from
    `Utility.materializedMPVConfigDirURL/fonts` in addition to a system
    family name. Store the resulting font path or family name in a new
    `Preference.Key.osdFont`.
12. **Document auto-profiles.** No code change is required for
    `[profile]` / `profile-cond` / `profile-restore` — mpv handles them
    natively once `config-dir` is set. Add a section to
    `iina/Resources/mpv-bundle/README-mpv-config.md` so users understand
    that all 6 profiles in the user's `mpv.conf` are honoured.
13. **Do NOT block Lua script loading.** Verify that
    `MPVController.mpvInit` does not call
    `setOptionString("load-scripts", "no")` on the main player mpv
    instance. (`MPVOptionDefaults.swift:55-58` already only disables it
    on the throwaway defaults-query instance, so this is a verification
    step rather than a code change.)
14. **Project hygiene.** The Copy Files build phase must list files
    explicitly (no build-time globbing) so the bundling is reproducible
    across `xcodebuild` and Xcode IDE runs. New `mpv/` files added
    later need an explicit addition to the build phase.

## Acceptance Criteria

1. After building `iina.xcodeproj`, the built `.app/Contents/Resources/mpv/`
   contains `mpv.conf`, `input.conf`, `scripts/`, `script-opts/`, `fonts/`,
   and `yt-dlp` with the same byte contents as the in-repo `mpv/`.
2. On first launch with an empty Application Support dir, IINA materialises
   `~/Library/Application Support/com.colliderli.iina/mpv/` from the bundle
   and the player's `config-dir` resolves to that path. Verify with
   `iina-cli --get-property config-dir` or by reading
   `mpv.log` in the per-run log dir.
3. The user's `mpv.conf` keys are visible to mpv: spot-check `hwdec=auto`,
   `keep-open=yes`, `ytdl=yes`, `volume=80`, `sub-font-size=43`,
   `screenshot-template="~~desktop/MPV-%P-N%n"`. The 6 `[profile]`
   sections parse without warnings in `mpv.log`.
4. ARCHITECTURE LIMITATION (revised): IINA uses the libmpv render API,
   which renders mpv output into IINA's own NSView. This is incompatible
   with standalone-display VOs (`vo=gpu`, `vo=gpu-next`,
   `vo=gpu-next==libplacebo`), which create their own GPU/display context.
   Therefore the `[HDR_DolbyVision]` profile's `vo=gpu-next` CANNOT be
   honoured inside IINA — opening a DOVI file must still use
   `vo=libmpv` (IINA forces it pre-init, see `MPVController.mpvInit`).
   The profile's OTHER keys (`gpu-context=macvk`, `tone-mapping=st2094-40`)
   are harmless under `vo=libmpv` (mpv ignores unused VO options) but have
   no effect. HDR via profile `vo=gpu-next` is out of scope for this
   iteration; a future HDR path would require routing HDR metadata
   through libmpv's render API instead.
5. The `[ontop_playback]` profile activates `ontop=yes` while not paused
   and removes it when paused.
6. Pressing right-mouse over the video area opens uosc's context menu
   (`script-binding uosc/menu` dispatches correctly).
7. Pressing `i` opens the stats overlay, ` `` ` opens the console,
   `DEL` toggles the built-in OSC visibility (assuming
   `osc.lua`/`stats.lua`/`console.lua` are added to `mpv/scripts/` in
   this iteration, otherwise document the gap and add a TODO).
8. yt-dlp is auto-located: opening a YouTube URL plays successfully
   even with `ytdlSearchPath` empty. `mpv.log` shows a `yt-dlp` subprocess
   invocation sourced from the bundled `mpv/yt-dlp`.
9. `--ytdl-raw-options-append=cookies-from-browser=edge` is passed to mpv.
   `mpv.log` shows `ytdl-raw-options-append` in the option list.
10. uosc's icons and shapes render correctly: the right-mouse menu shows
    uosc's icon glyphs (not missing-glyph boxes).
11. A bundled Lua script that registers
    `mp.register_event("script-message", function(n, a) mp.osd_message(n..":"..a) end)`
    receives messages sent via
    `iina-cli --script-message my-event hello` (or the equivalent
    debug command in IINA).
12. The user's `mpv/input.conf:79-81` SPACE triplet (3 lines, the same
    key with `@click`/`@press`/`@release` suffixes) parses into 3 distinct
    `KeyMapping` rows, none dropped. A unit test covers this case.
13. An `osd-font="Microsoft Yahei"` value from the user's `mpv.conf` (or
    a new IINA preference) is used by IINA's native OSD — visible as
    the font family of the OSD label after a seek.
14. After the iteration, the existing IINA test target still passes
    (regression check).

## Scope

- `iina/MPVController.swift` — rewrite forced-option blocks (lines 322–666)
  to use `userOptionsContains` guards; add `MPV_EVENT_SCRIPT_MESSAGE`
  handler; add `osd-fonts-dir` / `sub-fonts-dir` calls; add `scripts` /
  `script-opts` injection (or document the auto-load path); switch
  `ytdlRawOptions` to the `-append` mpv option constant; add config-dir
  resolution to the bundled + materialized path.
- `iina/PlayerCore.swift` — extend `startMPV` (lines 628–636) to prepend
  the bundled `mpv/` and the materialized `mpv/` dir to `PATH` ahead of
  the system `PATH`.
- `iina/PlayerCore.swift` — guard `force-window` setter (lines 558, 660)
  with the `userOptionsContains` pattern.
- `iina/MainWindowController.swift` — replace OSD font (line 2196) with
  a font resolved from `osd-font` and the bundled `fonts/`.
- `iina/KeyMapping.swift` — extend parser (line 140) for
  `@click`/`@press`/`@release`; add `BindingKind` enum.
- `iina/Preference.swift` — add new pref keys for the unwired options
  in requirement 6; change default for `useUserDefinedConfDir` to `true`
  and default `userDefinedConfDir` to the materialized path; add
  `osdFont`.
- `iina/SettingsPage*.swift` — add new groups `SettingsPageVideoAdvanced`
  and `SettingsPageOSD`; expose the new preferences; expose the new font
  picker.
- `iina/FontPickerWindowController.swift` — add a "Font file" tab
  that lists the bundled `fonts/` directory.
- `iina/Utility.swift` — add `bundledMPVConfigDirURL`
  (`Bundle.main.url(forResource: "mpv", withExtension: nil)`) and
  `materializedMPVConfigDirURL`
  (`appSupportDirUrl.appendingPathComponent("mpv")`).
- `iina/MpvScriptMessageCenter.swift` (new) — singleton holding
  `name → [callback]` registry; subscribes to the
  `iina.mpv.scriptMessage` notification.
- `iina.xcodeproj/project.pbxproj` — add Copy Files build phase to
  copy the `mpv/` folder contents into `Contents/Resources/mpv/`.
  Files listed explicitly.
- New `iina/Resources/mpv-bundle/README-mpv-config.md` — what IINA
  ships, how to customise, what is editable via IINA's UI vs requires
  editing the `mpv.conf` directly.
- `iina/Tests/` (if present) — add `KeyMappingTests.swift` covering
  the `@click`/`@press`/`@release` parse case.

## Non-Goals

- iOS/iPadOS (iina-ios) and iina-cli are NOT touched. macOS app only.
- Rewriting IINA's keybinding UI / shortcut panel. We only fix the
  parser and the input-conf forwarding.
- Replacing IINA's `AutoFileMatcher` subtitle auto-loader with mpv's
  `sub-auto`. We just stop forcing `sub-auto=no`; both auto-loaders
  co-existing is acceptable.
- Building an IINA-native Lua script host. `iina-plugin/` stays
  JavaScript-only.
- Auto-updating the user's materialized `mpv/` when the bundled `mpv/`
  changes. First-run copy is enough; subsequent upgrades are out of
  scope (a future iteration can do a non-destructive merge).
- Changing the existing IINA-internal input.conf editor
  (`PrefKeyBindingViewController`).
- Refactoring the iOS SwiftUI app, the CLI, or the plugin template.

## Behavior Details

- **First-run materialisation** (in `Utility.ensureMaterializedMPVConfigDir`):
  1. Compute `materialized = appSupportDirUrl/mpv`.
  2. If `materialized/mpv.conf` does NOT exist, recursively copy
     `bundledMPVConfigDirURL` → `materialized`, preserving symlinks for
     `yt-dlp`. Log the copy.
  3. If `materialized/mpv.conf` exists, do nothing (user has customised).
  4. Return `materialized`.
- **`useUserDefinedConfDir` default**: set to `true`; default
  `userDefinedConfDir` = the result of
  `Utility.ensureMaterializedMPVConfigDir()`. Existing users who have
  never enabled the toggle get the new default on next launch; if they
  want to revert, they can disable the toggle.
- **Option precedence guard**: helper
  `MPVController.shouldForce(_ key: String) -> Bool` returns
  `!userOptionsContains(key) && !activeProfileSet(key)`. Called from
  each forced-option block. The `userOptionsContains` function already
  exists at `MPVController.swift:1831`.
- **OSD font resolution**: precedence is
  (1) `Preference.Key.osdFont`,
  (2) `~~/mpv.conf` `osd-font=...` (read at startup via a tiny mpv
  get-property),
  (3) `Preference.Key.subTextFont`,
  (4) system default. For paths, prefer the bundled `fonts/` if the
  referenced file name is present there.
- **Lua script-message event**: when `MPV_EVENT_SCRIPT_MESSAGE` fires,
  the `name` is the registered message name, and the `args` field is a
  JSON array (mpv's contract). IINA posts an NSNotification; the new
  `MpvScriptMessageCenter` re-broadcasts to registered observers. The
  existing `JavascriptAPIMpv` can subscribe and forward to JS plugins
  without code changes there.
- **`@click`/`@press`/`@release` parser**: split the line on whitespace;
  the action is column 2; if column 2 ends in `#@<kind>`, set the
  `BindingKind` accordingly and strip the suffix. Three `KeyMapping`
  rows are produced for the same raw key.
- **yt-dlp auto-locate**: order
  (1) `Preference.string(for: .ytdlSearchPath)` (if non-empty and file
  exists),
  (2) `<materialized-mpv-dir>/yt-dlp`,
  (3) `<bundle>/mpv/yt-dlp`,
  (4) `Contents/MacOS/yt-dlp`,
  (5) `which yt-dlp` on the system PATH. The first existing executable
  wins. The resulting dir is prepended to `PATH`.
- **`ytdl-raw-options-append`**: new preference
  `Preference.Key.ytdlRawOptionsAppend` (string, default empty). Wired
  via
  `setUserOption(PK.ytdlRawOptionsAppend, type: .string, forName: MPVOption.ProgramBehavior.ytdlRawOptionsAppend, ...)`.
  The existing `ytdlRawOptions` preference is repurposed (or
  deprecated) — only one of them should set the corresponding mpv
  option.
- **Error handling**: if the bundled `mpv/` is missing (developer
  build without the Copy Files phase), IINA logs a warning at startup
  and falls back to mpv's default `~/.config/mpv/`. The app must not
  crash.
- **Symlink handling for `yt-dlp`**: the in-repo `mpv/yt-dlp` may be a
  symlink (per `install.command:56-58`). The Copy Files build phase
  must resolve symlinks at copy time, and the first-run materialisation
  must preserve executable bits.

## Dependencies And Research

- `mpv` (libmpv) — already used; no version bump. The forced-override
  removal in requirement 2 requires care because some values
  (e.g. `vo=libmpv`) exist to work around libmpv issues; the
  `userOptionsContains` guard pattern is the safety net. See
  `.specite/docs/mpv-script-loading.md` for the recommended option
  sequence and the gotchas around `~~osxbundle/` resolution.
- `uosc` 5.12.0 — already present in `mpv/scripts/uosc/`. No new
  dependency. `.specite/docs/uosc-integration.md` lists the
  `script-binding uosc/*` commands; IINA does not need to call any of
  them directly, only forward user keybindings.
- `yt-dlp` 2026.05.22+ — already present in `mpv/yt-dlp`. No new
  dependency. `.specite/docs/yt-dlp-options.md` documents
  `--cookies-from-browser` and the `.app` bundling pattern.
- No Swift Package Manager dependencies change. No new external libs.

## Verification

1. **Build**: `xcodebuild -project iina.xcodeproj -scheme IINA -configuration Debug build`
   (or open in Xcode and ⌘B). Confirm
   `iina.app/Contents/Resources/mpv/{mpv.conf,input.conf,scripts,script-opts,fonts,yt-dlp}`
   exist in the built product.
2. **Smoke run**: launch the .app, open a local video, and confirm:
   - `mpv.log` shows `osd-font` resolved to `Microsoft Yahei` (or the
     user's choice).
   - Pressing `i` opens the stats overlay.
   - The right mouse button opens uosc's context menu.
3. **Auto-profile smoke**: open a file whose name contains `DOVI`.
   Confirm `mp.get_property("vo") == "gpu-next"` (read via `iina-cli
   --get-property vo` or visible in the mpv log line
   `Applying profile HDR_DolbyVision`).
4. **uosc smoke**: open uosc's context menu. The icon glyphs (folder,
   cog, etc.) render correctly — not missing-glyph boxes.
5. **yt-dlp smoke**: open a YouTube URL via `⇧⌘O`. Playback starts.
   `mpv.log` shows the `yt-dlp` subprocess invocation sourced from
   `<bundle>/mpv/yt-dlp`.
6. **`ytdl-raw-options-append` smoke**: `mpv.log` shows
   `ytdl-raw-options-append=cookies-from-browser=edge` in the option
   list.
7. **Sub-message smoke**: add a tiny test Lua script in
   `mpv/scripts/_iina_test.lua` that registers
   `mp.register_event("script-message", function(n,a) mp.osd_message(n..":"..a) end)`.
   From IINA's debug menu (or `iina-cli --script-message iina-test
   hello`), confirm the OSD shows `iina-test:hello`.
8. **Parser smoke**: unit test
   `KeyMappingTests.testParseClickPressReleaseSpace` imports the
   user's `mpv/input.conf` and asserts the SPACE key produces 3
   `KeyMapping` rows with `BindingKind` values `.command`, `.click`,
   `.press`, `.release`. Run via
   `xcodebuild test -project iina.xcodeproj -scheme IINA -only-testing:iinaTests/KeyMappingTests`.
9. **Existing test suite**: run the existing test target and confirm
   no regression.

## Shifts

`N/A`
