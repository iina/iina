# mpv Options → IINA Settings Widget Reference

Reference table for choosing the correct IINA Preference widget per mpv
option in the user's `mpv.conf`. Widget legend at the bottom.

Sources: <https://mpv.io/manual/master/#options>, <https://libplacebo.org/options/>.

## Conventions / corrections

- `vd-lavc-software-fallback` does NOT exist in mpv. The real option is
  `hwdec-software-fallback=<yes|no|N>` (default `3`). Map the user's intent
  to that option. `vd-lavc-dr` is separate and real.
- `libplacebo-opts preset=` global enum is `default|fast|high_quality`
  (THREE members). There is no `high` global preset. Individual
  sub-sections use `peak_detection_preset=<default|high_quality>` and
  `color_map_preset=<default|high_quality>`.
- mpv color format: `r/g/b` floats 0.0–1.0, `r/g/b/a`, single gray, or
  hex `#RRGGBB` / `#AARRGGBB`. IINA's `NSColorWell` must emit
  `#AARRGGBB` (or `#RRGGBB`).
- libmpv defaults differ from CLI defaults where noted ("except libmpv").

---

## 1. Hardware decoding

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `hwdec` | string-list (enum-ish) | `no`, `auto`, `auto-copy`, `auto-unsafe`, `yes`, or comma-list of APIs (`videotoolbox`, `vaapi`, `nvdec`, …) | `no` | PopupButton (common subset) + advanced Input for raw list |
| `hwdec-software-fallback` | int-or-flag | `yes`/`no`/`N` (1==yes) | `3` | PopupButton (yes/no) or Stepper (0–N) |
| `vd-lavc-dr` | enum | `auto`, `yes`, `no` | `auto` | PopupButton |

## 2. Video scaling filters

`scale` / `cscale` / `dscale` share the same enum (cscale/dscale unset ⇒
inherit `scale`). Common members — full list via `--scale=help`:

`bilinear`, `bicubic`, `lanczos`, `spline36` (spline-windowed sinc),
`spline64`, `ewa_lanczos` (jinc), `ewa_lanczossharp`,
`ewa_lanczos4sharpest`, `mitchell`, `hermite`, `catmull_rom`, `gaussian`,
`oversample`, `linear` (tscale only), `nearest`, `box`.

| Option | Type | Default | IINA widget |
|---|---|---|---|
| `scale` | enum | `lanczos` | PopupButton |
| `cscale` | enum | unset (inherits `scale`) | PopupButton (+ "inherit" choice) |
| `dscale` | enum | `hermite` (CLI) | PopupButton |
| `scale-antiring` | float `0.0–1.0` | `0.0` (high-quality profile `0.6`) | Slider |
| `correct-downscaling` | flag | `yes` | Switch |
| `linear-downscaling` | flag | `yes` | Switch |
| `sigmoid-upscaling` | flag | `yes` | Switch |

## 3. Color / HDR

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `hdr-compute-peak` | enum | `auto`, `yes`, `no` | `auto` | PopupButton |
| `hdr-peak-percentile` | float `0.0–100.0` | `100.0` | Slider |
| `hdr-contrast-recovery` | float `0.0–2.0` | `0.0` | Slider |
| `icc-force-contrast` | string | `no`, `0–1000000`, `inf` | `no` | Input (text; allow `no`/`inf`/number) |

## 4. Dithering

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `dither` | enum | `fruit`, `ordered`, `error-diffusion`, `no` | `fruit` | PopupButton |

## 5. libplacebo (gpu-next backend)

`libplacebo-opts` is a key/value list (`key=value,key=value`) passed raw
to libplacebo. Treat as advanced free-form Input. The notable inner key:

| Key (inside `libplacebo-opts`) | Type | Valid values | Default | IINA widget |
|---|---|---|---|---|
| `preset` | enum | `default`, `fast`, `high_quality` | `default` | PopupButton |
| `peak_detection_preset` | enum | `default`, `high_quality` | `default` | PopupButton |
| `color_map_preset` | enum | `default`, `high_quality` | `default` | PopupButton |

Host option:

| Option | Type | IINA widget |
|---|---|---|
| `libplacebo-opts` | key/value-list | multiline Input (raw `key=value` pairs) |

## 6. Window / UI

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `border` | flag | `yes`/`no` | `yes` | Switch |
| `hidpi-window-scale` | flag | `yes`/`no` | `no` | Switch |
| `force-window` | enum | `yes`, `no`, `immediate` | `no` (libmpv) | PopupButton |
| `geometry` | string (geometry) | `[W[xH]][+-x+-y][/WS]` or `x:y`, `%` allowed | unset | Input (text) |
| `autofit-larger` | string (geometry) | `[W[xH]]`, `%` allowed | unset | Input (text) |
| `cursor-autohide` | int-or-enum | `N` ms, `no`, `always` | `1000` | PopupButton (no/always) + Input for ms |
| `osc` | flag | `yes`/`no` | `yes` | Switch |

## 7. Playback behavior

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `save-position-on-quit` | flag | `yes`/`no` | `no` | Switch |
| `keep-open` | enum | `yes`, `no`, `always` | `no` | PopupButton |
| `force-seekable` | flag | `yes`/`no` | `no` | Switch |
| `input-media-keys` | flag | `yes`/`no` | `yes` (CLI); `no` (libmpv) | Switch |
| `ytdl` | flag | `yes`/`no` | `yes` | Switch |
| `ytdl-raw-options-append` | key/value-list append op | `key=value` (e.g. `cookies-from-browser=edge`) | unset | multiline Input / list editor |

## 8. Audio

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `ad-lavc-downmix` | flag | `yes`/`no` | `no` | Switch |
| `audio-channels` | string-list | `auto-safe`, `auto`, layout names (`stereo`, `mono`, `5.1`, `7.1`, …), channel count, or `fl-fr-lfe` style | `auto-safe` | PopupButton (common layouts) |
| `volume` | float (0–100 typical; negative→0) | numeric | `100` | Slider |
| `volume-max` | float `100.0–1000.0` | numeric | `130` | Slider / Input |
| `alang` | string-list (IETF tags) | comma-list e.g. `jpn,eng` | unset | Input (comma-separated) |

## 9. External track / subtitle loading

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `audio-file-auto` | enum | `no`, `exact`, `fuzzy`, `all` | `no` | PopupButton |
| `sub-auto` | enum | `no`, `exact`, `fuzzy`, `all` | `exact` | PopupButton |
| `slang` | string-list (IETF tags) | comma-list | unset | Input (comma-separated) |
| `sub-file-paths` | path-list | `:`-separated (`;` on Win) dirs | unset | path picker (multi) |

## 10. Subtitle styling

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `sub-font-size` | int (scaled px @720h) | numeric | `38` | Stepper / Input |
| `sub-shadow-offset` | int/float (scaled px) | numeric | `0` | Stepper / Input |
| `sub-color` | color | `r/g/b[/a]` or `#RRGGBB` / `#AARRGGBB` | opaque white | NSColorWell |

## 11. Screenshots

Format options:

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `screenshot-format` | enum | `png`, `jpg`/`jpeg`, `webp`, `jxl`, `avif` | `jpg` | PopupButton |
| `screenshot-high-bit-depth` | flag | `yes`/`no` | `yes` | Switch |
| `screenshot-template` | string (template) | filename template w/ specifiers (see below) | `mpv-shot%n` | Input (text) |
| `screenshot-jpeg-quality` | int `0–100` | numeric | `90` | Slider |
| `screenshot-jpeg-source-chroma` | flag | `yes`/`no` | `yes` | Switch |
| `screenshot-png-compression` | int `0–9` | numeric | `7` | Slider |
| `screenshot-webp-lossless` | flag | `yes`/`no` | `no` | Switch |
| `screenshot-webp-quality` | int `0–100` | numeric | `75` | Slider |
| `screenshot-jxl-distance` | float `0–15` | 0.0=lossless, 1.0≈JPEG90 | `1.0` | Slider |
| `screenshot-jxl-effort` | int `1–9` | numeric | `4` | Slider |

`screenshot-template` expansion specifiers: `%[#][0X]n` (seq num, pad
to X, default `04`), `%f` (filename), `%F` (filename no ext), `%x` (dir
path), `%X{fallback}` (dir or fallback), `%p` (`HH:MM:SS`), `%P`
(`HH:MM:SS.mmm`), `%wH/%wh/%wM/%wm/%wS/%ws/%wT` (time components),
`%%` (literal `%`).

## 12. OSD block

| Option | Type | Valid values | mpv default | IINA widget |
|---|---|---|---|---|
| `osd-on-seek` | enum | `no`, `bar`, `msg`, `msg-bar` | `bar` | PopupButton |
| `osd-bar-h` | float `0.1–50` | % of screen height | `3.125` | Slider |
| `osd-bar-border-size` | float (scaled px) | alias of `osd-bar-outline-size` | `0.5` | Stepper / Input |
| `osd-border-size` | float (scaled px) | alias of `osd-outline-size` | `1.65` | Stepper / Input |
| `osd-font-size` | int (scaled px @720h) | numeric | `30` | Stepper / Input |
| `osd-fractions` | flag | `yes`/`no` | `no` | Switch |
| `osd-playing-msg` | string (property-expanded) | template w/ `${prop}` | unset | Input (multiline) |
| `osd-font` | string (font name) | font family/postscript name | `sans-serif` | FontPicker (system font) |
| `osd-duration` | int (ms) | numeric | `1000` | Stepper / Input |
| `osd-playing-msg-duration` | int (ms) | numeric | unset (uses `osd-duration`) | Stepper / Input |

---

## Widget legend

| Widget | Use for |
|---|---|
| **Switch** (NSSwitch) | flag options (`yes`/`no`) |
| **PopupButton** (NSPopUpButton) | closed enums (≤ ~12 known members) |
| **Slider** (NSSlider) | bounded float/int ranges (quality, percentile, gain, ms) |
| **Stepper / Input** (NSTextField) | unbounded or large-range numbers (sizes, ms counts) |
| **Input** (NSTextField, plain) | geometry strings, templates, comma-lists, raw key=value |
| **NSColorWell** | color options (emit `#AARRGGBB`) |
| **FontPicker** | `osd-font` / `*-font` (system font name) |
| **path picker** (NSOpenPanel) | path-list options (`sub-file-paths`, file/dir options) |

## Cross-cutting notes for implementers

- All `flag` options accept `yes`/`no`/`<empty>` (empty ⇒ `yes`).
  `--no-<opt>` is the negation. Store as Bool in IINA prefs.
- `audio-channels` and the scale enums are *open* enums (accept values
  beyond the popup); always provide an "advanced/raw" text field beside
  the PopupButton for power users.
- libmpv re-defaults: `force-window`, `input-media-keys`, `osc` and
  several others default to `no` (or differ) under libmpv vs CLI. When
  IINA ships the user's `mpv.conf` as config-dir, mpv.conf wins, so the
  IINA Preference default only matters when the user has NOT set the key.
- `geometry` / `autofit-larger` parsing on macOS: origin is bottom-left;
  `%` is relative to screen. Validate loosely — mpv rejects bad values.
- `libplacebo-opts` requires libplacebo ≥ v6.309 and `--vo=gpu-next`;
  silently ignored otherwise. Do not expose it unless gpu-next is active.
