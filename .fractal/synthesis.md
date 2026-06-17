# Fractal findings: mpv config → IINA Settings coverage

**Source**: /fractal
**Input**: Analyze mpv config and map to IINA Settings UI

### Items

1. **GPU/scale/colour/HDR block — fully wired** -- All 17 options from the user's `mpv.conf` now have matching `Preference.Key` entries and UI controls in `SettingsPageVideoAdvanced`. This is Phase 7 work already completed.
   - source: `iina/Preference.swift:189-209`, `iina/SettingsPageVideoAdvanced.swift`
   - confidence: CONFIRMED

2. **OSD block — fully wired** -- All 10 `osd-*` options have keys and appear in `SettingsPageOSD`.
   - source: `iina/Preference.swift:211-221`, `iina/SettingsPageOSD.swift`
   - confidence: CONFIRMED

3. **Screenshot quality options — keys exist, UI missing** -- `screenshotJpegQuality`, `screenshotPngCompression`, `screenshotWebpLossless/Quality`, `screenshotJxlDistance/Effort`, `screenshotHighBitDepth`, `screenshotJpegSourceChroma` all have `Preference.Key` definitions but no Settings UI controls.
   - source: `iina/Preference.swift:232-239`, `SettingsPageScreenshot.swift` (no matching items found)
   - confidence: CONFIRMED

4. **Subtitle non-ASS styling — unmapped** -- `sub-font-size`, `sub-shadow-offset`, `sub-color` (for non-ASS subtitles) have no `Preference.Key` and no UI. IINA only exposes ASS-style subtitle styling via `subTextSize`, `subTextColorString`, etc.
   - source: `mpv/mpv.conf:54-56`, `iina/Preference.swift:276-300`
   - confidence: CONFIRMED

5. **Window/playback partial gaps** -- `autofit-larger`, `cursor-autohide`, `ad-lavc-downmix`, `sub-file-paths` have keys but no UI controls. `force-window` has no key (guarded in `PlayerCore.swift` setter). `geometry` has no mapping. `save-position-on-quit` is intentionally not mapped (IINA uses own history).
   - source: `mpv/mpv.conf:28-40`, `iina/Preference.swift:242-249`, `iina/MPVController.swift:679-682`
   - confidence: CONFIRMED

6. **tone-mapping mode — partially covered** -- `tone-mapping=st2094-40` in `[HDR_DolbyVision]` profile has no dedicated key. `toneMappingAlgorithm` exists but covers algorithm selection, not the specific tone-mapping mode string.
   - source: `mpv/mpv.conf:123`, `iina/Preference.swift:180-182`
   - confidence: CONFIRMED

7. **input.conf bindings — out of scope for Settings UI** -- Key bindings are handled by mpv directly via `config-dir`. The `@click`/`@press`/`@release` parsing extension in `KeyMapping.swift` is for IINA's own input editor, not a Settings page.
   - source: `mpv/input.conf`, `iina/KeyMapping.swift`
   - confidence: CONFIRMED

### Exploration Shape

- **Areas explored**: mpv.conf options, Preference.swift keys, SettingsPage*.swift UI pages, MPVController wiring
- **Max depth reached**: 1
- **Handlers dispatched**: 1
- **Dead ends**: input.conf key binding UI (not applicable — bindings are mpv-native)

### Open Questions

None. All mpv.conf options have been accounted for.

### Summary

The Phase 7 work is largely complete: GPU/scale/HDR and OSD options are fully wired to both Preference keys and Settings UI. The remaining gaps are mostly UI wiring for keys that already exist (screenshot quality, `autofit-larger`, `cursor-autohide`, `ad-lavc-downmix`, `sub-file-paths`) plus a few unmapped options (`sub-font-size`/`sub-color`/`sub-shadow-offset` for non-ASS, `force-window`, `geometry`, `tone-mapping` mode). These are implementation tasks, not analysis gaps.
