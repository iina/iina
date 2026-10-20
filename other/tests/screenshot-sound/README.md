# Screenshot sound

Run `bash other/tests/screenshot-sound/run.sh`. Override the output directory with
`SCREENSHOT_SOUND_OUTPUT_DIR` if needed.

Compiles the production completion callback and sound helper. It uses native
images, temporary files, an isolated UserDefaults domain and a real system sound
object. System playback is intercepted so automated checks are silent. Engine,
pasteboard and preview are fixtures; the personal clipboard is never changed.

Coverage: default/reset/persistence, file/clipboard/combined destinations, exactly
one sound, preview disabled, feedback disabled, image decode/copy failure,
missing folder/result and the native UI-sound policy. mpv error replies are gated
before this callback and remain a source/full-player integration boundary.
