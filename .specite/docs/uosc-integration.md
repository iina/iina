# uosc Integration Notes

Sources: [README.md](https://github.com/tomasklaen/uosc), [src/uosc.conf](https://github.com/tomasklaen/uosc/blob/HEAD/src/uosc.conf), [src/uosc/main.lua](https://github.com/tomasklaen/uosc/blob/main/src/uosc/main.lua), [installers/unix.sh](https://github.com/tomasklaen/uosc/blob/HEAD/installers/unix.sh), [installers/windows.ps1](https://github.com/tomasklaen/uosc/blob/HEAD/installers/windows.ps1). Latest release: **5.12.0** (Sep 13, 2025). Requires mpv **≥ 0.33**.

uosc is a self-contained mpv Lua script plus a tiny helper binary (`ziggy`) used only for OpenSubtitles search/download, clipboard, and self-update. The core UI is pure Lua/libass and does not require any extra runtime from the host.

---

## 1. Install Layout

Files uosc drops into the mpv **config directory** (mpv picks `scripts/` and `fonts/` up automatically):

```
<mpv-config>/
  scripts/
    uosc.lua            # loader entry-point — mpv auto-runs anything in scripts/*.lua
    uosc/               # main package
    uosc_shared/        # shared lua modules
  fonts/
    uosc_icons.otf      # icon font (REQUIRED for icons to render)
    uosc_textures.ttf   # texture font (REQUIRED for shapes/backgrounds)
  script-opts/
    uosc.conf           # options file (created only if missing)
```

Config-dir resolution precedence (from `installers/unix.sh`): `$MPV_CONFIG_DIR` → flatpak `~/.var/app/io.mpv.Mpv/config/mpv` → snap `~/snap/mpv/current/.config/mpv` → snap-wayland `~/snap/mpv-wayland/common/.config/mpv` → `$XDG_CONFIG_HOME/mpv` (Linux) → `~/.config/mpv` (macOS). On Windows: `$MPV_CONFIG_DIR` → current `portable_config/` → `$APPDATA/mpv`.

### Programmatic install (host-app bundle)

```bash
# 1. download the release zip
curl -L -o /tmp/uosc.zip \
  https://github.com/tomasklaen/uosc/releases/latest/download/uosc.zip

# 2. unzip into the mpv config dir (creates scripts/, fonts/, script-opts/)
unzip -q -o /tmp/uosc.zip -d "$MPV_CONFIG_DIR"

# 3. only if no uosc.conf yet, fetch the defaults
[ -f "$MPV_CONFIG_DIR/script-opts/uosc.conf" ] || \
  curl -L -o "$MPV_CONFIG_DIR/script-opts/uosc.conf" \
    https://github.com/tomasklaen/uosc/releases/latest/download/uosc.conf
```

Or fetch individual files at the same URLs (the same `uosc.zip` and `uosc.conf` URLs are referenced by `unix.sh` and `windows.ps1`).

### Required `mpv.conf` toggles for a clean UI

```ini
# uosc renders its own seeking/volume indicators, so the built-in OSD bar is redundant
osd-bar=no

# uosc draws its own window border / controls when border is off
border=no
```

Optional perf tweak: `video-sync=display-resample`.

### Font assets (uosc_icons.otf, uosc_textures.ttf)

Both fonts are **required** — they are referenced internally by uosc's libass renderer (icons via glyph IDs, textures for shape/background fills). Without them, icons render as missing-glyph boxes and shapes fall back to no fills.

- Loaded by uosc automatically; the host does **not** need to register them with mpv via `--osd-font` or `@font-face`.
- The text font (titles, timecodes, menus) is whatever mpv uses for `--osd-font` — uosc reads `options/osd-font` at startup. The host configures this through normal mpv options:

```ini
# mpv.conf
osd-font=Inter
osd-font-size=22
```

- Boldness for text is controlled by uosc's own `font_bold` option, **not** by the host.

---

## 2. uosc.conf Options the Host Should Care About

Full defaults live in `src/uosc.conf`. The options a host app typically configures (or surfaces in its own settings UI):

```ini
# --- text font controls (text font itself comes from mpv's osd-font) ---
font_scale=1            # numeric multiplier on rendered text size
font_bold=no            # yes|no — use only bold font weight throughout the UI

# --- top bar (window controls + media title) ---
top_bar=no-border       # never | no-border | always
top_bar_size=40         # height in px (pre-scale)
top_bar_controls=right  # no | left | right
top_bar_title=yes       # no | yes | "<custom template using ${...}>"
top_bar_alt_title=      # empty, or a template like "${filename}"
top_bar_alt_title_place=below   # below | toggle
top_bar_flash_on=video,audio    # flash on load: audio,video,image,chapter
top_bar_persistency=            # comma list: paused,audio,image,video,idle,windowed,fullscreen

# --- timeline / progress ---
timeline_style=line              # line | bar
timeline_size=40                 # 0 disables
timeline_step=5                  # wheel-seek step (suffix `!` for exact seek)
progress=windowed                # when to show always-on thin progress: windowed|fullscreen|always|never

# --- controls bar (button row) ---
controls=menu,gap,<video,audio>subtitles,<has_many_audio>audio,<has_many_video>video,<has_many_edition>editions,<stream>stream-quality,gap,space,<video,audio>speed,space,shuffle,loop-playlist,loop-file,gap,prev,items,next,gap,fullscreen
controls_size=32
controls_margin=8
controls_spacing=2

# --- volume / speed ---
volume=right                     # none | left | right
volume_size=40
volume_step=1
speed_step=0.1
speed_step_is_factor=no

# --- menus ---
menu_type_to_search=yes         # typing auto-opens search
menu_item_height=36
menu_min_width=260
menu_padding=4

# --- flash & autohide ---
flash_duration=1000
autohide=no
pause_indicator=flash            # flash | static | manual

# --- types shown in loaders/open-file ---
video_types=3g2,3gp,asf,avi,f4v,flv,h264,h265,m2ts,m4v,mkv,mov,mp4,mp4v,mpeg,mpg,ogm,ogv,rm,rmvb,ts,vob,webm,wmv,y4m
audio_types=aac,ac3,aiff,ape,au,cue,dsf,dts,flac,m4a,mid,midi,mka,mp3,mp4a,oga,ogg,opus,spx,tak,tta,wav,weba,wma,wv
image_types=apng,avif,bmp,gif,j2k,jp2,jfif,jpeg,jpg,jxl,mj2,png,svg,tga,tif,tiff,webp
subtitle_types=aqt,ass,gsub,idx,jss,lrc,mks,pgs,pjs,psb,rt,sbv,slt,smi,sub,sup,srt,ssa,ssf,ttxt,txt,usf,vt,vtt
playlist_types=m3u,m3u8,pls,url,cue
load_types=video,audio,image
default_directory=~/
show_hidden_files=no
use_trash=no

# --- subtitles downloader (uses OpenSubtitles REST) ---
languages=slang,en
subtitles_directory=~~/subtitles

# --- colors / opacity / theming ---
# Defaults: foreground=ffffff, foreground_text=000000, background=000000, background_text=ffffff,
#           window_border=000000, curtain=111111, success=a5e075, error=ff616e,
#           match=69c5ff, heatmap=00adee
color=
opacity=

# --- scaling ---
scale=1
scale_fullscreen=1.3

# --- element visibility ---
disable_elements=    # window_border, top_bar, timeline, controls, volume, idle_indicator,
                     # audio_indicator, buffering_indicator, pause_indicator
```

The `top_bar` option replaces what users commonly call a "title bar" — uosc observes mpv's own `title-bar` and `border` properties and draws its own when both are off. To **hide** the host window's native title bar while uosc draws its own, set `border=no` in `mpv.conf`; uosc will paint `window_border` and a `top_bar` over the undecorated area.

### Subtitles the host needs to know about

- `osd-font` (mpv) — text font face/size; uosc respects it.
- `osd-playlist-entry` (mpv) — `title` vs `filename`; uosc uses it in the playlist menu.
- `slang` (mpv) — fallback for uosc's `languages` keyword.
- `script-opts/uosc.conf` — read by `mp.options.read_options(options, 'uosc', ...)` in `main.lua`; the `uosc` prefix is the script-opt name.

---

## 3. Built-in `script-binding uosc/<name>` Commands

These are the commands a host app most commonly exposes in its own UI (toolbar buttons, menu items, etc.). They are registered in `main.lua` via `mp.add_key_binding(nil, name, ...)`, so the host invokes them with mpv's standard `script-binding` command.

| Binding (`uosc/<name>`) | Purpose | Key mpv property / effect |
|---|---|---|
| `open-file` | File/directory browser (filters by `video_types`/`audio_types`/`image_types`) | `loadfile <path>` |
| `load-subtitles` | Subtitle file browser (filters by `subtitle_types`) | `sub-add <path>` |
| `load-audio` | Audio file browser | `audio-add <path>` |
| `load-video` | Extra video track browser | `video-add <path>` |
| `subtitles` | Track-selection menu for subs (incl. download) | `sid`, `sub-visibility`, `secondary-sid` |
| `audio` | Track-selection menu for audio | `aid` |
| `video` | Track-selection menu for video | `vid` |
| `audio-device` | Audio output device picker | `audio-device` |
| `playlist` / `items` | Playlist menu; `items` is "playlist if any, else open-file" | `playlist-pos-1`, `playlist-remove`, `playlist-move` |
| `chapters` | Chapter menu (with sponsor-block / opening / ending ranges) | `chapter` |
| `editions` | MKV edition picker | `edition` |
| `stream-quality` | Quality picker (writes `ytdl-format` from `stream_quality_options`) | `ytdl-format` + reload |
| `download-subtitles` | OpenSubtitles search/download | ziggy subprocess |
| `show-in-directory` | Reveal current file in OS file explorer | none (subprocess) |
| `open-config-directory` | Open mpv config dir in OS file explorer | none (subprocess) |
| `menu` | Toggle default context menu | none |
| `menu-blurred` | Same but no first-item preselect (good for mouse buttons) | none |
| `keybinds` | Command-palette of current keybindings | none |
| `shuffle` | Toggle uosc's shuffle mode (different from mpv's `playlist-shuffle`) | none |
| `next`, `prev`, `first`, `last` | Navigate playlist or directory | `playlist-pos-1` / `loadfile` |
| `next-file`, `prev-file`, `first-file`, `last-file` | Directory navigation only | `loadfile` |
| `delete-file-next`, `delete-file-prev`, `delete-file-quit` | Delete current + navigate/quit (needs `trash-cli` on Linux / `trash` on macOS when `use_trash=yes`) | `stop`, `quit` |
| `paste`, `paste-to-open`, `paste-to-playlist` | Paste a path/URL from clipboard (ziggy) | `loadfile … [append]` |
| `copy-to-clipboard` | Copy current path/URL to clipboard (ziggy) | none |
| `update` | Self-update from inside the UI | downloads release zip |
| `toggle-ui` | Pin UI visible (calls `toggle-elements timeline,controls,volume,top_bar`) | none |
| `toggle-progress` | Toggle minimized always-on progress | none |
| `toggle-title` | Swap top-bar title between main/alt | none |
| `flash-ui`, `flash-timeline`, `flash-progress`, `flash-top-bar`, `flash-volume`, `flash-speed`, `flash-pause-indicator` | Briefly reveal one element | none |
| `decide-pause-indicator` | Stick pause indicator visible (used with `pause_indicator=manual`) | none |
| `menu-prev`, `menu-next`, `menu-prev-page`, `menu-next-page`, `menu-start`, `menu-end`, `menu-activate`, `menu-back` | Programmatic menu navigation | none |

### Invoking them from the host

```lua
-- mp.input.command / mp.command / mp.commandv all work
mp.commandv('script-binding', 'uosc/open-file')
mp.commandv('script-binding', 'uosc/playlist')
mp.commandv('script-binding', 'uosc/load-subtitles')
mp.commandv('script-binding', 'uosc/subtitles')
mp.commandv('script-binding', 'uosc/audio')
mp.commandv('script-binding', 'uosc/video')
mp.commandv('script-binding', 'uosc/editions')
mp.commandv('script-binding', 'uosc/chapters')
mp.commandv('script-binding', 'uosc/audio-device')
mp.commandv('script-binding', 'uosc/stream-quality')
mp.commandv('script-binding', 'uosc/show-in-directory')
mp.commandv('script-binding', 'uosc/open-config-directory')
mp.commandv('script-binding', 'uosc/menu')
mp.commandv('script-binding', 'uosc/flash-elements', 'timeline,speed')  -- see messages below
```

If the host is a non-Lua binary (Swift, C, etc.) using libmpv, the equivalent is the mpv command `script-binding uosc/<name>`:

```c
// libmpv
mpv_command_string(ctx, "script-binding uosc/open-file");
mpv_command_string(ctx, "script-binding uosc/load-subtitles");
mpv_command_string(ctx, "script-binding uosc/playlist");
```

---

## 4. Script Messages (host → uosc)

uosc registers message handlers via `mp.register_script_message(<name>, <fn>)`; the host sends them with `script-message-to uosc <name> <args...>`.

```lua
-- open a submenu defined in input.conf (or one of the default ones)
mp.commandv('script-message-to', 'uosc', 'show-submenu', 'Utils > Aspect ratio')
mp.commandv('script-message-to', 'uosc', 'show-submenu-blurred', 'Utils > Audio devices')

-- open a fully custom menu (JSON: {type, title, items:[{title,hint,value,badge,...}]})
mp.commandv('script-message-to', 'uosc', 'open-menu', [[
  {
    "type": "host_menu",
    "title": "Host menu",
    "items": [
      {"title": "Open",   "value": "script-binding uosc/open-file"},
      {"title": "Reload", "value": "cycle-values loop-file inf no"}
    ]
  }
]])

-- update an already-open menu of a given type
mp.commandv('script-message-to', 'uosc', 'update-menu', '{"type":"host_menu","items":[...]}')

-- select a menu item programmatically (1-based index)
mp.commandv('script-message-to', 'uosc', 'select-menu-item', 'host_menu', '1')

-- close a menu by type
mp.commandv('script-message-to', 'uosc', 'close-menu', 'host_menu')

-- pin/unpin an element (visibility 0..1, omit ids to target all)
mp.commandv('script-message-to', 'uosc', 'set-min-visibility', '1', 'timeline,volume')
mp.commandv('script-message-to', 'uosc', 'set-min-visibility', '0')

-- flash an element briefly (ids: timeline,progress,controls,volume,top_bar,speed,pause_indicator)
mp.commandv('script-message-to', 'uosc', 'flash-elements', 'timeline,speed')

-- override what a uosc key-binding runs (for a single session)
mp.commandv('script-message-to', 'uosc', 'overwrite-binding', 'next',
            'playlist-next; show-text "next!"')

-- disable elements from a host script (use a unique client id; pass '' to undo)
mp.commandv('script-message-to', 'uosc', 'disable-elements', 'my_host_app', 'top_bar,volume')

-- expose an external property read by uosc elements
mp.commandv('script-message-to', 'uosc', 'set', 'my_host_mode', 'picture-in-picture')
```

uosc also **publishes** one outbound message on load — `script-message uosc-version 5.12.0` — which scripts/hosts can listen for to confirm the script is alive and check the version.

### Sharing the on-screen unoccupied region (osc-margins)

uosc writes a normalized `{l,r,t,b}` margin set to the shared-script property and `user-data/osc/margins`, so other scripts (and the host) can place overlays without overlapping the UI:

```lua
-- read (Lua script side)
mp.command_native({'expand-path', '~~/script-opts/osc-margins'})  -- shared prop file
local margins = mp.get_property_native('user-data/osc/margins')    -- {l=0,r=0,t=0,b=0.18}
```

---

## 5. In-Process API (host *is* a Lua mpv script)

If the host loads as a Lua script in the same mpv instance, it can talk to uosc via the shared module `uosc_shared/lib/std.lua` (re-exports) and `utils.shared_script_property_set`:

```lua
local utils = require('mp.utils')
-- declare the shared property the same way uosc does (idempotent)
if utils.shared_script_property then utils.shared_script_property('osc-margins') end
```

For menu integration, the cleanest path is `script-message-to uosc open-menu <json>` (above) — uosc owns the menu renderer and the search/type-to-filter behavior.

---

## 6. Version Check (host-side guard)

```lua
-- fire and listen once
mp.register_message('uosc-version', function(version)
    mp.osd_message('uosc ' .. version .. ' loaded', 1)
end)
-- uosc 5.12.0 is the current stable; reject older if you depend on a feature
```

If the host needs a minimum version, gate new `open-menu` JSON / `disable-elements` calls on a parsed semver check (anything ≥ 4.6 supports `open-menu`; ≥ 5.0 supports `disable-elements`; ≥ 5.12 is current).

---

## 7. Minimal `input.conf` Stanza a Host Can Ship

A safe default input.conf the host can write if none exists — covers all the script-bindings listed above plus the key uosc wants bound for flash indicators:

```ini
# context menu
mbtn_right   script-binding uosc/menu
menu         script-binding uosc/menu

# track menus
s            script-binding uosc/subtitles  #! Subtitles
a            script-binding uosc/audio      #! Audio tracks
v            script-binding uosc/video      #! Video tracks

# navigation
p            script-binding uosc/items      #! Playlist
c            script-binding uosc/chapters   #! Chapters
o            script-binding uosc/open-file  #! Open file
alt+s        script-binding uosc/load-subtitles  #! Load subtitles

# flash helpers (suppress OSD bar / echo)
space        cycle pause; script-binding uosc/flash-pause-indicator
right        seek  5
left         seek -5
shift+right  seek  30; script-binding uosc/flash-timeline
shift+left   seek -30; script-binding uosc/flash-timeline
m            no-osd cycle mute; script-binding uosc/flash-volume
up           no-osd add volume  10; script-binding uosc/flash-volume
down         no-osd add volume -10; script-binding uosc/flash-volume
[            no-osd add speed -0.1; script-binding uosc/flash-speed
]            no-osd add speed  0.1; script-binding uosc/flash-speed
\            no-osd set speed 1;   script-binding uosc/flash-speed
>            script-binding uosc/next;  script-message-to uosc flash-elements top_bar,timeline
<            script-binding uosc/prev;  script-message-to uosc flash-elements top_bar,timeline
O            script-binding uosc/show-in-directory  #! Show in directory
esc          quit
```

The `#! Title` and `#! Section > Item` comments are uosc's own menu-definition syntax — uosc parses `input.conf` and builds the context menu from them. Anything the host doesn't want in the menu can simply omit the `#!` comment.
