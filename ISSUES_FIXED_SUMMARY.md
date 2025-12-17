# Issues Fixed Summary

## ✅ Fixed Issues

### 1. Issue #2193: RTSP Password Security
**Status**: ✅ Fixed  
**Fix**: Sanitize URLs before saving to playback history to remove credentials  
**Files**: `Extensions.swift`, `HistoryController.swift`

### 2. Issue #5658: OpenSubtitles Question Mark Bug
**Status**: ✅ Fixed  
**Fix**: URL-encode query parameter before sending to OpenSubtitles API  
**Files**: `OpenSubClient.swift`

### 3. Issue #5829: History with NAS Causes Launch Failure
**Status**: ✅ Fixed  
**Fix**: Filter invalid history entries during read, don't block on network operations  
**Files**: `HistoryController.swift`

---

## 🔧 Additional Issues Found (To Fix)

### High Priority
- **#5099**: "Pause when media is opened" not respected for audio files
- **#4862**: Incorrect handling of % in URL under Ventura
- **#3324**: Open URL with whitespace doesn't work

### Medium Priority
- **#5177**: UI improvements for network stream playlists
- **#5690**: Constraint errors on macOS 26 (likely macOS bug)

See `MORE_ISSUES_TO_FIX.md` for detailed analysis.

---

## Total Issues Addressed

- **3 issues fixed** ✅
- **5+ issues identified** for future fixes
- **UPnP/DLNA feature** implemented (addresses issues #2173, #906, #3565, #3442)

---

## Next Steps

1. Test all fixes thoroughly
2. Fix remaining high-priority issues (#5099, #4862, #3324)
3. Add fixes to PR or create separate PRs
4. Comment on original GitHub issues linking to fixes

