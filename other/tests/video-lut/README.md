# Video LUT checks

- `bash other/tests/video-lut/run.sh [OUTPUT]` checks 3D `.cube` validation,
  persistent copies, name collisions, UTF-8/special filenames, scoped reset, real
  Trash deletion/recovery and legacy hidden-copy reimport. Test-only trash items
  are recovered into the output folder after checks.
- `python3 other/tests/video-lut/engine.py OUTPUT /Applications/LYINA.app/Contents/Frameworks/libmpv.2.dylib`
  consumes that output and renders baseline, identity, inverted output and inverted
  source LUT frames through the exact bundled engine. Also checks labeled
  replacement/removal without deleting unrelated video filters. No UI or audio.
- `bash other/tests/video-lut/popup-run.sh [OUTPUT]` exercises the extracted,
  unchanged production popup in AppKit with local service/engine doubles. It tests
  import/cancel/error callbacks, selection, UTF-8 graph quoting, scope, deletion confirmation/cancel, real managed-copy trashing, original-file
  preservation, cross-player rollback and disabling
  during interactive crop. The system file picker and rendering are not stub-free
  integration evidence from this suite.

2026-10-17 live UI inspection confirmed the LUT row before Brightness and the
None/Import menu in an isolated app. The system open panel caused repeated CUA
timeouts; completing the import through that live panel remains unverified.
