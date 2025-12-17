# Quick Start Guide - UPnP/DLNA Implementation

## What Has Been Implemented

✅ **Core UPnP/DLNA Functionality**
- SSDP device discovery
- Device description parsing
- ContentDirectory service client
- DIDL-Lite XML parsing
- Media item browsing

✅ **User Interface**
- Browser window controller (code complete, needs XIB)
- Device list view
- Content outline view
- Playback integration

✅ **Security Fixes**
- WebSocket TLS support added
- Security audit completed

✅ **Integration**
- Menu action added to AppDelegate
- PlayerCore integration ready

---

## What You Need to Do Next

### Step 1: Create the XIB File (5-10 minutes)

1. Open `iina.xcodeproj` in Xcode
2. Right-click on `iina/Base.lproj/` folder
3. Select "New File..." → "User Interface" → "Window"
4. Name it `UPnPBrowserWindowController.xib`
5. Design the window with:
   - Split view (horizontal)
   - Left: Table View (device list)
   - Right: Outline View (content browser)
   - Bottom: Status label, Refresh button, Play button
6. Connect outlets:
   - `deviceTableView` → Table View
   - `contentOutlineView` → Outline View
   - `refreshButton` → Refresh button
   - `playButton` → Play button
   - `statusLabel` → Status text field
7. Set file owner to `UPnPBrowserWindowController`

### Step 2: Add Menu Item (2 minutes)

1. Open `iina/Base.lproj/MainMenu.xib`
2. Find "File" menu
3. Add new menu item after "Open URL..."
4. Set title: "Open from UPnP/DLNA Server..."
5. Connect action to `AppDelegate.openUPnP:`

### Step 3: Add Localization (Optional, 5 minutes)

Add to `iina/en.lproj/Localizable.strings`:
```
"upnp.browser.title" = "UPnP/DLNA Browser";
"upnp.browser.status.discovering" = "Discovering devices...";
"upnp.browser.status.found" = "Found %d devices";
"upnp.browser.status.browsing" = "Browsing content...";
"upnp.browser.status.items" = "Found %d items";
"upnp.browser.status.error" = "Error: ";
"upnp.browser.status.no_content" = "Device does not support content browsing";
```

### Step 4: Build and Test

```bash
# Download dependencies
./other/download_libs.sh

# Open in Xcode
open iina.xcodeproj

# Build (⌘B)
# Run (⌘R)
```

### Step 5: Test with DLNA Server

1. **Enable DLNA on a server**:
   - Plex: Settings → Network → Enable DLNA
   - Kodi: Settings → Services → UPnP/DLNA → Enable
   - Universal Media Server: Already enabled by default

2. **Test in IINA**:
   - Menu → File → "Open from UPnP/DLNA Server..."
   - Wait for devices to appear (15 seconds)
   - Click on a device
   - Browse content
   - Double-click to play

---

## Files Created

All files are in `iina/` directory:

1. `UPnPDevice.swift` - Device model
2. `UPnPItem.swift` - Media item model  
3. `UPnPManager.swift` - Core UPnP functionality
4. `UPnPBrowserWindowController.swift` - UI controller

## Files Modified

1. `AppDelegate.swift` - Added menu action
2. `WebSocketServer.swift` - Added TLS support

---

## Known Issues to Address

### High Priority
1. **XML Parsing**: Currently uses regex - should use XMLParser
2. **Error Handling**: Needs better user feedback

### Medium Priority
1. **Device Removal**: No detection when device goes offline
2. **Metadata**: Some fields may be missing

### Low Priority
1. **Performance**: Could cache device descriptions
2. **UI Polish**: Loading indicators, better error messages

---

## If You Want to Improve XML Parsing

Replace regex-based parsing in `UPnPManager.swift` with proper XMLParser:

```swift
// Example for device description
class DeviceDescriptionParser: NSObject, XMLParserDelegate {
  var device: UPnPDevice?
  var currentElement = ""
  var currentText = ""
  
  func parse(data: Data, baseDevice: UPnPDevice) -> UPnPDevice? {
    let parser = XMLParser(data: data)
    parser.delegate = self
    // ... implement delegate methods
  }
}
```

---

## Troubleshooting

### Devices Not Appearing
- Check firewall settings
- Ensure DLNA server is running
- Check network connectivity
- Look at Console.app for IINA logs

### Playback Fails
- Check if URL is accessible
- Verify mpv can handle the format
- Check network permissions

### Build Errors
- Ensure all files are added to Xcode project
- Check that outlets are connected in XIB
- Verify Swift version compatibility

---

## Next Steps After Basic Implementation

1. **Improve XML Parsing** (use XMLParser)
2. **Add Error Dialogs** (user-friendly messages)
3. **Add Loading Indicators** (better UX)
4. **Test with Multiple Servers** (compatibility)
5. **Add Search** (find media across devices)
6. **Add Favorites** (save devices)

---

## Contributing Back

If you want to submit this as a PR:

1. **Fork the repository**
2. **Create feature branch**: `git checkout -b feature/upnp-dlna-support`
3. **Commit changes**: `git commit -m "Add UPnP/DLNA support"`
4. **Push**: `git push origin feature/upnp-dlna-support`
5. **Create PR** on GitHub

See `IMPLEMENTATION_SUMMARY.md` for PR description template.

---

## Need Help?

- Check `IMPLEMENTATION_SUMMARY.md` for detailed info
- Check `UPNP_IMPLEMENTATION_GUIDE.md` for code examples
- Check `SECURITY_AUDIT.md` for security considerations
- Check `CODEBASE_ANALYSIS.md` for architecture overview

---

**Status**: ✅ Ready for XIB creation and testing!

**Estimated Time to Complete**: 15-30 minutes for XIB + menu item

