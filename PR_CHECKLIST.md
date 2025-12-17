# PR Submission Checklist

## Pre-Submission Checklist

### ✅ Code Quality
- [x] All UPnP files are properly structured and documented
- [x] No compilation errors or warnings
- [x] Code follows IINA's existing patterns (Logger, subsystem, etc.)
- [x] Network permission added to Info.plist

### ✅ Functionality
- [x] UPnP discovery works (tested with MiniDLNA/DietPi)
- [x] Device browsing works
- [x] Content listing works
- [x] Playback integration works
- [x] UI is accessible from menu and welcome window

### ✅ Files Added
- [x] `iina/UPnPManager.swift` - Core UPnP logic
- [x] `iina/UPnPDevice.swift` - Device model
- [x] `iina/UPnPItem.swift` - Media item model
- [x] `iina/UPnPBrowserWindowController.swift` - UI controller
- [x] `iina/Base.lproj/UPnPBrowserWindowController.xib` - UI layout

### ✅ Files Modified
- [x] `iina/AppDelegate.swift` - Added menu action and lazy var
- [x] `iina/InitialWindowController.swift` - Added welcome button
- [x] `iina/Info.plist` - Added network permission
- [x] `iina.xcodeproj/project.pbxproj` - Added file references

### 📝 Documentation
- [x] `CODEBASE_ANALYSIS.md` - Architecture overview
- [x] `UPNP_IMPLEMENTATION_GUIDE.md` - Technical details
- [x] `BUILD_INSTRUCTIONS.md` - Build and maintenance guide
- [x] `QUICK_START.md` - Quick start guide
- [x] `SECURITY_AUDIT.md` - Security considerations

## PR Description Template

Use this when creating your PR on GitHub:

```markdown
## Add UPnP/DLNA Browser Support

This PR adds experimental UPnP/DLNA media server discovery and browsing capabilities to IINA.

### Features

- **SSDP Discovery**: Automatically discovers UPnP/DLNA media servers on the local network
- **Device Browsing**: Browse media content from discovered servers
- **Playback Integration**: Play videos directly from UPnP/DLNA servers
- **UI Integration**: 
  - Menu item: `File` → `Open from UPnP/DLNA Server...`
  - Welcome window button: "Open from UPnP/DLNA Server..."

### Technical Details

- Uses BSD sockets for SSDP discovery (similar to VLC/libupnp approach)
- Parses UPnP device descriptions and ContentDirectory service
- Supports DIDL-Lite XML parsing for media items
- Network permission (`NSLocalNetworkUsageDescription`) added to Info.plist

### Testing

Tested with:
- MiniDLNA on DietPi (192.168.0.120)
- Various UPnP/DLNA servers on local network

### Known Limitations

- No authentication support (basic servers only)
- No transcoding support (plays direct URLs)
- Some servers may not be fully compatible

### Files Changed

**New Files:**
- `iina/UPnPManager.swift` - Core UPnP discovery and browsing
- `iina/UPnPDevice.swift` - Device model
- `iina/UPnPItem.swift` - Media item model
- `iina/UPnPBrowserWindowController.swift` - UI controller
- `iina/Base.lproj/UPnPBrowserWindowController.xib` - UI layout

**Modified Files:**
- `iina/AppDelegate.swift` - Menu integration
- `iina/InitialWindowController.swift` - Welcome window button
- `iina/Info.plist` - Network permission
- `iina.xcodeproj/project.pbxproj` - Project file updates

### Documentation

See:
- `UPNP_IMPLEMENTATION_GUIDE.md` - Technical implementation details
- `BUILD_INSTRUCTIONS.md` - Build and maintenance guide
- `QUICK_START.md` - Quick start guide

### Related Issues

Addresses feature requests:
- #XXXX (if any relevant GitHub issues exist)

---

**Note**: This is an experimental feature. Feedback and testing with various UPnP/DLNA servers is welcome!
```

## Post-Submission

### If PR is Accepted
1. Celebrate! 🎉
2. Monitor for any issues or feedback
3. Be ready to address review comments
4. Consider adding more server compatibility if requested

### If PR is Rejected/Closed
1. **Don't delete your fork** - it's still valuable!
2. **Maintain your fork:**
   - Keep it updated with upstream changes
   - Create releases for others who want UPnP support
   - Consider creating a separate "IINA-UPnP" project if there's community interest

3. **Share your work:**
   - Post on Reddit (r/macapps, r/apple)
   - Share on IINA's Discord/community channels
   - Create a GitHub release with a pre-built binary

## Maintenance Commands

```bash
# Keep your fork updated
git fetch origin
git checkout feature/upnp-dlna
git merge origin/develop

# Create a release build
xcodebuild -project iina.xcodeproj -scheme iina -configuration Release build

# Tag a release
git tag -a v1.4.1-upnp -m "IINA with UPnP/DLNA support"
git push jay v1.4.1-upnp
```

