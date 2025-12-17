# Additional Issues to Fix

## Summary

Found several more fixable issues after reviewing the IINA GitHub repository:

### ✅ Already Fixed
- **#2193**: RTSP password in plaintext - ✅ Fixed
- **#5658**: OpenSubtitles question mark - ✅ Fixed

### 🔧 High Priority Fixes

#### 1. Issue #5829: History with NAS causes launch failure
**Priority**: HIGH - Blocks app launch

**Problem**: When playback history contains URLs from a NAS that's powered off, IINA gets stuck in an infinite loading loop and crashes on launch.

**Root Cause**: History reading might be trying to access URLs or validate them, causing blocking operations.

**Fix Needed**: 
- Add error handling in `HistoryController.read()` to gracefully handle corrupted or inaccessible history entries
- Filter out invalid/unreachable URLs when reading history
- Add timeout for URL validation if it's being done

**Files to Modify**:
- `iina/HistoryController.swift` - Add error handling and filtering

---

#### 2. Issue #5099: "Pause when media is opened" not respected for audio
**Priority**: MEDIUM - User experience bug

**Problem**: For audio files without cover art, the "pause when media is opened" setting is not respected because `MPV_EVENT_VIDEO_RECONFIG` fires before `MPV_EVENT_FILE_LOADED`, setting `justOpenedFile` to false.

**Root Cause**: 
- `justOpenedFile` is set to `true` when opening file (line 496)
- For audio-only files, `playbackRestarted()` might be called before `fileLoaded()`, setting `justOpenedFile` to false (line 2204)
- `fileLoaded()` checks `justOpenedFile` to determine if it should pause

**Fix Needed**:
- Don't set `justOpenedFile = false` in `playbackRestarted()` if `fileLoaded()` hasn't been called yet
- Or check if file is audio-only and handle pause differently

**Files to Modify**:
- `iina/PlayerCore.swift` - Fix `justOpenedFile` logic for audio files

---

#### 3. Issue #4862: Incorrect handling of % in URL under Ventura
**Priority**: MEDIUM - URL encoding bug

**Problem**: URLs containing `%25` (encoded `%`) fail to open because the code double-encodes them. When a URL like `https://example.com/%25foo%20bar.mkv` is processed, it's decoded to `%foo bar.mkv` and then re-encoding fails.

**Root Cause**: The URL encoding logic in `PlayerCore.openURLString()` or `OpenURLWindowController.getURL()` is decoding already-encoded URLs and then trying to re-encode them.

**Fix Needed**:
- Check if URL is already properly encoded before attempting to encode
- Don't decode and re-encode URLs that are already valid
- Handle `%25` (encoded `%`) correctly

**Files to Modify**:
- `iina/PlayerCore.swift` - Fix URL encoding logic
- `iina/OpenURLWindowController.swift` - Fix URL encoding

---

#### 4. Issue #3324: Open URL with whitespace doesn't work
**Priority**: MEDIUM - URL encoding bug

**Problem**: URLs with whitespace in paths (e.g., FTP URLs with spaces in directory names) fail to open.

**Root Cause**: Whitespace in URLs needs to be percent-encoded (`%20`), but the current encoding might not handle all cases.

**Fix Needed**:
- Ensure all whitespace in URL paths is properly encoded
- Test with FTP URLs containing spaces

**Files to Modify**:
- `iina/PlayerCore.swift` - Improve URL encoding
- `iina/OpenURLWindowController.swift` - Fix whitespace encoding

---

### 📋 Medium Priority Fixes

#### 5. Issue #5177: UI improvements for network stream playlists
**Priority**: MEDIUM - UX improvement

**Problem**: When opening a playlist of network streams:
1. Default album art not displayed (black screen)
2. "Buffering" message never shown
3. Window doesn't open until stream loads
4. Music mode not automatically enabled

**Fix Needed**: Multiple UI improvements for network stream handling.

---

#### 6. Issue #5690: Constraint errors on macOS 26
**Priority**: LOW - macOS compatibility issue

**Problem**: Constraint errors in open panel on macOS 26 Tahoe. Likely a macOS bug, but we could add workarounds.

**Fix Needed**: Investigate and add workarounds if possible.

---

## Implementation Priority

1. **#5829** - History launch failure (blocks app)
2. **#5099** - Pause when opened (user experience)
3. **#4862** - URL % encoding (affects URL opening)
4. **#3324** - URL whitespace (affects URL opening)
5. **#5177** - Network stream UI (UX improvement)

---

## Next Steps

1. Fix issue #5829 (history launch failure) - highest priority
2. Fix issue #5099 (pause when opened) - user experience
3. Fix URL encoding issues (#4862, #3324) - together since they're related
4. Test all fixes thoroughly
5. Add to PR or create separate PRs

