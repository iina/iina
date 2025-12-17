# Issues Found and Fixes

## Summary of Issues Found

### 1. ✅ UPnP/DLNA Support (Issues #2173, #906, #3565, #3442)
**Status**: Already implemented in our PR #5852!

These are the exact feature requests we've addressed:
- Issue #2173: "UPnP / DLNA support?"
- Issue #906: "would you please add DLNA support"
- Issue #3565: "Request to support DLNA protocol"
- Issue #3442: "Do you have any plan to support DLNA?"

**Action**: Our PR addresses all of these. We can comment on these issues linking to our PR.

---

### 2. 🔒 Security Issue: RTSP Password in Plaintext (Issue #2193)
**Priority**: HIGH - Security vulnerability

**Problem**: 
- When opening RTSP streams with credentials (e.g., `rtsp://user:pass@host/path`), the full URL including password is stored in playback history
- Passwords are stored in plaintext in the history file
- Should use Keychain for passwords, not store them in URLs

**Location**: 
- `PlaybackHistory.swift` - stores the full URL
- `HistoryController.swift` - saves history entries
- `OpenURLWindowController.swift` - constructs URLs with credentials

**Fix Needed**:
- Sanitize URLs before saving to history (remove user:pass@)
- Store credentials separately in Keychain if needed
- Display sanitized URLs in history UI

---

### 3. 🐛 OpenSubtitles Network Error with Question Marks (Issue #5658)
**Priority**: MEDIUM - Bug affecting subtitle search

**Problem**:
- Files with question marks (?) in the name cause "network error" when searching OpenSubtitles
- Question marks need to be URL-encoded in the API request

**Location**:
- `OpenSubSubtitle.swift` line 319: `let searchString = url.isFileURL ? url.deletingPathExtension().lastPathComponent : mediaTitle`
- `OpenSubClient.swift` - needs to URL-encode the query parameter

**Fix Needed**:
- URL-encode the search string before sending to OpenSubtitles API
- Handle special characters properly in the query parameter

---

### 4. 🐛 Window Not Shown When Video Can't Decode (Issue #5843)
**Priority**: MEDIUM - UX bug

**Problem**:
- When a video can't be decoded (e.g., AV1 track issues), the window doesn't reopen even though audio plays
- User sees no window but audio is playing

**Location**: 
- Window management code when playback fails
- Need to ensure window is shown even if video decode fails

**Fix Needed**:
- Ensure window is displayed even when video decoding fails
- Show error message or placeholder when video can't decode

---

## Recommended Fix Order

1. **RTSP Password Security** (#2193) - Security issue, should be fixed first
2. **OpenSubtitles Question Mark** (#5658) - Easy fix, affects user experience
3. **Window Display on Decode Failure** (#5843) - UX improvement

---

## Next Steps

1. Implement fixes for issues #2193 and #5658 (easier ones)
2. Test fixes thoroughly
3. Add fixes to our PR or create separate PRs
4. Comment on the original issues linking to fixes

