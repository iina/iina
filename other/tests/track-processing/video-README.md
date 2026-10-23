# Per-track video processing checks

Run from the repository root:

```sh
zsh other/tests/track-processing/video-run.sh
python3 other/tests/track-processing/video-mpv.py \
  build/track-processing-2026-10-17/video-probe \
  /Applications/LYINA.app/Contents/Frameworks/libmpv.2.dylib
```

The first command compiles the production Foundation-only Swift builders,
checks input validation and defaults, then renders the exact emitted graphs
with the installed FFmpeg. Pixel assertions cover crop/aspect/clockwise rotation,
fixed canvas dimensions, display aspect fitting, source and canvas SAR, track
stacking, semi-transparent input alpha through color correction, and transparent
padding above a background track. FFmpeg scaling can round alpha by one 8-bit unit.

The optional second command loads the specified actual libmpv, decodes a generated
two-track FFV1/BGRA fixture and checks rendered pixels for four compositing cases.
It also decodes a 16-bit FFV1 source tagged BT.2020/PQ, applies single-track
geometry processing and checks 16-bit output format, retained HDR metadata and
16-bit PNG output. The FFmpeg probe verifies exact preservation of adjacent
16-bit luma code values through the geometry-only branch.
It uses image output and opens no window or audio device. This exercises the
bundled engine's decoding, filter negotiation and alpha compositing, independently
of the player's UI. Generated files remain in the output evidence directory.

`ProcessedVideoGraph.make` accepts positive unique IDs in front-to-back order.
An empty selection returns nil. Active per-track settings are applied before
compositing; settings belonging to inactive tracks are ignored. The bottom
source's raw dimensions and optional pixel aspect specify the fixed canvas.
Sources are fitted by their incoming display aspect; crop, aspect override and
rotation never resize the canvas. Callers must pass real demux pixel aspect for
anamorphic canvases. The all-neutral path retains the existing layer graph.

Single-track geometry-only processing uses a 16-bit alpha-capable YUV pipeline;
adding color processing or multiple tracks uses the existing 8-bit RGBA path.
Color control values use mpv's -100...100 ranges and its documented local source
mapping (brightness /100, contrast and saturation (value+100)/100, gamma 8^(value/100),
hue value*1.8 degrees). FFmpeg YUV equalization is not pixel-identical to native
mpv output shaders. This does not provide a new HDR/color-managed multitrack
compositor or high-bit-depth per-track color equalizer.

Observed on 2026-10-17: 50 Swift checks, 12 FFmpeg graph/pixel cases plus a
16-bit luma precision check, and 5 exact installed libmpv render cases passed.
These checks do not assert UI target
selection, runtime graph ownership, performance or Master processing behavior.
