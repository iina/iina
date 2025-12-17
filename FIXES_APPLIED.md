# Fixes Applied

## ✅ Issue #2193: RTSP Password Security Fix

**Problem**: URLs with credentials (e.g., `rtsp://user:pass@host/path`) were stored in playback history with passwords in plaintext.

**Solution**: 
- Added `URL.sanitizedForHistory` extension method that removes user credentials from URLs
- Modified `HistoryController.add()` to sanitize URLs before storing in history
- Credentials are still stored securely in Keychain (already implemented), but not in history

**Files Modified**:
- `iina/Extensions.swift` - Added `sanitizedForHistory` property
- `iina/HistoryController.swift` - Use sanitized URL when creating history entries

**Testing**:
1. Open an RTSP stream with credentials: `rtsp://user:pass@host/path`
2. Check playback history - should show `rtsp://host/path` (no credentials)
3. Credentials should still be in Keychain for future use

---

## ✅ Issue #5658: OpenSubtitles Question Mark Fix

**Problem**: Files with question marks (?) in the name caused "network error" when searching OpenSubtitles.

**Solution**:
- URL-encode the query parameter before sending to OpenSubtitles API
- Ensures special characters like `?` are properly encoded

**Files Modified**:
- `iina/OpenSubClient.swift` - URL-encode query parameter in `subtitles()` method

**Testing**:
1. Create a file with `?` in the name (e.g., `video?.mkv`)
2. Try to find subtitles from OpenSubtitles
3. Should work without network error

---

## Next Steps

1. **Test both fixes** thoroughly
2. **Add to existing PR** or create separate PRs for these fixes
3. **Comment on original issues** linking to the fixes:
   - Issue #2193: Security fix for RTSP passwords
   - Issue #5658: Fix for OpenSubtitles question mark bug

## Related Issues We Can Address

- **Issue #5843**: Window not shown when video can't decode (more complex, needs investigation)
- **UPnP/DLNA Issues**: Already addressed in PR #5852

