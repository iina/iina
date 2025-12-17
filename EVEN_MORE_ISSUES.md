# Even More Issues Found - Round 3

## 🔧 High Priority Regression Bugs

### 1. Issue #5831: Double Click to Play Audio from Playlist Not Working
**Priority**: HIGH - Regression bug, affects core functionality

**Problem**: In music mode, double-clicking an audio file in the playlist selects it and resets transport to 00:00 but doesn't start playing. Works in 1.3.5, broken in 1.4.1.

**Root Cause**: Likely a regression in playlist double-click handling or play command after selection.

**Fix Needed**:
- Check double-click handler in playlist view
- Ensure play command is sent after selection
- Verify music mode playlist interaction code

**Files to Find**:
- Playlist view double-click handler
- Music mode playlist code

---

### 2. Issue #5850: "Add files in same folder automatically" Plays Odd Files Only
**Priority**: HIGH - Regression bug, affects playlist functionality

**Problem**: When auto-adding files from a folder, IINA plays every odd file (1, 3, 5...) but skips even files (2, 4, 6...). This is a regression in 1.4.1.

**Root Cause**: Likely an off-by-one error or incorrect indexing when iterating through files in a folder.

**Fix Needed**:
- Check file enumeration logic
- Verify playlist indexing when auto-adding files
- Check for any filtering that might skip files

**Files to Find**:
- Auto-add files from folder code
- Playlist file enumeration

---

### 3. Issue #5719: Can't Access Playlist if First Stream in .m3u Fails
**Priority**: HIGH - UX regression

**Problem**: When opening an .m3u playlist, if the first stream is slow/unresponsive, the window doesn't open and playlist is inaccessible. Previously (pre-1.4.0), the window would open immediately.

**Root Cause**: Window opening logic now waits for first stream to load before showing window.

**Fix Needed**:
- Open window immediately when playlist is loaded
- Load playlist content upfront, don't wait for first stream
- Allow accessing playlist even if first stream is loading

**Files to Find**:
- Playlist loading code
- Window opening logic for playlists

---

## 🐛 Medium Priority Bugs

### 4. Issue #4217: Seek Twice Automatically with Custom Key Bindings
**Priority**: MEDIUM - Key binding bug

**Problem**: When customizing key bindings from IINA Default, seek forward commands (3s, 30s) execute twice - once for the custom binding and once for the default (2s).

**Root Cause**: Default key binding not being removed when custom binding is added, or both bindings are active.

**Fix Needed**:
- Ensure default bindings are removed when custom ones are set
- Check key binding conflict resolution
- Verify binding replacement logic

**Files to Find**:
- Key binding configuration code
- Default binding removal logic

---

### 5. Issue #5662: Some Translated Strings Still in English
**Priority**: MEDIUM - Localization bug

**Problem**: Some UI strings remain in English even when translations are 100% complete on Crowdin. This is a synchronization issue between translations and code.

**Root Cause**: 
- Missing `NSLocalizedString` calls
- Hardcoded English strings
- Translation keys not matching Crowdin

**Fix Needed**:
- Find hardcoded English strings
- Replace with `NSLocalizedString` calls
- Verify all UI strings use localization

**Files to Find**:
- Preference UI code
- Menu items
- Plugin-related UI

---

### 6. Issue #5170: Automatically Open File on Launch
**Priority**: LOW - Feature request / behavior question

**Problem**: User wants to know if IINA can automatically open a file (like iptv.m3u) when the app launches.

**Root Cause**: Not a bug, but a feature request. Could be implemented.

**Fix Needed**:
- Add preference for auto-opening file on launch
- Or document if this is already possible

---

## 📋 Summary

**New Issues Found**: 6 additional issues

**Priority Breakdown**:
- **High** (3): #5831, #5850, #5719 - All regression bugs affecting core functionality
- **Medium** (2): #4217, #5662 - Key bindings and localization
- **Low** (1): #5170 - Feature request

**Total Issues Status**:
- **Fixed**: 3 issues (#2193, #5658, #5829)
- **Identified for fixing**: 17 issues total
- **UPnP/DLNA feature**: Implemented (addresses 4 feature requests)

---

## Implementation Priority

1. **#5850** - Auto-add files regression (affects many users)
2. **#5831** - Double-click playlist regression (affects music mode)
3. **#5719** - Playlist access regression (affects .m3u users)
4. **#4217** - Key binding seek bug
5. **#5662** - Localization strings

---

## Notes

- All three high-priority issues are **regressions** introduced in recent versions
- These should be relatively straightforward to fix (reverting or fixing the regression)
- The playlist issues (#5831, #5850, #5719) are likely related to recent playlist changes

