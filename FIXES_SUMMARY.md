# Fixes for IINA Issues

## Summary

Found several issues we can fix:
1. ✅ **UPnP/DLNA Support** - Already implemented in PR #5852
2. 🔒 **RTSP Password Security** (#2193) - High priority security fix
3. 🐛 **OpenSubtitles Question Mark Bug** (#5658) - Medium priority bug fix

## Issue #2193: RTSP Password in Plaintext

**Problem**: URLs with credentials (e.g., `rtsp://user:pass@host/path`) are stored in playback history with passwords in plaintext.

**Fix**: Sanitize URLs before saving to history by removing user credentials from the URL.

**Files to modify**:
- `HistoryController.swift` - Sanitize URL before creating PlaybackHistory
- Add URL extension to sanitize credentials

## Issue #5658: OpenSubtitles Network Error with Question Marks

**Problem**: Files with question marks (?) in the name cause "network error" when searching OpenSubtitles.

**Fix**: URL-encode the query parameter before sending to OpenSubtitles API.

**Files to modify**:
- `OpenSubClient.swift` - URL-encode the query parameter in `subtitles()` method

## Implementation Plan

1. Add URL sanitization extension
2. Fix HistoryController to use sanitized URLs
3. Fix OpenSubClient to URL-encode query parameter
4. Test both fixes
5. Add to PR or create separate PRs

