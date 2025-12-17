# Additional Issues Found - Analysis

## 🔧 Fixable Issues (Priority Order)

### 1. Issue #5113: External Audio Loading with .AC3 Directory
**Priority**: MEDIUM - File extension detection bug

**Problem**: When loading external audio, if the directory name ends with `.AC3`, IINA treats it as a file extension and tries to open the folder as an audio file instead of showing its contents.

**Root Cause**: File extension detection logic likely uses `pathExtension` which would return `.AC3` for a folder named `Tv.Show.Name.AC3`.

**Fix Needed**:
- Check if the selected path is actually a directory before treating it as a file
- Use `FileManager` to check if path is a directory
- Only apply file extension filtering to actual files, not directories

**Files to Find**:
- External audio loading code (likely in menu actions or file picker)

---

### 2. Issue #5491: Timestamp Not Refreshed on Frame-by-Frame
**Priority**: MEDIUM - UI update bug

**Problem**: When using frame-by-frame navigation (`.` key), the timestamp display doesn't update immediately, often delayed by a few seconds.

**Root Cause**: The timestamp update might be throttled or only updated on certain events, not on frame-step commands.

**Fix Needed**:
- Ensure timestamp is updated immediately after frame-step command
- Force UI sync after frame-step operations
- Check if `syncUITime()` is called after frame-step

**Files to Find**:
- Frame-step command handler
- Timestamp update/sync code

---

### 3. Issue #4691: Wrong Tooltip in Playlist Panel
**Priority**: LOW - UI bug

**Problem**: The `+` button in playlist panel sometimes shows "Toggle Picture-in-Picture" tooltip instead of "Add to playlist" when OSC is positioned below.

**Root Cause**: Tooltip is likely being picked up from the OSC button underneath due to overlapping hit areas or z-order issues.

**Fix Needed**:
- Ensure playlist panel buttons have proper tooltip set
- Check z-order/layering of playlist panel vs OSC
- Verify tooltip is explicitly set on playlist buttons

**Files to Find**:
- Playlist panel UI code
- Tooltip configuration

---

### 4. Issue #3010: Window Closes on Playback Error
**Priority**: MEDIUM - UX improvement

**Problem**: When a file/stream fails to open, the window closes, making it impossible to see the URL in the playlist or take actions on the failed item.

**Root Cause**: Error handling likely closes the window when playback fails, especially for single-item playlists.

**Fix Needed**:
- Keep window open when playback errors occur
- Show error message but maintain window state
- Allow user to see playlist and retry or remove failed items

**Files to Find**:
- Error handling code for playback failures
- Window closing logic

---

### 5. Issue #3500: Subtitle Language Preference Ignored
**Priority**: MEDIUM - Preference bug

**Problem**: Subtitle language preference (e.g., Czech) is ignored, always loading English subtitles automatically.

**Root Cause**: Subtitle auto-loading logic might not be checking preferences correctly, or preference matching logic is flawed.

**Fix Needed**:
- Verify subtitle preference is read correctly
- Check subtitle auto-loading logic uses preference
- Ensure language code matching works (CZE, CES, CS should all match Czech)

**Files to Find**:
- Subtitle preference code
- Auto-load subtitle logic

---

### 6. Issue #5438: VLC Shuffle Shortcut Conflict
**Priority**: LOW - Key binding conflict

**Problem**: VLC keybind preset has duplicate `Meta+z` bindings, causing shuffle (`z`) to not work.

**Root Cause**: Key binding conflict - `Meta+z` is bound to both shuffle and window-scale, causing the first match to take precedence.

**Fix Needed**:
- Detect and warn about duplicate key bindings
- Or ensure shuffle binding is checked/processed correctly
- Fix default VLC keybind preset to remove duplicate

**Files to Find**:
- Key binding configuration
- VLC preset file

---

## 📋 Summary

**Total Issues Found**: 6 additional fixable issues

**Priority Breakdown**:
- **High**: None (already fixed the critical ones)
- **Medium**: 4 issues (#5113, #5491, #3010, #3500)
- **Low**: 2 issues (#4691, #5438)

**Estimated Complexity**:
- **Easy** (1-2 hours): #5113, #4691
- **Medium** (2-4 hours): #5491, #3010, #3500
- **Complex** (4+ hours): #5438 (requires key binding system understanding)

---

## Next Steps

1. Start with easiest fixes (#5113, #4691)
2. Then tackle medium complexity (#5491, #3010, #3500)
3. Investigate #5438 if time permits

