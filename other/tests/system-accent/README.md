# Native accent policy checks

Run `python3 other/tests/system-accent/run.py` on macOS. The driver compiles the production policy to a temporary directory and starts separate processes for 20 input configurations in both enabled and disabled modes. Each process checks Aqua, Dark Aqua, and both increased-contrast appearances, preservation of unrelated arguments, the absence of persistent/global preference writes, custom title contrast, and launch-stable OSC fill selection. The executable is removed after testing.

The matrix covers all eight fixed native palette colors, Multicolor, exact custom burgundy with both Multicolor and red native accents, a second custom color, light/black/white colors, invalid/incomplete/out-of-range/nonfinite values, and the untouched actual system preferences. Enabled output is checked against the raw RGB components; disabled output and untouched native colors are compared to independent AppKit processes that do not call `AppAccentColor.configure`. The dynamic color is additionally checked after a simulated system-highlight update in the same process.

The driver reuses `build/sidebar-osd-tests/module-cache` when available. Pass `--module-cache PATH` to choose a different existing Swift cache. Pass `--output PATH` to select a JSON result path; the default is `build/system-accent-repair-2026-10-23/native-checks.json`.

## Product color policy

The player intentionally uses the macOS **Text highlight color** as its app accent, including arbitrary colors chosen with Other. This was explicitly requested after the distinction from macOS **Color** was explained. These two settings are independent: [`NSColor.controlAccentColor`](https://developer.apple.com/documentation/appkit/nscolor/controlaccentcolor) follows the native control color; `NSColor.selectedTextBackgroundColor` follows the text highlight with light/dark transformations. See [Apple's Appearance settings guide](https://support.apple.com/en-gb/guide/mac-help/mchlp1225/mac).

`AppAccentColor.color` reads the original `AppleHighlightColor` components and interprets them as sRGB. It preserves all three values, without AppKit's transformed selection-background shade or approximation to a fixed palette color. Missing or malformed highlight components use the native control accent as the automatic fallback. The dynamic color re-reads the preference when resolved. The enable/disable policy remains fixed for the current launch.

When disabled, the startup policy overlays standard blue using `AppleAccentColor`, `AppleAquaColorVariant`, and `AppleHighlightColor` in `NSArgumentDomain` before `NSApplicationMain`. The overlay is process-local and never persisted. The app defaults to enabled; changes to the switch apply after restart. Disabled OSC fills retain their original neutral style.

## API and validation limits

The Apple appearance preference keys are OS implementation preferences, not a documented API for reading arbitrary RGB or applying an app-wide tint. Their format and behavior require verification on new macOS releases. The implementation does not modify global preferences, use private methods, swizzle system classes, or approximate a custom color to the fixed native palette.

AppKit offers no app-wide runtime tint setter, and `NSSwitch` has no public per-control tint property. An accent asset provides an arbitrary app accent for Multicolor only; it does not override a user's fixed native accent. See [Apple's WWDC20 accent color explanation](https://developer.apple.com/videos/play/wwdc2020/10104/?time=975). Native controls need supported per-control tint properties or an explicit adapter. `NSColorList` is a color-panel palette/catalog and does not set a control theme.

Live UI acceptance must additionally verify switches, radio buttons, segments, sliders, table selection, and OSD/OSC drawing. A successful shared-color readback does not prove each control's rendering or that every consumer uses the shared color. Tests do not change system settings or exercise actual system preference-change notifications.
