# Final Round - Additional Issues Found

## 🔧 High Priority Issues (3)

### 1. Issue #5735: Audio Plays but UI Shows Up Late
**Priority**: HIGH - UX regression

**Problem**: When opening IINA by double-clicking a file or dragging a file in, audio starts playing immediately but the UI window doesn't appear until several seconds later.

**Root Cause**: Window initialization/display is delayed, possibly waiting for video track or some other condition before showing.

**Fix Needed**:
- Show window immediately when file starts loading
- Don't wait for video track or other conditions
- Ensure window is displayed as soon as playback starts

**Files to Find**:
- Window opening/display logic
- File loading initialization

---

### 2. Issue #5815: Window Not Displayed for Audio with WebP Cover Art
**Priority**: HIGH - Window display bug

**Problem**: Audio files with embedded WebP cover art play audio but don't show the player window. IINA can't display WebP, so it should show window with empty artwork pane.

**Root Cause**: Window display logic might be conditional on having displayable artwork, and WebP failure causes window not to show.

**Fix Needed**:
- Show window even if artwork can't be displayed
- Handle WebP artwork gracefully (show empty/placeholder)
- Don't hide window on artwork loading failure

**Files to Find**:
- Artwork loading/display code
- Window display logic for audio files

---

### 3. Issue #5755: Right Arrow Key Seeks Then Restarts Video
**Priority**: HIGH - Key binding bug

**Problem**: Pressing right arrow (seek forward 5s) correctly seeks forward, but then immediately jumps back to the beginning. Log shows "Playback restarted" after seek.

**Root Cause**: The seek command might be triggering a playback restart that resets position, or there's a conflict with another command.

**Fix Needed**:
- Check seek command implementation
- Ensure playback restart doesn't reset position after seek
- Verify no conflicting key bindings

**Files to Find**:
- Seek command handler
- Playback restart logic

---

## 🐛 Medium Priority Issues (3)

### 4. Issue #5716: Always On Top Doesn't Stick
**Priority**: MEDIUM - Preference bug

**Problem**: "Always Float on Top while Playing" setting works during session, but after closing and reopening IINA, the setting is checked but doesn't actually work.

**Root Cause**: Preference is saved but not properly restored/applied on window creation.

**Fix Needed**:
- Ensure "Always On Top" preference is applied when window is created
- Check preference restoration on app launch
- Verify window level is set correctly from preference

**Files to Find**:
- Preference restoration code
- Window level setting on creation

---

### 5. Issue #3322: Remember Video Size Not Working
**Priority**: MEDIUM - Preference bug (older issue)

**Problem**: Window size is not remembered between sessions. Always resets to default 640px width when reopening videos, even with "Resize window to fit video size: Disabled".

**Root Cause**: Window size saving/restoration logic might be broken or not working with the current window management.

**Fix Needed**:
- Fix window size saving
- Ensure size is restored on file open
- Check window size preference handling

**Files to Find**:
- Window size saving/restoration
- Window size preference code

---

### 6. Issue #4559: Thumbnail Visible with OSC Hidden
**Priority**: LOW - UI bug (rare)

**Problem**: Thumbnail preview remains visible even when OSC is hidden. Very rare occurrence.

**Root Cause**: Thumbnail visibility not properly tied to OSC visibility state.

**Fix Needed**:
- Ensure thumbnail is hidden when OSC is hidden
- Check thumbnail visibility state management

**Files to Find**:
- OSC visibility code
- Thumbnail display logic

---

## 📋 Summary

**New Issues Found**: 6 additional issues

**Priority Breakdown**:
- **High** (3): #5735, #5815, #5755 - All affect core functionality
- **Medium** (2): #5716, #3322 - Preference/restoration bugs
- **Low** (1): #4559 - Rare UI bug

**Total Issues Status**:
- **Fixed**: 3 issues (#2193, #5658, #5829)
- **Identified for fixing**: 22 issues total
- **UPnP/DLNA feature**: Implemented (addresses 4 feature requests)

---

## Key Observations

1. **Window Display Issues**: Multiple issues (#5735, #5815) related to window not showing when it should
2. **Preference Persistence**: Issues with preferences not sticking (#5716, #3322)
3. **Seek/Playback Bugs**: Issue #5755 shows playback restart after seek, which is problematic

---

## Updated Priority List

### Critical (Do First)
1. #5850 - Auto-add files regression
2. #5831 - Double-click playlist regression  
3. #5719 - Playlist access regression
4. #5735 - UI shows late (regression)
5. #5815 - Window not shown for WebP audio
6. #5755 - Seek then restart bug

### High Priority
7. #5099 - Pause when opened
8. #4862 - URL % encoding
9. #3324 - URL whitespace

### Medium Priority
10. #5113 - External audio .AC3
11. #5491 - Frame-by-frame timestamp
12. #3010 - Window on error
13. #3500 - Subtitle preference
14. #4217 - Key binding seek
15. #5716 - Always on top
16. #3322 - Remember window size

