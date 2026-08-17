# VR2D

Plays 3D VR video as a flat picture you can look around in, with the
reprojection done by a fragment shader inside IINA's own renderer.

The sibling project `iina-VR2D-plugin` does the same job as an IINA plugin and
works, but its panning cannot be made smooth: a plugin can only reach the `v360`
CPU filter, which costs about 0.064 s of CPU per megapixel of output on every
parameter change and forces hardware decoding into copy-back. Inside the app
none of that applies — mpv has already put the decoded frame in a texture.

Measured on a 4096x2048 30 fps clip, 14 seconds of playback:

| | CPU time | Memory |
|---|---|---|
| Reprojection off | 18.03 s | 596 MB |
| Reprojection on | 18.18 s | 594 MB |

### Two things that made panning feel slow, and are not obvious

**A conflicting filter.** If the VR2D *plugin* is installed and enabled it does
the same job with the `v360` CPU filter, so the frame arrives already
reprojected and the shader reprojects it again — the picture is wrong and the
speed is the plugin's. VR2D now checks the filter chain when it switches on and
says so on the OSD. Turn the plugin off.

**Frames being thrown away.** When AppKit declines a redraw, `display()` falls
into a path that consumes the waiting frame and discards it. That is right when
nothing is going to draw it, and wrong when a redraw is already queued — which
is the normal state while looking around, so a good frame was being binned
moments before the draw that wanted it. It now steps aside only in that case.
Getting this wrong in the other direction is worth knowing about too: disabling
the path outright made mpv report ~250 dropped frames per 5 seconds on a 60 fps
clip, because frames it used to discard quietly were now counted. Same pixels on
screen, different bookkeeping — and a good reminder to check what a counter is
actually counting.

**mpv waiting inside its own render call.** By default mpv renders a frame early
and then blocks in `mpv_render_context_render()` until that frame's target
display time, up to `video-timing-offset` — 50 ms. IINA has exactly one thread
that may touch OpenGL, so that wait holds up everything queued behind it,
including a redraw asking only to move the camera. Measured on the 4K clip, the
render call took **32.5 ms, of which 30 ms was waiting**: it was the frame
interval, not work, and it was identical whether the offscreen buffer was 4096,
3840 or 1920 pixels wide. With the wait switched off and `video-timing-offset`
set to 0 — the pairing the render API's own documentation recommends — the same
call takes **2.1 ms**. Both are undone when reprojection is switched off.

## How it works

`ViewLayer` normally hands mpv the layer's own framebuffer. With reprojection on
it points mpv at an offscreen texture instead, then draws one full-screen
triangle through the VR shader into the layer's framebuffer.

Two details drive the design:

- **mpv renders *fitted* into whatever framebuffer it is given**, because
  `keepaspect` is on. Handing it a window-sized framebuffer would produce a
  letterboxed, already-downscaled image, and reprojecting that would sample
  black bars and throw away most of the source resolution. So the offscreen
  texture is the video's own display size, where mpv's scale is 1:1.
- **mpv expects the OpenGL state at its defaults** on entry and leaves it that
  way on exit, apart from the viewport, scissor, blend function and clear colour
  (`render_gl.h`). Anything the pass binds is unbound before it returns.

Panning, zooming and recentring only change uniforms, so they never involve mpv
and work while paused — the layer is simply marked as needing display and the
held frame is reprojected again.

### Why OpenGL and not Metal

The mpv render API has exactly two backends, `opengl` and `sw`
(`deps/include/mpv/render.h`). There is no Metal one. A `CAMetalLayer` would
therefore mean either the software renderer — the CPU cost this exists to escape
— or keeping the GL context anyway and sharing its texture into Metal through an
`IOSurface`, which adds a cross-API synchronisation problem and a rewrite of the
`ViewLayer`/`VideoView` plumbing while removing nothing. mpv also requires CGL
for hardware decode interop on macOS, so the GL context is not optional.

`CAOpenGLLayer` being deprecated is upstream IINA's exposure, not something this
adds. All the maths lives in one fragment function, so a Metal port later is
close to mechanical.

## Subtitles

mpv composites subtitles into the same framebuffer as the video, and the render
API offers no way to separate them, so with reprojection on they were warped
onto the sphere with the picture — magnified past reading at the centre of the
view, and smeared around the pole at the bottom of the frame, which is where
mpv puts them.

So mpv is asked not to draw them and `VR2DSubtitleView` draws them instead, over
the flattened picture, from mpv's own `sub-text` property. They stay still while
you look around, stay legible, and land where subtitles belong.

The styling is read back out of mpv, not out of IINA's preferences: font, size,
scale, bold, italic, colour, border size and colour, background, shadow,
spacing, alignment, margins and position. mpv holds the effective values — IINA
has already pushed twenty-odd settings into it, and anything from `mpv.conf`, a
user script or a runtime change is in there too — so reading them from there is
both shorter and more correct than maintaining a second copy of that mapping.
Changing a subtitle setting restyles whatever is on screen straight away.

**Showing and hiding.** mpv's `sub-visibility` is what stops it drawing its own
subtitles, and it is also how the user shows and hides them, so the two would
fight: turning subtitles back on would turn the *warped* ones back on. While
VR2D is drawing them, `PlayerCore.toggleSubVisibility` is routed to the overlay
instead, so the Subtitle menu, the keyboard shortcut and the OSD all behave
exactly as before. mpv's own setting is put back when reprojection is switched
off.

Picture-based subtitles have no text to re-draw, so they are left to mpv and
stay warped. ASS positioning and inline styling are not reproduced either — the
text is taken plain.

## Projections

| | |
|---|---|
| **Stereo layouts** | side by side, over under, monoscopic, either eye first |
| **Projections** | 180° equirectangular, 360° equirectangular, equi-angular cubemap, fisheye at 180 / 190 / 200 / 220° |
| **Detection** | file-name conventions, container stereo metadata, frame aspect ratio |

Picking one eye out of a packed frame is a texture transform rather than a crop,
and unlike `v360`'s own `in_stereo` handling it can pick either eye.

## Using it

Open a VR video. If the name or the container says what it is, reprojection
turns on by itself and says what it found.

| Action | |
|---|---|
| Look around | Drag the video |
| Zoom | Scroll, or pinch |
| Look around (keyboard) | <kbd>⇧</kbd><kbd>⌥</kbd> + arrow keys |
| Zoom (keyboard) | <kbd>⌥</kbd><kbd>=</kbd> / <kbd>⌥</kbd><kbd>-</kbd> |
| Recentre | <kbd>⌥</kbd><kbd>0</kbd> |
| Try the next stereo layout | <kbd>⌥</kbd><kbd>L</kbd> |
| Swap eye | <kbd>⌥</kbd><kbd>E</kbd> |

Everything is under **Video → VR Video**, next to Aspect Ratio, Crop and
Rotation, and it works the way they do: a list of values with a tick on the
current one, the first of which is **Off**. There is no separate on/off command
— choosing Off is the off switch, exactly as Crop's None is, and choosing a
projection turns reprojection on with it. Settings are in **Settings → Video**.

Clicking and double-clicking still do what they normally do: a drag that moves
the view is not counted as a click, and a click that does not move is passed
straight through.

### When the name tells you nothing

Plenty of files are named in a way that says nothing about how they were shot.
**Video → VR Video** lists the projections, so you can work down them while the
file plays. The tell is that straight lines in the scene — door frames, ceiling
beams, table edges — go straight when the projection is right and bow when it is
wrong.

## Detection

A file is flattened automatically when there is at least one **strong** signal
and the frame's shape agrees with it:

- the container's stereo flag (`video-params/stereo-in`)
- an explicit layout in the name — `3dh`, `sbs`, `lr`, `rl`, `3dv`, `tb`, `ou`,
  `bt`, `mono`
- a lens profile — `MKX200`, `MKX220`, `VRCA220`, `RF52`, `fisheye190`
- an explicit projection — `180x180`, `vr180`, `360x180`, `vr360`, `equirect`,
  `eac`

**Weak** hints — a bare `180`/`360`, or a headset name like `oculus` or `quest`
— are ignored unless *"Also act on weak hints"* is on, because plenty of
ordinary files contain them. Aspect ratio never triggers detection on its own.

## Tests

```bash
other/vr2d-tests/run.sh                      # detection and frustum maths
other/vr2d-tests/shader.sh <path-to-IINA.app>  # the shader, against ffmpeg's v360
other/vr2d-tests/input.sh  <path-to-IINA.app>  # looking around, in the real app
```

`run.sh` compiles `VR2DGeometry.swift` and `VR2DDetect.swift` on their own — they
depend on nothing but Foundation — and runs the plugin's behavioural spec against
them.

`shader.sh` is the one that matters. Checking a projection by eye does not work:
a mirrored cube face still looks like a picture. Instead the test patterns encode
each pixel's own longitude and latitude in their red and green channels, so a
render says exactly which direction every output pixel sampled. The same view is
then rendered by `ffmpeg`'s `v360` — the reference implementation for what these
files mean — and the two are compared as an angle on the sphere. 28 cases across
five projections, both stereo layouts and both eyes agree with `v360` to within
one step of the encoding, with a median difference of 0.000° in 26 of them.

That comparison is also how the equi-angular cubemap was written: rather than
guessing the face order and rotations, a `v360`-produced cubemap of a
coordinate-encoded sphere was decoded to read the layout off directly.

## Limitations

- **Picture-based subtitles (PGS, VobSub) are reprojected along with the
  video**, because there is no text in them to re-draw. Text subtitles are
  handled: see below.
- **The window keeps the source's aspect ratio.** A 180° side-by-side file is
  2:1, so the flat view is rendered into a 2:1 window.
- **The equi-angular cubemap is about one pixel out** per 512-pixel face against
  `v360`, which insets each face slightly. Visible only on the highest-frequency
  test material.
- **Spherical metadata (`sv3d`) is not read** — mpv does not expose it. The
  container's stereo layout is used, and the projection comes from the name or
  the aspect ratio.

## Still open

- **Measuring how smooth panning actually is, from outside, is unreliable.**
  `other/vr2d-tests/profile` reports draws per second, but macOS throttles
  presentation for a window that is not frontmost, and a run launched from a
  script usually is not. The same clip and build measured 130 draws/s in one run
  and 10 in another purely because of that, so only the figures taken from
  *inside* one draw — how long mpv's render took, how long the pass took, how
  long a view change waited — are quoted here.
- **While a drag is in progress the video itself advances only a few frames a
  second**, because frames that arrive with no redraw queued are discarded as
  they always were. The pan stays smooth; the picture behind it is briefly
  stale. Whether that is worth fixing is a judgement call, not a defect.

## Notes for anyone working on this

- If the `iina-VR2D-plugin` is installed and enabled, **turn it off**. It
  reprojects with a CPU filter, so the shader would be handed an already
  reprojected frame. The test harnesses refuse to load plugins for this reason.
- IINA's forced redraw while paused is intermittently unreliable on its own —
  about one capture in five does not come back, with reprojection off as well as
  on. `input.sh` measures both so a regression can be told apart from this.
- IINA's log is block buffered. A run that ends badly loses its last 28KB; run
  the app under `script -q /dev/null` to read a whole one.
