# UPnP Preferences Decoupling Implementation Plan

> **For agentic workers:** Execute task-by-task from the approved design [`docs/superpowers/specs/2026-07-29-upnp-prefs-decoupling-design.md`](../specs/2026-07-29-upnp-prefs-decoupling-design.md).

**Goal:** Move UPnP settings out of `Preference.swift` into private storage + browser UI only.

**Architecture:** `UPnPPreferences` wraps UserDefaults with existing key strings; migrate call sites; strip Preference keys; extend browser settings alert; cleanup PrefGeneral/strings.

**Tech Stack:** Swift, AppKit, UserDefaults, Xcode pbxproj

---

### Task 1: Add UPnPPreferences + Xcode membership

- [ ] Create `iina/UPnPPreferences.swift` with registerDefaults + typed accessors
- [ ] Call `UPnPPreferences.registerDefaults()` from AppDelegate near Preference defaults registration
- [ ] Add file to `project.pbxproj` (file ref, Controllers group, Sources phase)

### Task 2: Migrate call sites; strip Preference.swift

- [ ] Replace all UPnP Preference usage in UPnPBrowserWindowController + PlayerCore
- [ ] Remove UPnP keys and defaultValues from Preference.swift

### Task 3: Browser settings + hygiene

- [ ] Add Auto-Play Next checkbox to settings alert + localization
- [ ] Restore PrefGeneralViewController.xib to develop
- [ ] Remove unused `preference.upnp.*` strings (Base + en)

### Task 4: Verify

- [ ] rg confirms no UPnP in Preference.swift; no Preference.upnp call sites
- [ ] `xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug build` succeeds
- [ ] Commit implementation (do not push/update PR unless asked)
