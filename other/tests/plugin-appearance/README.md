# Plugin appearance acceptance

Run on a Mac with an interactive WindowServer session:

```sh
python3 other/tests/plugin-appearance/run.py
```

The harness compiles the actual `AppAccentColor.swift`,
`JavascriptAPIAppearance.swift`, and `PluginAppearanceBridge.swift` for a macOS 12
deployment target. Small stubs provide the owning application's preferences and
plugin base class. The existing message bridge and simple-mode HTML are extracted
verbatim from production sources. Static integration assertions cover normal and
global API registration and all three plugin WebView navigation hooks.

Checks exercise actual JavaScriptCore exports and managed callbacks, fresh
snapshots, listener removal/unload, unchanged-update deduplication, configured
Theme resolution, and background JSCore initialization while main is deliberately
unavailable. The latter prevents reintroducing a synchronous main-thread hop
while a plugin holds its JavaScript virtual-machine lock, and checks cancellation
before deferred observer startup.

Observer ownership checks use actual registration fields and test-only consumer
counters (`PLUGIN_APPEARANCE_TESTING`). Repeated bootstrap installs one shared
set of three application observers. Twelve getter-only native contexts install
zero subscriptions; twenty-four callbacks across those contexts install twelve
lightweight subscriptions. Removing their final callbacks returns the consumer
count to zero. An HTML bridge adds only one source subscription and its own view
appearance observer. The shared source keeps the background appearance cache
fresh even when no native context subscribes.

Real WKWebView tests cover CSS variables before the first author script, live
callbacks/browser events, preserving authored colors and the existing message
bridge, script ordering and isolated content worlds, file reload with the current
seed, simple mode, disposal, and absence of WebView retain cycles. A synthetic
persisted `PageTransitionEvent` tests the BFCache event-handler regression; this
is not acceptance of a real WebKit back/forward-cache restoration.

The app stays nonactivating, uses a nonpersistent WebKit data store, and supplies
process-local volatile color fixtures. It does not install plugins or write
personal/system preferences. Reuse `build/sidebar-osd-tests/module-cache` (the
default) to avoid creating another large compiler cache. Small outputs are saved
under `build/plugin-appearance-2026-10-24` or `--output`.

`fixture.iinaplugin` is the real app acceptance fixture, identifier
`org.iina.tests.accent-api-fixture`. Install/enable it only in an isolated QA domain.
It logs normal/global snapshots and adds the **Accent API** sidebar tab plus
Plugins menu commands beginning **Accent API —** for sidebar, standalone, simple
mode, and overlay checks. Its fixed purple button must retain the author's color.
The `video-overlay` permission belongs to that demonstration; the appearance API
itself has no permission requirement.
