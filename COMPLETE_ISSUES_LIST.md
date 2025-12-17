# Complete Issues List - All Findings

## ✅ Fixed Issues (3)

1. **#2193**: RTSP Password Security - ✅ Fixed
2. **#5658**: OpenSubtitles Question Mark - ✅ Fixed  
3. **#5829**: History with NAS Launch Failure - ✅ Fixed

---

## 🔧 High Priority Issues to Fix (9)

### Regression Bugs (4)
1. **#5850**: Auto-add files plays odd files only (regression)
2. **#5831**: Double-click playlist not playing (regression)
3. **#5719**: Can't access playlist if first stream fails (regression)
4. **#5735**: Audio plays but UI shows up late (regression)

### Window Display Bugs (2)
5. **#5815**: Window not displayed for audio with WebP cover art
6. **#5755**: Right arrow key seeks then restarts video

### Other High Priority (3)
7. **#5099**: "Pause when media is opened" not respected for audio
8. **#4862**: Incorrect handling of % in URL under Ventura
9. **#3324**: Open URL with whitespace doesn't work

---

## 🐛 Medium Priority Issues (10)

10. **#5113**: External audio loading with .AC3 directory
11. **#5491**: Timestamp not refreshed on frame-by-frame
12. **#3010**: Window closes on playback error
13. **#3500**: Subtitle language preference ignored
14. **#4217**: Seek twice automatically with custom key bindings
15. **#5662**: Some translated strings still in English
16. **#5177**: UI improvements for network stream playlists
17. **#5716**: Always On Top doesn't stick
18. **#3322**: Remember video size not working
19. **#4691**: Wrong tooltip in playlist panel

---

## 📝 Low Priority Issues (2)

20. **#5438**: VLC shuffle shortcut conflict
21. **#5170**: Automatically open file on launch (feature request)
22. **#4559**: Thumbnail visible with OSC hidden (rare)

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
- **Total Issues Identified**: 22
- **High Priority**: 9 issues (4 regressions, 2 window bugs, 3 others)
- **Medium Priority**: 10 issues
- **Low Priority**: 3 issues
- **Feature Implemented**: UPnP/DLNA (addresses 4 feature requests)

---

## Recommended Fix Order

### Phase 1: Critical Regressions (Do First)
1. #5850 - Auto-add files regression
2. #5831 - Double-click playlist regression
3. #5719 - Playlist access regression
4. #5735 - UI shows late regression

### Phase 2: Window Display & Playback Bugs
5. #5815 - Window not shown for WebP audio
6. #5755 - Seek then restart bug
7. #2193 - ✅ Already fixed

### Phase 3: Security & High Priority
8. #5099 - Pause when opened
9. #4862 - URL % encoding
10. #3324 - URL whitespace

### Phase 4: Medium Priority Bugs
11. #5113 - External audio .AC3
12. #5491 - Frame-by-frame timestamp
13. #3010 - Window on error
14. #3500 - Subtitle preference
15. #4217 - Key binding seek
16. #5716 - Always on top
17. #3322 - Remember window size
18. #5662 - Localization strings
19. #5177 - Network stream UI
20. #4691 - Tooltip bug

### Phase 5: Low Priority
21. #5438 - VLC shuffle
22. #5170 - Auto-open file
23. #4559 - Thumbnail with OSC hidden

---

## Documentation Files

- `ISSUES_TO_FIX.md` - Initial analysis
- `MORE_ISSUES_TO_FIX.md` - Round 2 findings
- `ADDITIONAL_ISSUES_FOUND.md` - Round 3 findings
- `EVEN_MORE_ISSUES.md` - Round 4 findings (regressions)
- `FINAL_ROUND_ISSUES.md` - Round 5 findings (window/preference bugs)
- `ISSUES_FIXED_SUMMARY.md` - Summary of fixes
- `COMPLETE_ISSUES_LIST.md` - This file (complete overview)

