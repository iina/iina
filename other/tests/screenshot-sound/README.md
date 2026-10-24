# Screenshot sound

Run `bash other/tests/screenshot-sound/run.sh`. Override the output directory with
`SCREENSHOT_SOUND_OUTPUT_DIR` if needed.

Compiles the production request lifecycle, async-command submission, command-reply
branch, node parsing, typed OSD command provenance, ImageIO decoder and sound helper. Bundled mpv C structures
are populated by a small engine fixture; reply memory is destroyed before main
processes the copied filename. It uses native images, temporary files, an isolated
UserDefaults domain and a real system sound object. System playback is intercepted
so checks are silent. Pasteboard and preview are fixtures; the personal clipboard
is never changed. No player window is opened.

Coverage: default/reset/persistence, captured destination/sound intent,
file/clipboard/combined destinations, exactly one sound, preview disabled,
decode/copy/missing-file failures, immediate submission failure, async failure,
unique request IDs, out-of-order/duplicate replies, overlapping feedback tokens,
cancel/media change/stop/shutdown, invalidation during worker decoding,
cache-confined cleanup and the native UI-sound policy. Image decoding is checked
off-main; pasteboard, sound, OSD and feedback completion are checked on main.

Real mpv capture, actual clipboard serialization, FFmpeg fallback formats and
visible feedback animation remain native-app integration checks.
