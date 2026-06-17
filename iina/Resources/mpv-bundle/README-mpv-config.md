# Bundled mpv Configuration

This directory contains the `mpv/` configuration folder that IINA ships
inside the macOS app bundle. It is copied into the built `.app` at
`Contents/Resources/mpv/` by the `Copy MPV Config` Xcode build phase, and
materialised into the user's Application Support directory on first
launch (see below).

## What is shipped

| Path                  | Purpose                                                |
| --------------------- | ------------------------------------------------------ |
| `mpv.conf`            | Main mpv option file (scaling, OSD, HDR, etc.)         |
| `input.conf`          | Default key bindings (uosc, stats, console, etc.)      |
| `scripts/`            | Lua scripts loaded automatically by mpv                |
| `script-opts/`        | Per-script options (read by mpv's `script-opts` layer) |
| `fonts/`              | Bundled font assets (`uosc_icons.otf`, `uosc_textures.ttf`) |
| `yt-dlp`              | Bundled `yt-dlp` binary, auto-located by `PlayerCore`  |

## How IINA consumes it at runtime

1. `Utility.bundledMPVConfigDirURL` returns the in-bundle path
   (`Bundle.main.url(forResource: "mpv", withExtension: nil)`).
2. On first launch with an empty Application Support directory, IINA
   copies the bundled tree to
   `~/Library/Application Support/com.colliderli.iina/mpv/` and passes
   that path to mpv via `config-dir`. The copy is **idempotent** — it
   only runs when the destination `mpv.conf` is missing.
3. The active `config-dir` is therefore the materialized path, not the
   bundle path. mpv's `~~/` macro expands to the materialized dir at
   runtime.

## Editing vs. shipping

- Files inside the bundled `mpv/` are **read-only** from the user's
  perspective. Editing them in place affects the build only.
- To customise, edit the copy under
  `~/Library/Application Support/com.colliderli.iina/mpv/`. The
  first-run copy will never overwrite a customised `mpv.conf`.
- To reset to the bundled defaults, delete the materialized `mpv/`
  directory and relaunch IINA.

## What can be edited from IINA's UI

- The basic mpv.conf options are exposed through the existing
  `SettingsPageAdvanced` (additional mpv options) editor.
- New preference keys and dedicated UI groups
  (`SettingsPageVideoAdvanced`, `SettingsPageOSD`) are added in later
  phases of the `mpv-config-driven-refactor` iteration to expose the
  options the bundled `mpv.conf` uses but the old IINA Preference layer
  did not cover.

## Auto-profiles

The bundled `mpv.conf` defines six `[profile]` sections
(`[ontop_playback]`, `[Images]`, `[extension.vpy]`,
`[HDR_generic]`, `[HDR_DolbyVision]`, `[HDR直通]`). These are honoured
natively by mpv once `config-dir` is set — no IINA-side code change is
required.

## See also

- `../SPEC.md` (in this iteration folder) — full requirements and
  acceptance criteria.
- `../PLAN.md` — phased implementation plan.
