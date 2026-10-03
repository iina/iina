# Timeline thumbnail API contract tests

Player-scoped plugins subscribe through `iina.thumbnails.subscribe(callback)`
and stop delivery with `iina.thumbnails.unsubscribe(id)`. The callback receives
`state`, `progress`, `media`, cumulative `thumbnails`, and an optional
invalidation/failure `reason`. `state` is `generating`, `partial`, `ready`,
`invalidated`, `unavailable`, or `failed`; cache hits and fresh generation both
finish with `ready`. Each thumbnail exposes `timestamp()`, `width()`,
`height()`, `mimeType()`, and `data()` (a lazily created `Uint8Array`).

`media` contains the opaque session ID, file URL and metadata, and selected
video-track identity. IINA drops stale results when any of those identities
changes. Delivery is main-thread coalesced and images are JPEG-encoded before
crossing the bridge; IINA bounds an update to 128 items, 256 KiB per item, and
8 MiB total. The API is read-only and never exposes cache paths or FFmpeg
controls. Subscriptions are removed automatically when a plugin instance is
unloaded.

`test_timeline_thumbnail_api.py` is a dependency-free Python harness for this
public broker contract. It covers cache/fresh parity, progressive and final
states, file/track/session invalidation, request-token rejection, plugin
unload, malformed data, transfer bounds, and existing API registration.

These tests do not claim live AppKit, JavaScriptCore, FFmpeg, or WebView
coverage. Run them with:

```sh
python3 -m unittest discover -s other/tests/timeline-thumbnail-api -p 'test_*.py'
```

On macOS, also run the production broker's native regression tests:

```sh
bash other/tests/timeline-thumbnail-api/run_native_tests.sh
```

The Swift harness compiles `TimelineThumbnailBroker.swift` with minimal player
type stubs. It runs actual AppKit JPEG encoding on the broker queue for fresh
`NSImage(cgImage:)` frames and cache-decoded images, checks partial/ready pixels
and timestamps, image dimensions, actual per-image/cumulative JPEG byte limits,
count limits, and session invalidation.
It does not exercise FFmpeg generation or the JavaScript/WebView bridge.
