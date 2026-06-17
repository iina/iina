# AGENTS.md

## Project Overview

IINA is the modern video player for macOS, built on top of `libmpv`. It ships
a native AppKit UI, a JavaScript plugin host, a CLI tool (`iina-cli`), and a
companion browser helper. The codebase embeds mpv via the libmpv C API and
synchronises Swift state with mpv property/option changes through a dedicated
`MPVController` and `PlayerCore` pair.

The current iteration `mpv-config-driven-refactor` is in the **specified**
stage. It targets the user's personal `mpv/` configuration bundle (HOOKE007
MPV_lazy style, located at `/Users/vec/workspace/swift/iina/mpv/`) and aims
to:

- Ship that `mpv/` folder inside the `.app` and adopt it as the default mpv
  `config-dir`.
- Stop hard-forcing mpv options that fight the user's `mpv.conf` (e.g.
  `vo=libmpv`, `sub-auto=no`, `input-media-keys=no`, `force-window`).
- Wire the missing IINA Preference keys and UI for the options the user's
  `mpv.conf` actually uses (`scale/cscale/dscale`, `libplacebo-opts`, the
  `osd-*` block, `icc-force-contrast`, `vd-lavc-dr`, etc.).
- Bundle the two uosc font assets and the `yt-dlp` binary, and resolve them
  at runtime.
- Support `--ytdl-raw-options-append` (the user's `cookies-from-browser=edge`
  pattern) instead of overwriting mpv's defaults.
- Handle `MPV_EVENT_SCRIPT_MESSAGE` so Lua scripts can call back to IINA.
- Extend the input.conf parser to understand `@click`/`@press`/`@release`
  modifiers.
- Wire `osd-font` into IINA's native OSD rendering.

Scope is the macOS app (`iina/`) only — config + plugin layer. iOS, CLI,
and the JS plugin template are explicitly out of scope. The full work
list, acceptance criteria, and verification steps live in
`.specite/iterations/mpv-config-driven-refactor/SPEC.md`.

## Tech Stack

- **Language**: Swift 5.x, with a thin C/ObjC bridge for libmpv.
- **Build**: Xcode project (`iina.xcodeproj`), `xcodebuild` for CI. There is
  no Swift Package Manager `Package.swift` at the root.
- **UI**: AppKit on macOS; no SwiftUI on the desktop app. iOS app is
  SwiftUI but is out of scope for this iteration.
- **Playback**: `libmpv` (vendored prebuilt via `other/download_libs.sh`).
  Init entry point: `iina/MPVController.swift:318` (`MPVController.mpvInit`).
- **Plugin host**: JavaScriptCore + WKWebView. `iina-plugin/` at the repo
  root is a CLI scaffolder, not a runtime.
- **Bundled user assets (this iteration)**: the in-repo `mpv/` folder is
  copied into the `.app/Contents/Resources/mpv/` by a new Xcode Copy Files
  build phase. `Utility.ensureMaterializedMPVConfigDir` first-run copies
  the bundle to `~/Library/Application Support/com.colliderli.iina/mpv/`.
- **External binaries in scope**: `yt-dlp` (bundled from
  `mpv/yt-dlp`), uosc 5.12.0 (Lua, bundled from `mpv/scripts/uosc/`).
- **Configuration**: IINA uses a JSON user-config layer (`Preference.swift`)
  that mirrors the relevant subset of mpv options. Lua scripts use mpv's
  own `script-opts/*.conf` parser, which mpv reads from the `config-dir`.
- **Tests**: there is no Swift test target at the repo root by default.
  New tests for this iteration go under `iina/Tests/KeyMappingTests.swift`
  (or the existing test target if one exists when implementation starts).
  Smoke tests are run via the built `.app` and the per-run `mpv.log`
  in `~/Library/Logs/com.colliderli.iina/<date>/`.

Key files for this iteration:

- `iina/MPVController.swift` — forced-option rewrites, `userOptionsContains`
  guards, `MPV_EVENT_SCRIPT_MESSAGE` handler, `osd-fonts-dir` /
  `sub-fonts-dir` calls, `--ytdl-raw-options-append` wiring.
- `iina/PlayerCore.swift` — `startMPV` PATH augmentation; `force-window`
  setter guards.
- `iina/MainWindowController.swift:2196` — OSD font resolution.
- `iina/KeyMapping.swift:140` — `parseInputConf` extension for
  `@click`/`@press`/`@release`.
- `iina/Preference.swift` — new pref keys, default changes.
- `iina/SettingsPage*.swift` — new `SettingsPageVideoAdvanced` and
  `SettingsPageOSD` groups.
- `iina/Utility.swift` — `bundledMPVConfigDirURL`,
  `materializedMPVConfigDirURL`, `ensureMaterializedMPVConfigDir`.
- `iina/FontPickerWindowController.swift` — "Font file" tab.
- `iina/MpvScriptMessageCenter.swift` (new) — `script-message` registry.
- `iina.xcodeproj/project.pbxproj` — new Copy Files build phase.
- `mpv/` (in-repo) — canonical source for the bundled config.
- `.specite/iterations/mpv-config-driven-refactor/SPEC.md` — full spec.
- `.specite/docs/mpv-script-loading.md`,
  `.specite/docs/uosc-integration.md`,
  `.specite/docs/yt-dlp-options.md` — research reports.
