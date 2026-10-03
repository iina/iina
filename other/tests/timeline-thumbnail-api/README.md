# Timeline thumbnail API contract tests

`test_timeline_thumbnail_api.py` is a dependency-free Python harness for the
public broker contract. It covers cache/fresh parity, progressive and final
states, file/track/session invalidation, request-token rejection, plugin
unload, malformed data, transfer bounds, and existing API registration.

These tests do not claim live AppKit, JavaScriptCore, FFmpeg, or WebView
coverage. Run them with:

```sh
python3 -m unittest discover -s other/tests/timeline-thumbnail-api -p 'test_*.py'
```
