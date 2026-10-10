# Synthetic test fixtures

These fixtures were generated for the iPadOS playback tests. They contain FFmpeg test-pattern video, synthesized tone audio, and authored subtitle text, not film clips, recorded music, or downloaded subtitles. The generated content and subtitle text are offered under GPL-3.0-only; see ../../LICENSE.

| File | Content |
| --- | --- |
| `playback.mp4` | Approximately 12 seconds, 320×180 H.264 test-pattern video with AAC tone audio |
| `playback.mkv` | The same short test media in Matroska with an authored SubRip track |
| `music.m4a` | A 12-second synthetic AAC tone; title, artist, and album identify it as a test fixture |
| `primary.srt` | Authored bottom-track test text |
| `secondary.srt` | Authored top-track test text |

FFmpeg's `testsrc2`/`sine` generators can produce replacement video/audio fixtures with these dimensions and duration; mux `primary.srt` as a SubRip track for the Matroska case. Frame stepping, captures, subtitles, and timing tests rely on synthetic media with visible frame changes. FFmpeg's executable and codec implementations are not included in this fixture directory.
