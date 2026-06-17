# mpv: Script Loading, `script-opts`, Custom Fonts, and libmpv Hosting

Reference compiled from the mpv stable manual (`https://mpv.io/manual/stable/`) and `include/mpv/client.h`. Citations point at the relevant manual sections.

---

## 1. Auto-loading scripts from the config dir

mpv auto-loads every entry in `<config-dir>/scripts/` as if passed to `--scripts`, in alphabetical order. Single `.lua` / `.main` files and directories both work; `.disable`-suffixed files are always skipped.

```
~/.config/mpv/
├── mpv.conf
├── input.conf
├── fonts.conf                # fontconfig customization (optional)
├── subfont.ttf               # fallback sub font (optional)
├── fonts/                    # default for --sub-fonts-dir & --osd-fonts-dir
│   ├── NotoSans.ttf
│   └── SarasaMonoSC.ttf
├── scripts/
│   ├── osc.lua               # single-file script
│   ├── sponsorblock-minimal/
│   │   ├── main.lua          # directory script (must be named main.<ext>)
│   │   └── categories.json
│   └── mpv-playlistmanager.lua
├── script-opts/
│   ├── osc.conf
│   ├── sponsorblock-minimal.conf
│   └── mpv-playlistmanager.conf
```

Key rules (manual §"Script location", lines 16105-16121):
- `.lua` → Lua backend; `.js` → JS; `.so`/`.dll` → C plugin.
- `main.lua` (or `main.js`, `main.cplugin`) is the entry point for a script directory.
- The directory's top level is prepended to Lua's `package.path` so scripts can `require` siblings.
- Auto-load is suppressed with `--load-scripts=no`.

## 2. `--scripts` option

`--script=<file>` (single) or `--scripts=<file1>:<file2>:...` (path list, separator `:` on Unix, `;` on Windows). Supports the full path-list suffix machinery (`-append`, `-add`, `-pre`, `-clr`, `-remove`).

```bash
# CLI
mpv --scripts=/path/a.lua:/path/b/main.lua

# Append without re-encoding separators
mpv --scripts=/path/a.lua --scripts-append=/path/b/main.lua
```

Programmatic equivalent (libmpv / mpv_set_option_string):

```c
mpv_set_option_string(mpv, "scripts",
    "/path/a.lua:/path/b/main.lua");
// or scoped, less escaping:
mpv_set_option_string(mpv, "scripts-append", "/path/c.lua");
```

Manual reference: `--scripts` is a path list option; see §"List Options" (lines 642-787). Source: line 1831 of the manual.

## 3. `--script-opts` and `script-opts/*.conf`

### Command line / property

`--script-opt` appends one `key=value`; `--script-opts` overwrites the list with `k1=v1,k2=v2`. Keys MUST be prefixed with the script's identifier (`<scriptid>-...`) to avoid collisions; values unclaimed by any loaded script are silently dropped.

```bash
mpv --script-opts=osc-layout=bottombar,osc-showtitle=yes,sponsorblock-minimal-categories=sponsor
```

### `script-opts/<identifier>.conf` parsing

The file format is read by `mp.options.read_options(table, identifier)` inside the Lua script itself. Rules (manual §"mp.options functions", lines 16556-16588):
- File lives at `<config-dir>/script-opts/<identifier>.conf`.
- `key=value` per line; `#` starts a comment; whitespace is not stripped.
- Booleans parse as `yes`/`no`.
- CLI `--script-opts=identifier-key=value` overrides the conf file (conf is read first, then CLI overrides it).
- `on_update` callback (3rd arg) re-reads matching keys whenever the `script-opts` property changes at runtime.

```lua
-- in <script-dir>/myscript/main.lua
local options = {
    foo = "default",
    bar = 42,
    enabled = true,
}
require "mp.options".read_options(options, "myscript")
-- now options.{foo,bar,enabled} reflect:
--   ~/.config/mpv/script-opts/myscript.conf  (if present)
--   then --script-opts=myscript-foo=...       (overrides)
```

```ini
# ~/.config/mpv/script-opts/myscript.conf
foo=Hello World
bar=9999
enabled=no
```

```bash
mpv --script-opts=myscript-foo=OVERRIDE
```

Script names are derived from the filename with non-alphanumerics → `_` (e.g. `mpv-playlistmanager.lua` → `mpv_playlistmanager`); the CLI prefix must match that exact identifier (manual lines 16109, 16442).

## 4. Shipping custom fonts alongside the config dir

### Built-in defaults

- `--sub-fonts-dir` defaults to `~~/fonts` (manual line 3788).
- `--osd-fonts-dir` defaults to `~~/fonts` (line 5077).
- `~~/` resolves to `~~home/` (`~/.config/mpv/`) or the first matching file in any config dir (lines 510-585). On macOS, `~~osxbundle/` is the `.app` resource directory.
- `~/.config/mpv/subfont.ttf` is always used as a fallback by `none` font provider (line 17764).

### Per-platform path macros

| Macro | Resolves to |
|---|---|
| `~~/` | first existing match in config dirs, else `~~home/` |
| `~~home/` | user config dir, e.g. `~/.config/mpv/` (overridden by `--config-dir`, `MPV_HOME`, `XDG_CONFIG_HOME`) |
| `~~global/` | `/etc/mpv` (Linux) |
| `~~osxbundle/` | macOS `.app` Resources (macOS only) |
| `~~exe_dir/` | `mpv.exe` directory (Windows only) |
| `~~cache/` | `~/.cache/mpv/` |
| `~~state/` | `~/.local/state/mpv/` |

### Recommended libmpv host setup

```c
// Point everything at one private tree owned by the host app
mpv_set_option_string(mpv, "config-dir", "/path/to/host/Resources/mpv");

// Bundle extra fonts next to the bundled scripts
mpv_set_option_string(mpv, "sub-fonts-dir", "~~/fonts");
mpv_set_option_string(mpv, "osd-fonts-dir", "~~/fonts");
// macOS bundle Resources path:
mpv_set_option_string(mpv, "sub-fonts-dir", "~~osxbundle/Contents/Resources/fonts");

// Explicit font names (optional overrides; default = "sans-serif")
mpv_set_option_string(mpv, "sub-font", "Sarasa Mono SC");
mpv_set_option_string(mpv, "osd-font", "Noto Sans CJK SC");

// Pick a font provider explicitly. "auto" => CoreText on macOS (default).
// "none" ignores system fonts and only uses embedded + subfont.ttf + fonts/.
// "fontconfig" forces fontconfig (rare on macOS).
mpv_set_option_string(mpv, "sub-font-provider", "auto");
mpv_set_option_string(mpv, "osd-font-provider", "auto");

// Optional: a fontconfig customization at <config-dir>/fonts.conf is
// loaded automatically when libass was built with fontconfig (manual line 17758).
```

Notes (manual lines 3782, 3786, 5073):
- Files in `--*-fonts-dir` are loaded into memory once; for big font sets, prefer adding a `fonts.conf` (fontconfig) instead of dumping TTF files there.
- OSD never uses embedded media fonts; only `sub-fonts-dir` + `osd-fonts-dir` + the system provider.
- `--sub-font` is ignored for ASS subtitles unless `--sub-ass=no` (line 3587) — use the bundled `.ttf` via fontconfig/ASS style overrides if you need a custom face for ASS.

## 5. libmpv: forwarding user-installed scripts to embedded mpv

From the manual §"Embedding into other programs (libmpv)" (lines 17500-17510): libmpv uses the same option mechanism as the CLI; options can be set before `mpv_initialize` via `mpv_set_option_string` (or with native types via `mpv_set_property` / `MPV_FORMAT_NODE` after init).

Typical host-app flow (sequential, all before `mpv_initialize`):

```c
mpv_handle *ctx = mpv_create();

// 1. Pin config dir to the host's private tree (suppresses user & global).
//    No-config-dir would still pick up ~/.config/mpv/, which is usually wrong.
mpv_set_option_string(ctx, "config-dir", hostConfigDir);

// 2. Skip auto-loaded scripts; we will register them explicitly by full path
//    so user-installed scripts are always picked up but bundled ones run too.
mpv_set_option_string(ctx, "load-scripts", "no");

// 3. Forward the user-config directory's scripts/ verbatim.
//    Multiple scripts are joined with the platform path separator (: / ;).
char *scripts = build_scripts_list(userScriptsDir);
if (scripts) {
    mpv_set_option_string(ctx, "scripts", scripts);
    free(scripts);
}

// 4. Append the host's bundled scripts last so they cannot be shadowed.
mpv_set_option_string(ctx, "scripts-append",
    "/path/to/host/Resources/mpv/scripts/osc.lua");
mpv_set_option_string(ctx, "scripts-append",
    "/path/to/host/Resources/mpv/scripts/uosc/main.lua");

// 5. Forward the user's script-opts verbatim, then layer host defaults on top.
if (userScriptOpts)
    mpv_set_option_string(ctx, "script-opts", userScriptOpts);
mpv_set_option_string(ctx, "script-opts-append",
    "osc-showtitle=yes,osc-loop-playlist=inf");
mpv_set_option_string(ctx, "script-opts-append",
    "uosc-title-bar=no,uosc-themes=/path/to/host/Themes");

// 6. Fonts (see §4).
mpv_set_option_string(ctx, "config-dir", hostConfigDir);  // already set above
mpv_set_option_string(ctx, "sub-fonts-dir", "~~/fonts");
mpv_set_option_string(ctx, "osd-fonts-dir", "~~/fonts");

mpv_initialize(ctx);
```

Key gotchas (from manual):
- `--no-config` takes precedence over `--config-dir` (line 1809). Do not set both.
- All `~~/` config-dir-based paths become empty strings when `--no-config` is set (lines 538-546); the host should avoid this combination.
- `--config-dir` does **not** redirect `~~/cache` or `~~/state` — those keep their auto-detection (line 1807).
- Path list separator is `:` on Unix, `;` on Windows; build with `mpv_get_property("platform")` or branch on `__APPLE__`/`_WIN32` if the host is cross-platform.
- Option writes via `mpv_set_option_string` must happen before `mpv_initialize`; afterwards use `mpv_set_property` (e.g. `mpv_set_property(ctx, "script-opts", MPV_FORMAT_NODE, ...)` for structured updates).
- `script-opts` is also exposed as a runtime property (mutated via `set property script-opts ...`); this lets the host update script config without restart.

## 6. Minimal end-to-end host-app recipe (pseudocode)

```text
hostConfigDir = <App Support>/mpv
                ├── mpv.conf
                ├── input.conf
                ├── fonts.conf            (optional)
                ├── fonts/                (default for sub-fonts-dir / osd-fonts-dir)
                ├── scripts/
                │   ├── osc.lua           (or bundled uosc/main.lua)
                │   └── myhost.lua
                └── script-opts/
                    ├── osc.conf
                    └── myhost.conf

forwardUserConfig = yes
on startup:
    set config-dir = hostConfigDir                # isolates from ~/.config/mpv
    set load-scripts = no                         # we pass them explicitly
    set scripts = join(user~/scripts)             # user scripts first
    set scripts-append = hostConfigDir/scripts/*  # bundled scripts last
    set script-opts = user~/script-opts           # forwarded as-is
    set script-opts-append = host-defaults        # host's defaults layer on top
    set sub-fonts-dir = ~~/fonts                  # resolves under hostConfigDir
    set osd-fonts-dir = ~~/fonts
    initialize
```

This is the minimum surface a libmpv host needs to behave like a stock mpv with a private, predictable config root while still honouring whatever the user dropped in `~/Library/Application Support/mpv/scripts/` and `script-opts/`.
