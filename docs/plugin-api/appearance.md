# Appearance tokens — proposed API v1

This proposed read-only API shares the player's current accent with plugins.
It is available on this branch, not in stock IINA. It requires no new permission and is
available in normal player scripts, global plugin scripts, and main-frame HTML
sidebars, overlays, and standalone windows, including simple mode.

## Plugin scripts

```js
const appearance = iina.appearance;
if (appearance && typeof appearance.getTheme === 'function') {
  const theme = appearance.getTheme();
  iina.console.log(`Player accent: ${theme.accentColor}`);
}
```

`getTheme()` synchronously returns a fresh snapshot:

```json
{
  "version": 1,
  "source": "textHighlight",
  "accentColor": "#336699",
  "accentTextColor": "#FFFFFF"
}
```

Both color values are opaque, uppercase sRGB `#RRGGBB` strings. `source` names the
current launch's policy. These identifiers remain stable when visible Settings
labels change:

| Source | Meaning |
| --- | --- |
| `defaultBlue` | **Default** in Settings: standard player blue. |
| `systemAccent` | macOS Accent color. |
| `textHighlight` | **System Highlight** in Settings: macOS Text highlight color, including an Other/custom RGB selection. |
| `custom` | The player's saved custom color, applied when this launch started. |

A pending accent-source or custom-color change in Settings is not exposed before
Restart. System colors still update live when the current launch's source follows
macOS. If macOS supplies no valid text-highlight RGB, that policy falls back to
the native system accent while its source remains `textHighlight`.

Colors resolve using the player's configured light/dark/system Theme. Version 1
exposes accent tokens; it does not add a light/dark flag. HTML can continue using
`prefers-color-scheme` for its other theme styles.

Reading the snapshot needs no subscription. There are no setters and the API does
not create player windows.

## HTML and CSS

The player injects these custom properties on the document root before author scripts:

- `--iina-accent-color`
- `--iina-accent-text-color`

They update automatically, with no JavaScript or subscription required. Apply
them only to elements that should follow the player; existing plugin-authored
color rules are not rewritten.

```css
button.primary {
  background-color: var(--iina-accent-color, #007AFF);
  color: var(--iina-accent-text-color, #FFFFFF);
  border: 0;
  border-radius: 6px;
  padding: 8px 12px;
}
```

The fallbacks keep the same stylesheet usable on stock IINA. HTML also has
`window.iina.appearance.getTheme()` for code that needs the current colors.
The existing `iina.postMessage`, `iina.onMessage`, and simple-mode functions remain
available. The two reserved CSS properties are the only styles the bridge writes;
it does not recolor the page globally.

## Optional change subscriptions

Subscribe only when JavaScript must react to later changes, for example to redraw
a canvas. Normal/global plugin scripts and HTML share this interface:

```js
const appearance = iina.appearance;
if (appearance && typeof appearance.onChange === 'function') {
  const listener = appearance.onChange(theme => {
    iina.console.log(`Updated accent: ${theme.accentColor}`);
  });
  // When this subscriber is no longer needed:
  // appearance.offChange(listener);
}
```

`onChange(callback)` returns an opaque string ID. The callback receives the same
snapshot shape, is delivered on the main thread like the existing plugin UI API,
and is not called immediately. Read `getTheme()` for the initial value.
Unchanged snapshots are deduplicated and nearby notifications may be coalesced.
`offChange(id)` removes that listener; unknown IDs do nothing. Native callbacks
are managed references and are removed when the plugin instance unloads. A native
context subscribes when it receives its first callback and unsubscribes when its
last callback is removed.

HTML also supports the browser event:

```js
if (window.iina?.appearance) {
  window.addEventListener('iina-theme-changed', event => {
    console.log(event.detail.accentColor);
  });
}
```

Use either the callback or the browser event for a given subscriber to avoid
handling the same change twice. Each callback/event gets a fresh snapshot object.
Reload and navigation inject the current tokens again before the new document's
author scripts run. Register new document listeners normally. Subscriptions
survive a persisted `pagehide` when WebKit places a document in its back/forward
cache; discarded documents release their listeners. HTML `getTheme()` reads the
latest snapshot delivered to that document by the native bridge.

The public HTML appearance object is read-only.

## TypeScript and acceptance fixture

[appearance.d.ts](appearance.d.ts) exports additive interfaces without replacing
stock IINA's existing declarations:

```ts
import type { IINAWithAppearance } from './appearance';
const appearance = (iina as typeof iina & IINAWithAppearance).appearance;
```

The small real plugin at
[`other/tests/plugin-appearance/fixture.iinaplugin`](../../other/tests/plugin-appearance/fixture.iinaplugin)
shows the native API in normal/global contexts, a sidebar, a standalone HTML
window, simple mode, and a video overlay. Its `video-overlay` permission is solely
for the overlay demonstration; appearance itself needs no permission. The
fixture has explicit menu entries under Plugins beginning with **Accent API —**.
It must be installed/enabled in an isolated QA profile; the automated harness
does not install it into a personal profile.

Run `python3 other/tests/plugin-appearance/run.py` for the native JavaScriptCore
and WKWebView checks. This compiles the production policy, API, and bridge for a
macOS 12 deployment target and uses a nonpersistent WebKit data store and
process-local volatile color fixtures.
