# UI Driven MPV Options

## Goal

Make every option the curated `mpv/mpv.conf` expresses reachable, editable,
and **persisted** through IINA's Preferences UI — without requiring the user
to ship, edit, or even know about an `mpv.conf`. The curated values from the
in-repo `mpv/mpv.conf` are baked into `Preference.swift` as the new defaults,
so a fresh install behaves identically to the curated config. When a power
user *does* bring their own `~/Library/.../mpv/mpv.conf`, it wins on
conflict, and the affected Settings rows display an "Overridden by your
mpv.conf" badge so the precedence is never silent.

This supersedes `mpv-config-driven-refactor` (see Background).

## Background

- **Supersedes `.specite/iterations/mpv-config-driven-refactor/SPEC.md`**
  in place. That iteration's strategy was *config-driven*: bundle the user's
  whole `mpv/` folder as the mpv `config-dir` and stop fighting it. User
  direction for this iteration is the inverse: *UI-driven*. The `mpv/`
  bundle is **no longer shipped as a config-dir**; instead the same option
  values are baked into IINA's own preference defaults and exposed as
  Settings rows. A one-line `SUPERSEDED` banner is prepended to the old
  SPEC so readers are routed here.
- The prior iteration already delivered most of the **scaffolding** this
  iteration builds on (verified by the explore agent):
  - `iina/Preference.swift` already declares ~80 mpv-option keys in the
    "Phase 7" block (lines 184–249), but with **deliberately neutral
    defaults** (empty string / 0 / false) so mpv's own defaults applied.
    This iteration flips those defaults to the curated values.
  - `iina/SettingsPageOSD.swift` and `iina/SettingsPageVideoAdvanced.swift`
    already exist and already bind rows via the `SettingsItem.*` / `.bindTo()`
    pattern. Gaps in row coverage are filled here.
  - `iina/MPVSentinel.swift` already parses `mpv.conf` (main section) and
    exposes `wasSetInConfig(_ key: String) -> Bool` — the exact predicate
    the badge needs. Its known limitation: `[profile]` sections are skipped.
  - `MPVController.setUserOption(...)` at `iina/MPVController.swift:1963` is
    the single chokepoint that reads a `Preference.Key` and forwards it to
    mpv with type handling, logging, and live re-sync.
  - `syncMPVConfigToPreferences()` at `iina/MPVController.swift:835` already
    reflects mpv's effective values back into empty IINA prefs.
  - OSD font resolution (`MainWindowController.resolvedOSDFont`,
    line 2177) already has a 4-tier precedence (pref → mpv → sub font →
    system). KeyMapping `@click`/`@press`/`@release` is already supported
    (`iina/KeyMapping.swift:21,175`).
- The curated source of truth is `mpv/mpv.conf` (132 lines: 59
  non-comment option lines in the main section + 6 `[profile]` sections).
  Profile-section options are applied by mpv's own profile engine and are
  **out of scope** for the coverage table (see Non-Goals).
- Two corrections from research (`.specite/docs/mpv-options-ui-mapping.md`)
  must be honoured:
  1. `vd-lavc-software-fallback` does **not exist** in mpv. The real option
     is `hwdec-software-fallback=<yes|no|N>` (default `3`). The user's
     `mpv.conf` line `vd-lavc-software-fallback=60` is a long-standing typo
     that mpv silently ignores; the new Settings key maps to the correct
     `hwdec-software-fallback`.
  2. `libplacebo-opts preset=` has **three** members: `default|fast|
     high_quality`. There is no `high` global preset.
- User-confirmed intake: name `ui-driven-mpv-options`; supersedes old
  iteration in place; defaults baked into `Preference.swift` (mpv/ folder
  removed from bundle); full mpv.conf coverage required (with coverage
  table); user mpv.conf wins on conflict, surfaced via a per-row badge.

## Requirements

### 1. Bake curated defaults into `Preference.swift`

For every main-section option in `mpv/mpv.conf` that already has a
`Preference.Key`, change the entry in the `defaultPreference` dictionary
(`iina/Preference.swift:1202`) from the neutral value to the curated value
extracted from `mpv/mpv.conf`. Existing users are migrated by bumping a
preferences-version key so the new defaults register (the existing
`register(defaults:)` flow in `AppDelegate.swift:1092` handles this).

### 2. Fill coverage gaps (new keys + rows + wiring)

Every main-section option in `mpv/mpv.conf` must map to a `Preference.Key`,
a Settings row, and a `setUserOption(...)` call. The exploration found these
gaps requiring **new** keys: `hwdecSoftwareFallback` (renamed from the
nonexistent `vd-lavc-software-fallback`), `geometry`, `savePositionOnQuit`,
`inputMediaKeys`, `ytdl`, `ytdlRawOptionsAppend`, `volumeMax`,
`subShadowOffset`, `subColor`, and the full screenshot block
(`screenshotFormat`, `screenshotJpegQuality`, `screenshotJpegSourceChroma`,
`screenshotPngCompression`, `screenshotWebpLossless`, `screenshotWebpQuality`,
`screenshotJxlDistance`, `screenshotJxlEffort`, `screenshotHighBitDepth`,
`screenshotTemplate`). The full mapping is in Behavior Details.

### 3. "Overridden by your mpv.conf" badge

Add a badge/footnote to `SettingsItem.General.makeView`
(`iina/SettingsItem.swift:178`) that is shown when
`MPVSentinel.wasSetInConfig(<mpv-option-name>)` returns true for the row's
bound option. The badge is a small `NSTextField`/tooltip with localized
text "Overridden by your mpv.conf". Each `SettingsItem` row must carry the
mpv option name it binds to (extend the `.bindTo()` chain with an
`.mpvName("...")` accessor or derive it from the key's raw value where the
naming convention is stable).

### 4. Remove the `mpv/` config-dir bundling

Revert the mpv-config-driven Copy Files build phase and the first-run
materialisation (`Utility.ensureMaterializedMPVConfigDir`). Defaults now
live in `Preference.swift`, so there is no bundled `mpv.conf` to materialise.
`MPVSentinel.recordFromConfigFiles()` keeps reading the user's **optional**
`~/Library/Application Support/com.colliderli.iina/mpv/mpv.conf` so the
badge still works when a power user drops one in. If no user mpv.conf is
present, `wasSetInConfig` returns false everywhere → no badges, Settings
values apply cleanly.

### 5. Keep `useUserDefinedConfDir` as an advanced escape hatch

The existing Advanced → "Use another config dir" toggle stays. It defaults
to **off** (revert the prior iteration's `true` default). When a user
points it at a real mpv config-dir, mpv honours it and the badge reflects
the overrides per requirement 3.

### 6. Mark the old SPEC superseded

Prepend a `<!-- SUPERSEDED by ui-driven-mpv-options -->` banner and a
one-line note at the top of
`.specite/iterations/mpv-config-driven-refactor/SPEC.md` pointing readers
to this iteration.

## Acceptance Criteria

1. A clean build (`xcodebuild -project iina.xcodeproj -scheme IINA
   -configuration Debug build`) succeeds and the built `.app` contains **no**
   `Contents/Resources/mpv/` directory (mpv/ bundling removed).
2. On first launch with empty Application Support and **no** user mpv.conf,
   every option in the coverage table (Behavior Details) resolves to the
   curated value from `mpv/mpv.conf`. Verified by reading
   `mpv_property("scale") == "bilinear"`, `...("libplacebo-opts") ==
   "preset=fast"`, `...("osd-font-size") == 40`, `...("hwdec-software-
   fallback") == 60` via `iina-cli --get-property` or the per-run `mpv.log`.
3. No Settings row shows the "Overridden by your mpv.conf" badge in the
   clean-install / no-user-mpv.conf state.
4. Dropping a user `mpv.conf` containing `osd-font-size=99` into
   `~/Library/Application Support/com.colliderli.iina/mpv/` and relaunching
   causes: (a) `osd-font-size` to resolve to `99`, and (b) the OSD-font-size
   Settings row to display the "Overridden by your mpv.conf" badge.
5. **Full coverage**: for each non-comment line in the main section of
   `mpv/mpv.conf`, the coverage table lists a `Preference.Key`, a Settings
   row, and a `setUserOption` call. An automated or manual audit script
   confirms zero unmapped lines.
6. The two research corrections are honoured: the new key is named
   `hwdecSoftwareFallback` (not `vdLavcSoftwareFallback`), and the
   libplacebo-opts preset PopupButton offers exactly `default | fast |
   high_quality`.
7. Changing a Settings value at runtime (e.g. `scale` popup → `lanczos`)
   takes effect on the next file load without a restart (the existing
   `setUserOption` `sync: true` path).
8. The existing IINA test target still passes (regression). The existing
   `KeyMappingTests` (`@click`/`@press`/`@release`) and
   `MPVConfigSynthesisTests` still pass unchanged.

## Scope

- `iina/Preference.swift` — rewrite the `defaultPreference` entries for the
  ~50 already-wired keys to curated values; add ~15 new keys (requirement
  2); default `useUserDefinedConfDir` back to `false`.
- `iina/SettingsPageOSD.swift` — verify/complete rows for the OSD block.
- `iina/SettingsPageVideoAdvanced.swift` — verify/complete rows for
  scale/cscale/dscale/libplacebo/color/HDR/dither/hwdec-software-fallback.
- `iina/SettingsPageVideo.swift` (or a new screenshots section) — add the
  screenshot block rows.
- `iina/SettingsPageAudio.swift` — add `volumeMax`, verify `volume`.
- `iina/SettingsPageSubtitles.swift` — add `subShadowOffset`, `subColor`,
  verify `subFontSize`/`subFilePaths`.
- `iina/SettingsPageGeneral.swift` / `SettingsPageControl.swift` — add
  `savePositionOnQuit`, `geometry`, `inputMediaKeys`, `ytdl`,
  `ytdlRawOptionsAppend`.
- `iina/SettingsItem.swift` — add the badge hook to `General.makeView`
  (~line 178); add `.mpvName(_:)` accessor on `Base` (line 12) so a row
  knows which mpv option it binds to.
- `iina/MPVController.swift` — add `setUserOption(...)` calls in `mpvInit`
  for each new key; remove the `osd-fonts-dir`/`sub-fonts-dir` forced
  materialisation (lines 704–705) since the mpv/ fonts bundle is gone;
  remove the first-run materialisation call.
- `iina/Utility.swift` — remove `ensureMaterializedMPVConfigDir` (or reduce
  it to a no-op that returns the user-only path); keep
  `materializedMPVConfigDirURL` as the *user* path only (no bundle copy).
  Remove the `synthesizempvConf`/`MPVConfigRow` table if it is now dead
  (verify with `grep` first — Chesterton's fence).
- `iina/MainWindowController.swift` — OSD font resolution
  (`resolvedOSDFont`, line 2177) keeps its 4-tier precedence but the
  bundled-fonts fallback path must tolerate the bundle having no `mpv/fonts`
  dir.
- `iina/PlayerCore.swift` — remove the `force-window`/PATH augmentation that
  pointed at the bundled `mpv/yt-dlp`; revert to the system `yt-dlp` lookup
  (or honour a new `Preference.Key.ytdlSearchPath` if absent).
- `iina/MPVSentinel.swift` — unchanged; still reads the user-only mpv.conf.
- `iina.xcodeproj/project.pbxproj` — remove the mpv/ Copy Files build
  phase added by the prior iteration.
- `.specite/iterations/mpv-config-driven-refactor/SPEC.md` — prepend the
  SUPERSEDED banner.
- `iina/Tests/` — add `PreferenceDefaultsTests` asserting the curated
  defaults match `mpv/mpv.conf` (regression guard against drift).

## Non-Goals

- iOS/iPadOS (`iina-ios`), `iina-cli`, and the JS plugin template — macOS
  app only.
- `[profile]`-section options in `mpv/mpv.conf` (`ontop`, `image-display-
  duration`, `loop-file`/`loop-playlist` inside `[Images]`, `vo=gpu-next`
  /`gpu-context=macvk` inside `[HDR_DolbyVision]`, `target-*`/`blend-
  subtitles` inside `[HDR*]`, `demuxer-lavf-format` inside
  `[extension.vpy]`). Profiles are applied by mpv's own conditional
  profile engine; surfacing them as static Settings rows would misrepresent
  their conditional semantics. Power users edit profiles by hand in their
  user mpv.conf.
- Rebuilding IINA's keybinding editor or the `@click`/`@press`/`@release`
  parser (already complete from the prior iteration).
- Bundling `yt-dlp`, uosc, or the uosc font assets. With mpv/ bundling
  removed, these are not shipped; users who want them install them via the
  standard mpv config-dir (toggled by the Advanced escape hatch, requirement
  5) or system PATH.
- Auto-migrating the curated defaults back into an `mpv.conf` for users
  who had one materialised by the prior iteration. Those users keep their
  materialised file; the badge tells them which rows it overrides.
- Lua script-message event handling (`MPV_EVENT_SCRIPT_MESSAGE`) — already
  addressed by the prior iteration; no new work here unless a regression
  surfaces.

## Behavior Details

### Option precedence

For each option the effective value is resolved as:

1. **User mpv.conf** (if `~/Library/Application Support/com.colliderli.iina/
   mpv/mpv.conf` exists and sets the key) — wins.
2. **IINA Preference** value (defaults baked from `mpv/mpv.conf`,
   user-editable via Settings).
3. **mpv built-in default** (only when both above are unset — should not
   happen for baked keys).

The precedence is enforced by the existing `userOptionsContains` guard
pattern in `MPVController` for the forced-option block, and by mpv itself
for option keys IINA merely sets via `setUserOption` (mpv.conf is read
before IINA's `mpv_set_option_string` calls when a config-dir is active).
The badge mirrors this precedence: a row is badged iff
`MPVSentinel.wasSetInConfig(<mpv-name>)`.

### Coverage table (main section of `mpv/mpv.conf`)

Status: ✓ = key exists (re-default only); **NEW** = add key + row + wiring;
**GAP** = documented limitation (custom view / non-`SettingsItem.General`
widget), not pursued this iteration.
"Curated" = value baked into `Preference.swift`.

| mpv.conf line | Preference.Key | Widget | Curated | Status |
|---|---|---|---|---|
| `hwdec=auto` | `hardwareDecoder` | PopupButton | `auto` | ✓ |
| `icc-force-contrast=1000` | `iccForceContrast` | Input | `1000` | ✓ |
| `vd-lavc-dr=yes` | `vdLavcDr` | PopupButton | `yes` | ✓ |
| `vd-lavc-software-fallback=60` | `hwdecSoftwareFallback` | Stepper | `60` | **NEW** (option renamed; see correction 1) |
| `scale=bilinear` | `scale` | PopupButton | `bilinear` | ✓ |
| `cscale=bilinear` | `cscale` | PopupButton | `bilinear` | ✓ |
| `dscale=bilinear` | `dscale` | PopupButton | `bilinear` | ✓ |
| `scale-antiring=0.0` | `scaleAntiring` | Slider | `0.0` | ✓ |
| `correct-downscaling=no` | `correctDownscaling` | Switch | `no` | ✓ |
| `linear-downscaling=no` | `linearDownscaling` | Switch | `no` | ✓ |
| `sigmoid-upscaling=no` | `sigmoidUpscaling` | Switch | `no` | ✓ |
| `hdr-compute-peak=no` | `hdrComputePeak` | PopupButton | `no` | ✓ |
| `hdr-peak-percentile=100` | `hdrPeakPercentile` | Slider | `100` | ✓ |
| `hdr-contrast-recovery=0.0` | `hdrContrastRecovery` | Slider | `0.0` | ✓ |
| `dither=no` | `dither` | PopupButton | `no` | ✓ |
| `libplacebo-opts=preset=fast` | `libplaceboOpts` | Input | `preset=fast` | ✓ |
| `border=no` | `border` | Switch | `no` | ✓ (Phase 7 row added) |
| `hidpi-window-scale=yes` | `hidpiWindowScale` | Switch | `yes` | ✓ (Phase 7 row added) |
| `force-window=immediate` | `forceWindow` | PopupButton | `immediate` | **NEW** (pref key; PlayerCore guard) |
| `geometry=50%:50%` | `geometry` | Input | `50%:50%` | **NEW** |
| `autofit-larger=100%x100%` | `autofitLarger` | Input | `100%x100%` | ✓ |
| `save-position-on-quit=no` | `savePositionOnQuit` | Switch | `no` | **NEW** |
| `cursor-autohide=1000` | `cursorAutohide` | Input | `1000` | ✓ |
| `keep-open=yes` | `keepOpen` | PopupButton | `yes` | ✓ (verify legacy key) |
| `osc=no` | `osc` | Switch | `no` | ✓ |
| `input-media-keys=no` | `inputMediaKeys` | Switch | `no` | **NEW** |
| `force-seekable=yes` | `forceSeekable` | Switch | `yes` | ✓ |
| `ytdl=yes` | `ytdl` | Switch | `yes` | **NEW** |
| `ytdl-raw-options-append=cookies-from-browser=edge` | `ytdlRawOptionsAppend` | multiline Input | `cookies-from-browser=edge` | **NEW** |
| `ad-lavc-downmix=yes` | `adLavcDownmix` | Switch | `yes` | ✓ |
| `audio-channels=stereo` | `audioChannels` | PopupButton | `stereo` | ✓ (Phase 7 row added) |
| `audio-file-auto=fuzzy` | `audioFileAuto` | PopupButton | `fuzzy` | ✓ (Phase 7 row added) |
| `alang=en,eng,zh,chi` | `audioLanguage` | Input | `en,eng,zh,chi` | **GAP** (`SettingsAccessory.LanguageSelector`; Phase 5 badge machinery cannot reach) |
| `volume=80` | `volume` | Slider | `80` | **GAP** (`SwitchWithInput` widget; Phase 5 badge machinery cannot reach) |
| `volume-max=200` | `volumeMax` | Slider | `200` | **NEW** |
| `slang=chi,zh-CN,jpn,sc,chs` | `subtitleLanguage` | Input | `chi,zh-CN,jpn,sc,chs` | ✓ (legacy) |
| `sub-auto=fuzzy` | `subAuto` | PopupButton | `fuzzy` | **NEW** (was forced-only) |
| `sub-font-size=43` | `subTextSize` | Stepper | `43` | **GAP** (`SubtitlesFontView` custom view; badge machinery in `SettingsItem.General.makeView` does not reach raw AppKit widgets) |
| `sub-shadow-offset=0` | `subShadowOffset` | Stepper | `0` | **GAP** (`SubtitlesShadowView` custom view; see note above) |
| `sub-color='#F0FFFFFF'` | `subColor` | NSColorWell | `#F0FFFFFF` | **GAP** (`SubtitlesColorView` custom view; see note above) |
| `sub-file-paths=ass:srt:sub:subs:subtitles` | `subFilePaths` | path picker | `ass:srt:sub:subs:subtitles` | ✓ |
| `screenshot-format=png` | `screenshotFormat` | PopupButton | `png` | **NEW** |
| `screenshot-jpeg-quality=100` | `screenshotJpegQuality` | Slider | `100` | **GAP** (`ScreenshotFormatOptionsView` custom view; see note above) |
| `screenshot-jpeg-source-chroma=no` | `screenshotJpegSourceChroma` | Switch | `no` | **GAP** (`ScreenshotFormatOptionsView` custom view; see note above) |
| `screenshot-png-compression=5` | `screenshotPngCompression` | Slider | `5` | **GAP** (`ScreenshotFormatOptionsView` custom view; see note above) |
| `screenshot-webp-lossless=yes` | `screenshotWebpLossless` | Switch | `yes` | **GAP** (`ScreenshotFormatOptionsView` custom view; see note above) |
| `screenshot-webp-quality=100` | `screenshotWebpQuality` | Slider | `100` | **GAP** (`ScreenshotFormatOptionsView` custom view; see note above) |
| `screenshot-jxl-distance=0` | `screenshotJxlDistance` | Slider | `0` | **GAP** (`ScreenshotFormatOptionsView` custom view; see note above) |
| `screenshot-jxl-effort=5` | `screenshotJxlEffort` | Slider | `5` | **GAP** (`ScreenshotFormatOptionsView` custom view; see note above) |
| `screenshot-high-bit-depth=yes` | `screenshotHighBitDepth` | Switch | `yes` | **GAP** (`ScreenshotFormatOptionsView` custom view; see note above) |
| `screenshot-template="~~desktop/MPV-%P-N%n"` | `screenshotTemplate` | Input | `~~desktop/MPV-%P-N%n` | **NEW** |
| `osd-on-seek=msg-bar` | `osdOnSeek` | PopupButton | `msg-bar` | ✓ |
| `osd-bar-h=2` | `osdBarH` | Slider | `2` | ✓ |
| `osd-bar-border-size=0.2` | `osdBarBorderSize` | Stepper | `0.2` | ✓ |
| `osd-border-size=0` | `osdBorderSize` | Stepper | `0` | ✓ |
| `osd-font-size=40` | `osdFontSize` | Stepper | `40` | ✓ |
| `osd-fractions=yes` | `osdFractions` | Switch | `yes` | ✓ |
| `osd-playing-msg="${filename}"` | `osdPlayingMsg` | Input | `${filename}` | ✓ |
| `osd-font="Microsoft Yahei"` | `osdFont` | FontPicker | `Microsoft Yahei` | ✓ |
| `osd-duration=2000` | `osdDuration` | Stepper | `2000` | ✓ |
| `osd-playing-msg-duration=3000` | `osdPlayingMsgDuration` | Stepper | `3000` | ✓ |

Totals: 59 main-section option lines. 44 keys exist (re-default);
~15 new keys added in Phase 3; **Phase 7** added 4 new Settings rows
(`border`, `hidpi-window-scale`, `audio-channels`, `audio-file-auto`) and
brought the `knownGaps` set down from 17 → 13. Documented **GAP** rows:
8 `ScreenshotFormatOptionsView` custom-view rows, 3 `Subtitles*View`
custom-view rows (`sub-font-size`, `sub-shadow-offset`, `sub-color`),
1 `SwitchWithInput` row (`volume`), 1 `LanguageSelector` row
(`alang`). Widening the Phase 5 badge machinery to reach the custom
views would require a separate refactor of
`SettingsItem.General.makeView` to expose a `.mpvName`-aware hook on raw
AppKit widgets — not justified this iteration. Each "verify legacy" row
requires a `grep` confirmation that the listed legacy key name is the
one actually wired.

### Badge mechanics

- `SettingsItem.Base` gains an `var mpvOptionName: String?` and a chained
  accessor `.mpvName(_:)`. The accessor stores the mpv option string (e.g.
  `"osd-font-size"`).
- `SettingsItem.General.makeView` (~line 178) adds a badge view when
  `mpvOptionName.flatMap { MPVSentinel.wasSetInConfig($0) } == true`. Badge
  is a 12-pt secondary-label `NSTextField` reading "Overridden by your
  mpv.conf" (localized) with a tooltip restating the mpv option name.
- The badge is recomputed on view refresh; it does not need live updates
  during a single launch (mpv.conf is read once at `MPVController.mpvInit`).

### Color format

`sub-color` (and any future color option) is stored in IINA prefs as a hex
string `#AARRGGBB` (or `#RRGGBB` when alpha is 0xFF) and converted at the
`setUserOption` boundary to mpv's `r/g/b/a` form. The `NSColorWell` emits
`NSColor` → normalise to `#AARRGGBB` in the transformer.

### Removal safety (Chesterton's fence)

`Utility.synthesizempvConf` and the `MPVConfigRow` table may have other
callers (tests, the "Additional mpv options" path). Before deleting, grep
for `synthesizempvConf` and `MPVConfigRow` references; if the only caller
is the now-removed materialisation, delete; otherwise leave with a comment.

## Dependencies And Research

- **libmpv** — already integrated; no version bump. The forced-override
  removal relies on the existing `userOptionsContains` guard pattern and
  mpv's own option precedence (config-dir options win over `mpv_set_option
  _string` set after init when the option is list/append-typed; for scalar
  options the last writer wins, so IINA must set its values *before*
  `mpv_initialize` only when no user config-dir is active — already the
  current code path).
- **No new Swift Package Manager dependencies.** No new external binaries
  bundled (yt-dlp/uosc are deliberately un-bundled by this iteration).
- Research reports in `.specite/docs/`:
  - `mpv-options-ui-mapping.md` — **NEW this iteration.** Per-option type,
    valid values, mpv default, and recommended IINA widget for every line
    in the user's `mpv.conf`. Source of the coverage table above and the
    two corrections.
  - `mpv-script-loading.md`, `uosc-integration.md`, `yt-dlp-options.md` —
    retained from the prior iteration. Now relevant only to the Advanced
    escape hatch (requirement 5) for users who bring their own config-dir;
    no IINA code depends on them after mpv/ un-bundling.

## Verification

1. **Build**: `xcodebuild -project iina.xcodeproj -scheme IINA
   -configuration Debug build` succeeds. The built `.app` has **no**
   `Contents/Resources/mpv/` directory.
2. **Defaults test**: `xcodebuild test -project iina.xcodeproj -scheme IINA
   -only-testing:iinaTests/PreferenceDefaultsTests`. Asserts that for each
   row in the coverage table, the registered default equals the curated
   value (guards against drift between `mpv/mpv.conf` and `Preference.swift`).
3. **Clean-install smoke**: delete `~/Library/Application Support/com.
   colliderli.iina/`, launch the app, open a local video. Confirm via
   `mpv.log` (or `iina-cli --get-property`):
   - `scale=bilinear`, `cscale=bilinear`, `dscale=bilinear`.
   - `libplacebo-opts=preset=fast`.
   - `hwdec-software-fallback=60` (NOT `vd-lavc-software-fallback`).
   - `osd-font-size=40`, `osd-font=Microsoft Yahei` (or resolved system
     equivalent).
   - `volume=80`, `volume-max=200`.
4. **No-badge smoke**: in the clean install above, open Preferences → OSD
   and Preferences → Video (Advanced). Confirm no row shows the
   "Overridden by your mpv.conf" badge.
5. **Badge smoke**: drop a `mpv.conf` containing only `osd-font-size=99`
   into `~/Library/Application Support/com.colliderli.iina/mpv/`, relaunch.
   Confirm: (a) OSD font size is 99, (b) the OSD-font-size Settings row is
   badged, (c) the OSD-duration row is NOT badged (not set in the user
   mpv.conf).
6. **Live edit smoke**: in Preferences → Video (Advanced), change `scale`
   popup to `lanczos`, load a new file. Confirm `scale=lanczos` in
   `mpv.log` without restart.
7. **Coverage audit**: run a grep/script that extracts every
   `^[a-z][a-z-]*=` line from the main section of `mpv/mpv.conf` (excluding
   `[profile]` sections) and asserts each mpv option name appears in the
   coverage table in this SPEC and has a `.mpvName("<option>")` call in the
   Settings code. Zero unmapped lines.
8. **Regression**: existing `KeyMappingTests`,
   `MPVConfigSynthesisTests` (if not deleted), and the rest of the test
   target pass unchanged.

## Shifts

N/A
