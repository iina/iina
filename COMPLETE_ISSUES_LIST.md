# Complete Issues List - All Findings

## ✅ Fixed Issues (3)

1. **#2193**: RTSP Password Security - ✅ Fixed
2. **#5658**: OpenSubtitles Question Mark - ✅ Fixed  
3. **#5829**: History with NAS Launch Failure - ✅ Fixed

---

## 🔧 High Priority Issues to Fix (6)

### Regression Bugs (3)
1. **#5850**: Auto-add files plays odd files only (regression)
2. **#5831**: Double-click playlist not playing (regression)
3. **#5719**: Can't access playlist if first stream fails (regression)

### Other High Priority (3)
4. **#5099**: "Pause when media is opened" not respected for audio
5. **#4862**: Incorrect handling of % in URL under Ventura
6. **#3324**: Open URL with whitespace doesn't work

---

## 🐛 Medium Priority Issues (8)

7. **#5113**: External audio loading with .AC3 directory
8. **#5491**: Timestamp not refreshed on frame-by-frame
9. **#3010**: Window closes on playback error
10. **#3500**: Subtitle language preference ignored
11. **#4217**: Seek twice automatically with custom key bindings
12. **#5662**: Some translated strings still in English
13. **#5177**: UI improvements for network stream playlists
14. **#4691**: Wrong tooltip in playlist panel

---

## 📝 Low Priority Issues (2)

15. **#5438**: VLC shuffle shortcut conflict
16. **#5170**: Automatically open file on launch (feature request)

---

## 🎯 Feature Implemented

**UPnP/DLNA Support** - Addresses issues:
- #2173: UPnP / DLNA support?
- #906: would you please add DLNA support
- #3565: Request to support DLNA protocol
- #3442: Do you have any plan to support DLNA?

---

## Summary Statistics

- **Total Issues Fixed**: 3 ✅
- **Total Issues Identified**: 16
- **High Priority**: 6 issues
- **Medium Priority**: 8 issues
- **Low Priority**: 2 issues
- **Feature Implemented**: UPnP/DLNA (addresses 4 feature requests)

---

## Recommended Fix Order

### Phase 1: Critical Regressions (Do First)
1. #5850 - Auto-add files regression
2. #5831 - Double-click playlist regression
3. #5719 - Playlist access regression

### Phase 2: Security & High Priority
4. #2193 - ✅ Already fixed
5. #5099 - Pause when opened
6. #4862 - URL % encoding
7. #3324 - URL whitespace

### Phase 3: Medium Priority Bugs
8. #5113 - External audio .AC3
9. #5491 - Frame-by-frame timestamp
10. #3010 - Window on error
11. #3500 - Subtitle preference
12. #4217 - Key binding seek
13. #5662 - Localization strings

### Phase 4: Low Priority
14. #4691 - Tooltip bug
15. #5438 - VLC shuffle
16. #5170 - Auto-open file

---

## Documentation Files

- `ISSUES_TO_FIX.md` - Initial analysis
- `MORE_ISSUES_TO_FIX.md` - Round 2 findings
- `ADDITIONAL_ISSUES_FOUND.md` - Round 3 findings
- `EVEN_MORE_ISSUES.md` - Round 4 findings (regressions)
- `ISSUES_FIXED_SUMMARY.md` - Summary of fixes
- `COMPLETE_ISSUES_LIST.md` - This file (complete overview)

