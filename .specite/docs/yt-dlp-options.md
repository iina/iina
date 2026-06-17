# yt-dlp Options for macOS App Bundling (IINA / libmpv)

Concise reference for the four topics requested. Sources:
- yt-dlp README (master, 2026): https://github.com/yt-dlp/yt-dlp/blob/master/README.md
- yt-dlp EJS wiki: https://github.com/yt-dlp/yt-dlp/wiki/EJS
- mpv manual (stable): https://mpv.io/manual/stable/

yt-dlp on this machine (informational):
```
$ yt-dlp --version
2026.05.22
```

---

## 1. `--cookies-from-browser`

### Argument grammar

```
--cookies-from-browser BROWSER[+KEYRING][:PROFILE][::CONTAINER]
```

- `BROWSER` (required): one of `brave`, `chrome`, `chromium`, `edge`, `firefox`, `opera`, `safari`, `vivaldi`, `whale`.
- `+KEYRING` (optional, Linux only): `+basictext`, `+gnomekeyring`, `+kwallet`, `+kwallet5`, `+kwallet6`. Ignored on macOS.
- `:PROFILE` (optional): profile name or absolute path to a profile directory. Omit to use the most recently accessed profile.
- `::CONTAINER` (optional, Firefox only): container name, or `none` to pick the default container. Ignored for non-Firefox browsers.

Default: not loaded (`--no-cookies-from-browser`).

### Per-browser formats (macOS)

```bash
# Chrome
yt-dlp --cookies-from-browser chrome <URL>

# Chromium
yt-dlp --cookies-from-browser chromium <URL>

# Microsoft Edge (Chromium-based; on macOS reads ~/Library/Application Support/Microsoft Edge/...)
yt-dlp --cookies-from-browser edge <URL>

# Brave
yt-dlp --cookies-from-browser brave <URL>

# Vivaldi
yt-dlp --cookies-from-browser vivaldi <URL>

# Opera / Opera GX
yt-dlp --cookies-from-browser opera <URL>

# Whale
yt-dlp --cookies-from-browser whale <URL>

# Safari (macOS only; reads ~/Library/Cookies/Cookies.binarycookies)
yt-dlp --cookies-from-browser safari <URL>

# Firefox — supports :PROFILE
yt-dlp --cookies-from-browser firefox <URL>
yt-dlp --cookies-from-browser firefox:default-release <URL>
yt-dlp --cookies-from-browser firefox:/Users/me/Library/Application\ Support/Firefox/Profiles/abc123.default-release <URL>

# Firefox — supports ::CONTAINER
yt-dlp --cookies-from-browser firefox::Personal <URL>
yt-dlp --cookies-from-browser firefox::none <URL>     # default container
yt-dlp --cookies-from-browser firefox:default-release::Work <URL>

# Chrome with a specific profile (Linux path shown; on macOS the path lives under
# ~/Library/Application Support/Google/Chrome/)
yt-dlp --cookies-from-browser chrome:"Profile 1" <URL>
yt-dlp --cookies-from-browser chrome:/Users/me/Library/Application\ Support/Google/Chrome/Profile\ 1 <URL>
```

Notes:
- On macOS, `--cookies-from-browser` may trigger a Keychain access prompt the first time, because Chrome/Edge/Brave/Vivaldi/Opera/Whale cookie DBs are encrypted with a key stored in the user's login keychain. The user must allow the prompt or the call will fail.
- Safari cookies are NOT encrypted with Keychain the same way; the binary cookies file is read directly.
- Edge is fully Chromium-based on macOS, so the format is identical to Chrome except for the binary name.
- For headless or sandboxed apps, `chrome`/`edge` will fail unless the app is allowed to read the user's keychain. Fall back to `safari` or a Netscape cookie file (`--cookies /path/to/cookies.txt`).

### Variants worth knowing
- `--cookies FILE` — Netscape cookies.txt (use when browser access is not viable; format documented at https://curl.haxx.se/docs/http-cookies.html).
- `--no-cookies-from-browser` — explicit disable.
- Multiple values: not supported. Use multiple yt-dlp invocations or merge cookies.txt files.

---

## 2. `--remote-components`

### Argument grammar

```
--remote-components COMPONENT
```

Repeatable. Recognized values:
- `ejs:npm` — fetch the `yt-dlp-ejs` JS solver scripts from npm.
- `ejs:github` — fetch the same scripts from the yt-dlp-ejs GitHub releases.

Default: no remote components are allowed (`--no-remote-components`).

```bash
# Allow both sources (cumulative — use the flag twice)
yt-dlp --remote-components ejs:npm --remote-components ejs:github <URL>

# Explicit deny after allowing
yt-dlp --remote-components ejs:npm --no-remote-components <URL>
```

### When you actually need it

If you ship the official `yt-dlp_macos` (or `yt-dlp.exe` / `yt-dlp_linux`) PyInstaller build, `yt-dlp-ejs` is already bundled — you do NOT need `--remote-components`. You only need it when:
- You use the bare `yt-dlp` zipimport binary on Unix.
- You use a third-party package that does not bundle EJ scripts.
- You want to auto-update EJ scripts between yt-dlp releases (npm or GitHub sources).

The companion JS runtime (Deno is default and enabled out of the box) is what actually runs the EJ scripts. You also need:
```
--js-runtimes deno[:/path/to/deno]      # default; only override if deno is not on PATH
--js-runtimes node[:/path/to/node]
--js-runtimes quickjs[:/path/to/qjs]
```
`bun` is supported but deprecated; QuickJS prior to 2025-04-26 is too slow for YouTube.

### macOS bundling implication
If you ship `yt-dlp_macos` inside your .app, you do NOT need `--remote-components`. If you ship the zipimport `yt-dlp` and want zero network at first run, bundle `yt-dlp-ejs` (pip-installable) into `Contents/Resources/` and add it to `PYTHONPATH` instead.

---

## 3. Bundling `yt-dlp` in a macOS `.app`

### Official macOS binary

`yt-dlp_macos` — Universal MacOS 10.15+ standalone executable, PyInstaller-bundled, GPLv3+.
URL: `https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos`

Source tarball (`yt-dlp.tar.gz`) is Unlicense and is what you want if you must avoid GPLv3 in your app distribution (e.g., App Store). The tarball is the Python source; you would `pip install` it on the user's Mac, which is generally not what an app bundle does.

### Layout conventions

Two common locations inside `MyApp.app`:

```
MyApp.app/Contents/
  Info.plist
  MacOS/
    MyApp                 # main executable (IINA: iina)
  Resources/
    yt-dlp_macos          # <-- bundled binary, chmod 755
    yt-dlp-ejs/           # optional, only if not using PyInstaller build
    deno                  # optional JS runtime; Deno is bundled inside yt-dlp_macos
```

Pick a location; conventions are not enforced. The most common is `Contents/Resources/yt-dlp_macos` (keeps the binary out of the dyld search path used by `Contents/MacOS/`).

### Two invocation patterns

#### A. Invoke by absolute path (simplest)

```swift
// Swift
let bundleYtDlp = Bundle.main.url(
    forResource: "yt-dlp_macos",
    withExtension: nil,
    subdirectory: "Resources"
)!.path

// Use as a child process:
let proc = Process()
proc.executableURL = URL(fileURLWithPath: bundleYtDlp)
proc.arguments = ["--dump-json", urlString]
try proc.run()
```

```objc
// Objective-C (used by mpv/ytdl_hook.lua shell-out)
NSString *p = [[NSBundle mainBundle] pathForResource:@"yt-dlp_macos"
                                              ofType:nil
                                         inDirectory:@"Resources"];
```

#### B. Add to PATH so mpv's `ytdl_hook.lua` finds it by name (current IINA approach)

mpv's hook script looks for executables named `yt-dlp`, `yt-dlp_x86`, then `youtube-dl` in `PATH` (configurable via `ytdl_path`). To make a bundled binary discoverable, prepend its directory to `PATH` before launching mpv:

```swift
// IINA already does this in PlayerCore.swift:628-636:
let oldPath = String(cString: getenv("PATH")!)
var path = Utility.exeDirURL.path + ":" + oldPath       // Contents/MacOS
if let custom = Preference.string(for: .ytdlSearchPath), !custom.isEmpty {
    path = custom + ":" + path
}
setenv("PATH", path, 1)
```

To use a binary under `Resources/` instead, symlink or copy it into the same directory the app prepends:

```bash
# At build time (Xcode Run Script phase):
cp -f "$PROJECT_DIR/deps/executable/yt-dlp_macos" \
      "$BUILT_PRODUCTS_DIR/$EXECUTABLE_FOLDER_PATH/yt-dlp"
chmod +x "$BUILT_PRODUCTS_DIR/$EXECUTABLE_FOLDER_PATH/yt-dlp"
# or symlink:
ln -sf "../Resources/yt-dlp_macos" \
       "$BUILT_PRODUCTS_DIR/$EXECUTABLE_FOLDER_PATH/yt-dlp"
```

Or extend the PATH prefix in Swift to include `Contents/Resources`:

```swift
let resources = Bundle.main.resourceURL!.path
let newPath = "\(Utility.exeDirURL.path):\(resources):\(oldPath)"
setenv("PATH", newPath, 1)
```

Notes:
- Gatekeeper / notarization: any bundled binary that runs at launch must be notarized with the app, or it will be blocked on first run. `yt-dlp_macos` itself does not require ad-hoc signing by you, but the enclosing `.app` does.
- Quarantine: downloaded `yt-dlp_macos` may carry the com.apple.quarantine xattr; strip it inside the bundle (`xattr -d com.apple.quarantine ...`) and rebuild into the app yourself.
- `yt-dlp -U` (self-update) only works for the standalone binary. The .app bundle will be replaced on next install, so do not rely on self-update for bundled copies; ship updates via the app.
- macOS sandbox: if the app is sandboxed (App Store), `Process` cannot read arbitrary user paths (e.g., `~/Library/Application Support/Google/Chrome/...`) without explicit user-selected file entitlements. `--cookies-from-browser chrome` will not work in a sandboxed build. `safari` is also blocked. A non-sandboxed build (like IINA's) is required for full cookie support.

### Optional: pre-extract a cookies.txt once for sandboxed builds

```bash
# At runtime, with the user's consent, run yt-dlp once to dump cookies,
# then subsequent calls use --cookies /path/to/cookies.txt.
yt-dlp --cookies-from-browser chrome --cookies ~/Library/Application\ Support/MyApp/cookies.txt --no-download <URL>
```

---

## 4. Passing yt-dlp options through libmpv / mpv

### Option grammar

```
--ytdl-raw-options=<key>=<value>[,<key>=<value>[,...]]
```

- Comma-separated list of `key=value` pairs.
- Options without an argument must still have a trailing `=`.
- Special characters in values must be shell-escaped; in mpv's parser they are also subject to suboption escaping (use `[http://...]` quoting for `:`).
- "There is no sanity checking so it's possible to break things." (mpv manual)

### libmpv C API

```c
// Set the whole list in one call:
mpv_set_option_string(mpv, "ytdl-raw-options",
    "cookies-from-browser=chrome,"
    "remote-components=ejs:github,"
    "format=bestvideo*+bestaudio/best,"
    "force-ipv6=");                       // trailing = required for flag options

// Or append incrementally:
mpv_set_option_string(mpv, "ytdl-raw-options-append",
    "cookies-from-browser=firefox:default-release::none");
```

### libmpv Swift wrapper (IINA-style)

```swift
// IINA exposes MPVOption.ytdlRawOptions in MPVOption.swift:163
mpv.setOption("ytdl-raw-options",
              "cookies-from-browser=chrome,remote-components=ejs:github,format=bv*+ba/b")

// To pass a flag option (no value):
mpv.setOption("ytdl-raw-options", "force-ipv6=")
```

### Direct mpv command line

```bash
# Pass cookies from Chrome
mpv --ytdl-raw-options=cookies-from-browser=chrome 'https://example.com/watch?v=...'

# Pass a value containing commas / colons (suboption escaping)
mpv --ytdl-raw-options=proxy='[http://127.0.0.1:3128]' 'https://...'
mpv --ytdl-raw-options=username=user,password=pass 'https://...'

# Append to the option list instead of replacing it
mpv --ytdl-raw-options-append=cookies-from-browser=firefox:default 'https://...'

# Allow remote EJ scripts (only needed for non-bundled yt-dlp-ejs)
mpv --ytdl-raw-options=remote-components=ejs:github 'https://...'
```

### mpv config file (`~/.config/mpv/mpv.conf`)

```ini
ytdl-raw-options=cookies-from-browser=chrome,remote-components=ejs:github,format=bv*+ba/b
```

### How mpv spawns yt-dlp

`ytdl_hook.lua` (bundled in mpv) translates `--ytdl-raw-options` into argv for the `yt-dlp` process:

```lua
-- mpv/player/lua/ytdl_hook.lua (paraphrased)
local opts = mp.get_property_native("options/ytdl-raw-options", {})
-- merges with ytdl_format, etc., then:
local cmd = { "yt-dlp" }   -- or whatever ytdl_path resolves to
for k, v in pairs(opts) do
    if v == "" then table.insert(cmd, "--" .. k)
    else table.insert(cmd, "--" .. k .. "=" .. tostring(v)) end
end
```

`ytdl_path` defaults to `yt-dlp`, then `yt-dlp_x86`, then `youtube-dl`, looked up on `PATH` and in mpv's config dir. This is why IINA's `PlayerCore.startMPV()` prepends the bundle's binary directory to `PATH` — so the `yt-dlp` name resolves to the bundled `yt-dlp_macos`.

### Worked examples

```bash
# 1. Use bundled Chrome cookies and request best separate streams merged:
mpv --ytdl-raw-options=cookies-from-browser=chrome,format='bv*+ba/b' \
    'https://www.youtube.com/watch?v=BaW_jenozKc'

# 2. Use bundled Safari cookies (no Keychain prompt for encrypted v20 cookies on macOS Safari 14+):
mpv --ytdl-raw-options=cookies-from-browser=safari \
    'https://www.youtube.com/watch?v=BaW_jenozKc'

# 3. Use a specific Firefox profile + container, fall back to a non-container profile:
mpv --ytdl-raw-options='cookies-from-browser=firefox:default-release::Work' \
    'https://www.youtube.com/watch?v=BaW_jenozKc'

# 4. Use a pre-extracted Netscape cookies.txt (sandbox-friendly):
mpv --ytdl-raw-options='cookies=/Users/me/Library/Application Support/iina/cookies.txt' \
    'https://www.youtube.com/watch?v=BaW_jenozKc'

# 5. For a pip-installed yt-dlp without bundled EJ scripts:
mpv --ytdl-raw-options='remote-components=ejs:github,js-runtimes=node:/usr/local/bin/node' \
    'https://www.youtube.com/watch?v=BaW_jenozKc'
```

---

## 5. Quick reference cheat sheet

| Need | Flag |
|---|---|
| Chrome cookies (default profile) | `--cookies-from-browser chrome` |
| Chrome cookies (named profile) | `--cookies-from-browser "chrome:Profile 1"` |
| Edge cookies (default) | `--cookies-from-browser edge` |
| Firefox default profile | `--cookies-from-browser firefox` |
| Firefox specific profile | `--cookies-from-browser firefox:default-release` |
| Firefox specific container | `--cookies-from-browser firefox::Personal` |
| Safari cookies (macOS only) | `--cookies-from-browser safari` |
| Disable browser cookies | `--no-cookies-from-browser` |
| Use cookies.txt | `--cookies /path/cookies.txt` |
| Fetch EJ from npm at runtime | `--remote-components ejs:npm` |
| Fetch EJ from GitHub at runtime | `--remote-components ejs:github` |
| Disable all remote components | `--no-remote-components` |
| Custom JS runtime path | `--js-runtimes deno:/abs/path/to/deno` |
| Pass through libmpv (C) | `mpv_set_option_string(mpv, "ytdl-raw-options", "cookies-from-browser=chrome,remote-components=ejs:github")` |
| Pass through libmpv (Swift) | `mpv.setOption("ytdl-raw-options", "cookies-from-browser=chrome,remote-components=ejs:github")` |
| Bundle path in Swift | `Bundle.main.url(forResource:"yt-dlp_macos", withExtension:nil, subdirectory:"Resources")!.path` |
| Prepend bundle to PATH (IINA pattern) | `setenv("PATH", Utility.exeDirURL.path + ":" + oldPath, 1)` |

---

## 6. Verification commands

```bash
# Confirm bundled binary works:
"$APP/Contents/Resources/yt-dlp_macos" --version

# Confirm browser cookie paths are reachable:
yt-dlp --cookies-from-browser chrome --dump-json --no-download 'https://www.youtube.com/watch?v=BaW_jenozKc' 2>&1 | head

# Confirm mpv passes options through:
mpv --ytdl-raw-options=force-ipv6= --no-config 'https://www.youtube.com/watch?v=BaW_jenozKc' --idle=no 2>&1 | grep -i yt-dlp

# Confirm EJS scripts are bundled (no remote fetch needed):
yt-dlp_macos --remote-components= --js-runtimes= --verbose 'https://www.youtube.com/watch?v=BaW_jenozKc' 2>&1 | grep -i 'ejs\|player'
```

---

## 7. Gotchas (recorded from this IINA repo's current state)

- `iina/PlayerCore.swift:629-636` — IINA today symlinks a system-installed `yt-dlp` to `deps/executable/youtube-dl` (see `README.md:101-106`). Bundling means replacing this symlink with a real `yt-dlp_macos` checked into `deps/executable/` (or downloaded at build time).
- `iina/MPVOption.swift:1050-1053` exposes the `cookies` / `cookies-file` mpv options (which are separate from yt-dlp's `--cookies` and apply to libavformat). The yt-dlp-specific path is `ytdl-raw-options=cookies=...` or `ytdl-raw-options=cookies-from-browser=...`.
- `iina/MPVOption.swift:162-163` — the Swift constant is `MPVOption.ytdlRawOptions`; pass a comma-joined `key=value` string.
- `iina/AppData.swift:59` still points the help link at youtube-dl's old README; for any new UI strings about cookies/remote-components, point at the yt-dlp README sections cited above.
- `iina/PluginStorePanel.swift:18` advertises an "Official plugin for playing online media via yt-dlp / youtube-dl. The built-in youtube-dl support will be disabled when this plugin is enabled." — the bundled-binary change is orthogonal to this plugin; mpv's `ytdl=no` switch is the disable knob.
