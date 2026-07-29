# UPnP Preferences Decoupling Design

**Date:** 2026-07-29  
**Branch:** `feature/upnp-dlna-pr`  
**Status:** Approved in chat; awaiting final spec review before implementation  
**Related:** IINA PR feedback on [#5877](https://github.com/iina/iina/pull/5877) (@low-batt); upstream SwiftUI settings migration on `develop` / former `new-pref-ui`

## Problem

Maintainers asked contributors not to add new Preferences / settings-window UI while IINA ports settings to SwiftUI. UPnP currently stores state via `Preference.Key` entries in [`Preference.swift`](../../iina/Preference.swift), which couples the feature to IINA’s settings system even though most UPnP UI already lives in the browser window.

## Goal

Keep UPnP/DLNA behavior unchanged for users, but remove all UPnP coupling from IINA Preferences / Settings (Preference.swift, Pref XIBs, SettingsPage*). Settings remain only inside the UPnP browser.

## Non-goals

- Submitting or rewriting the GitHub PR description
- Porting UPnP into SwiftUI Settings pages
- Changing discovery / playback / auto-play algorithms beyond prefs access and one new checkbox
- Migrating other non-UPnP Preference keys

## Design

### 1. Private storage module

Add [`iina/UPnPPreferences.swift`](../../iina/UPnPPreferences.swift):

- Thin API over `UserDefaults.standard`
- Keep **existing string key names** (`upnpFavorites`, `upnpAutoPlayNext`, `upnpBrowserBehavior`, column-hidden keys, sort keys, playback context, auto-refresh keys) so values already stored on disk continue to work
- Register defaults (or return explicit fallbacks) matching today’s defaults:
  - auto-play next: `true`
  - browser behavior: `1` (keep open)
  - auto-refresh: `true`, interval `30`
  - sort: `"title"` ascending
  - column visibility: same as current Preference defaults
- Typed getters/setters: `bool`, `integer`, `string`, `data`, `set(...)`
- No dependency on `Preference.Key` / `Preference.defaultValues`

### 2. Call-site migration

Replace all `Preference.*(for: .upnp…)` / `Preference.set(..., for: .upnp…)` with `UPnPPreferences` in:

- [`UPnPBrowserWindowController.swift`](../../iina/UPnPBrowserWindowController.swift) (columns, favorites, sort, settings alert, playback context, auto-refresh, browser behavior, auto-play reads)
- [`PlayerCore.swift`](../../iina/PlayerCore.swift) (`loadUPnPPlaybackContext`, `fileEnded` auto-play checks)

`MainMenuActions` only uses the browser APIs / `loadUPnPPlaybackContext`; no direct Preference UPnP keys today beyond that path through PlayerCore.

### 3. Remove from Preference.swift

Delete all UPnP `Key` declarations and matching `defaultValues` entries. After this, `git diff origin/develop -- iina/Preference.swift` should be empty (or only incidental whitespace if unavoidable — prefer empty).

### 4. Browser settings UI

Extend the existing NSAlert in `showAutoRefreshSettings()`:

- Keep: auto-refresh enable, interval, when-video-closes behavior
- Add: **Auto-Play Next** checkbox bound to `UPnPPreferences` (replaces the invisible Preference-only default)
- Slightly taller accessory view to fit the new control
- Persist on OK only (same as today)

### 5. PR hygiene cleanup

- Restore [`PrefGeneralViewController.xib`](../../iina/Base.lproj/PrefGeneralViewController.xib) to match `origin/develop` (remove accidental frame-only delta)
- Remove unused `preference.upnp.*` keys from Base and en `Localizable.strings`
- Keep all `upnp.browser.*` strings used by the browser UI
- Add `UPnPPreferences.swift` to the Xcode target in `project.pbxproj`

### 6. Verification

- `rg 'upnp' iina/Preference.swift` → no matches
- `rg 'Preference\..*upnp|\.upnp' iina --glob '*.swift'` → no Preference UPnP keys
- `git diff origin/develop --stat` still UPnP-focused; no PrefGeneral / SettingsPage churn
- Debug build of `iina` scheme succeeds

## Risks / notes

- **Key continuity:** Reusing the same UserDefaults key strings avoids silent reset of favorites/columns for people already running UPnP builds.
- **Preference observers:** UPnP did not rely on Preference KVO for these keys; direct UserDefaults is fine.
- **PR #5877:** Branch can be updated later when the user asks; this change is local-first.

## Approval

Design approach **2 (hard decoupling)** approved in conversation 2026-07-29. This document is the written spec for implementation.
