# IINA Codebase Analysis & Contribution Guide

## Executive Summary

IINA is a modern macOS video player built with Swift, based on the mpv media player. This document provides an analysis of the codebase, answers to your specific questions, and guidance on contributing UPnP/DLNA support.

---

## 1. Codebase Architecture

### Core Components

- **Language**: Swift (with some Objective-C bridging)
- **Media Engine**: mpv (via libmpv)
- **UI Framework**: AppKit (Cocoa)
- **Architecture**: MVC pattern with clear separation of concerns

### Key Files & Structure

```
iina/
├── AppDelegate.swift          # Application lifecycle, menu actions, URL handling
├── PlayerCore.swift           # Main playback controller (encapsulates mpv)
├── MPVController.swift         # Direct mpv API wrapper (only VideoView & MPVController call mpv)
├── MainWindowController.swift  # Window management and UI
├── VideoView.swift             # Video rendering view
├── ControlBarView.swift        # On-screen controls (uses NSVisualEffectView)
└── [Many other UI/utility files]
```

### Architecture Principles (from CONTRIBUTING.md)

- **Only `VideoView` and `MPVController` may call mpv APIs directly**
- **`PlayerCore`** encapsulates general playback functions
- **Window-related logic** should be in `MainWindowController`
- **Generated files** (MPVCommand, MPVOption, MPVProperty) must not be modified directly

---

## 2. Apple Silicon (ARM64) Optimization ✅

### Status: **FULLY OPTIMIZED**

IINA has **native Apple Silicon support**:

1. **Architecture Detection**:
   - `MPVController.swift` includes `runningOnAppleSilicon()` method (lines 253-272)
   - Detects ARM64 architecture via `uname()` system call
   - Uses this to apply architecture-specific optimizations/workarounds

2. **Build Configuration**:
   - Supports `universal`, `arm64`, and `x86_64` architectures
   - Pre-compiled libraries available for all architectures
   - `Configs/iina.xcconfig` includes architecture-specific linker flags

3. **Hardware Acceleration**:
   - `HardwareDecodeCapabilities.swift` checks hardware decoding support
   - Apple Silicon-specific codec optimizations (e.g., AV1 handling)
   - Different workarounds for Intel vs Apple Silicon (see VP9 workaround in MPVController.swift:274-315)

4. **Deployment Target**:
   - `Configs/Deployment.xcconfig` shows `MACOSX_DEPLOYMENT_TARGET[arch=arm64] = 12`
   - Requires macOS 12+ for ARM64 builds

**Conclusion**: IINA is fully optimized for Apple Silicon and takes advantage of ARM64-specific features.

---

## 3. Glass UI Integration ✅

### Status: **PARTIALLY IMPLEMENTED** (Modern macOS Visual Effects)

IINA uses **NSVisualEffectView** extensively for modern macOS aesthetics:

1. **Visual Effect Views Found**:
   - `ControlBarView` extends `NSVisualEffectView` (glass effect for controls)
   - `MainWindowController` uses multiple `NSVisualEffectView` instances:
     - Title bar (`titleBarView`)
     - Control bar (`controlBarBottom`)
     - Sidebar (`sideBarView`)
     - OSD overlay (`osdVisualEffectView`)
   - `MiniPlayerWindowController` uses visual effects
   - `InitialWindowController` uses visual effects

2. **Materials Used**:
   - `material="popover"` - For overlays and popups
   - `material="sidebar"` - For side panels
   - `material="titlebar"` - For title bar areas
   - `material="underWindowBackground"` - For window backgrounds
   - `material="headerView"` - For header sections

3. **Modern Features**:
   - Dark mode support (`NSAppearance` extensions)
   - Rounded corners with `roundCorners()` extension
   - Vibrancy effects (`blendingMode="behindWindow"` and `"withinWindow"`)
   - Theme material preferences (`Preference.themeMaterial`)

4. **What's Missing**:
   - **No explicit "glass" material** (macOS 11+ `.hudWindow`, `.popover`, `.sheet` materials)
   - Could potentially use newer materials like `.hudWindow` or `.sheet` for more modern glass effects
   - The current implementation uses standard materials, not the newest macOS Sequoia/Sonoma glass effects

**Conclusion**: IINA has good visual effects integration, but could be enhanced with newer macOS glass materials for a more modern look.

---

## 4. UPnP/DLNA Support ❌

### Status: **NOT IMPLEMENTED**

**Current State**:
- No UPnP/DLNA discovery code found
- No DLNA media server client implementation
- Network support is limited to HTTP/HTTPS URLs and RTSP streams
- File opening supports local files and network URLs, but no UPnP protocol

**What Exists**:
- `PlayerCore.openURL()` - Can open HTTP/HTTPS URLs
- `MPVOption.Network` - Network-related mpv options (user-agent, proxy, etc.)
- `WebSocketServer.swift` - WebSocket server implementation (for remote control)
- Network file access via standard URL schemes

**What's Needed for UPnP/DLNA**:

1. **UPnP Discovery**:
   - SSDP (Simple Service Discovery Protocol) client
   - Device discovery on local network
   - Service description parsing (XML)

2. **DLNA Media Server Client**:
   - Browse content directory
   - List available media files
   - Get media metadata
   - Generate playable URLs

3. **UI Components**:
   - Network browser window/panel
   - Device list view
   - Content directory browser
   - Integration with existing file open dialog

4. **Integration Points**:
   - Add to `AppDelegate` menu actions
   - Integrate with `PlayerCore.openURL()`
   - Add to playlist system
   - Network preferences panel

---

## 5. Most Requested Features (Based on Web Research)

Based on GitHub and community discussions, common feature requests include:

1. **UPnP/DLNA Support** ⭐ (Your focus!)
2. **Better subtitle management**
3. **Playlist improvements**
4. **Plugin system enhancements** (already exists, but could be expanded)
5. **Better network streaming support**
6. **Audio passthrough improvements**

---

## 6. How to Contribute UPnP/DLNA Support

### Option A: Contribute to Main Repository

1. **Check Existing Issues**:
   - Search GitHub issues for "UPnP" or "DLNA"
   - If no issue exists, create one to discuss the feature

2. **Implementation Approach**:

   **Step 1: Choose a UPnP Library**
   - **Option 1**: Use a Swift UPnP library
     - `CocoaUPnP` (if available/updated)
     - `UPnP-Swift` (check GitHub)
     - Or build a minimal SSDP client
   
   - **Option 2**: Use a C/C++ library via bridging
     - `libupnp` (GPL, may have licensing issues)
     - `gupnp` (LGPL, more permissive)
     - Bridge via Objective-C

   **Step 2: Create UPnP Manager**
   ```swift
   // New file: iina/UPnPManager.swift
   class UPnPManager {
     func discoverDevices() -> [UPnPDevice]
     func browseContent(device: UPnPDevice, path: String) -> [UPnPItem]
     func getPlaybackURL(item: UPnPItem) -> URL?
   }
   ```

   **Step 3: Create UI Components**
   - `UPnPBrowserWindowController.swift` - Main browser window
   - `UPnPDeviceListViewController.swift` - Device list
   - `UPnPContentViewController.swift` - Content browser
   - Add menu item: "Open from UPnP/DLNA Server..."

   **Step 4: Integration**
   - Add to `AppDelegate` menu actions
   - Integrate with `PlayerCore.openURL()`
   - Add network preferences

3. **Testing**:
   - Test with various DLNA servers (Plex, Kodi, etc.)
   - Test on both Intel and Apple Silicon
   - Test with different media types

4. **Submit PR**:
   - Follow CONTRIBUTING.md guidelines
   - Submit to `develop` branch
   - Include documentation

### Option B: Fork and Create Custom Build

1. **Fork the Repository**:
   ```bash
   git clone https://github.com/iina/iina.git
   cd iina
   git remote add upstream https://github.com/iina/iina.git
   ```

2. **Create Feature Branch**:
   ```bash
   git checkout -b feature/upnp-dlna-support
   ```

3. **Implement UPnP/DLNA** (same as Option A, Step 2-4)

4. **Build and Test**:
   ```bash
   ./other/download_libs.sh  # Download pre-compiled libraries
   # Open in Xcode and build
   ```

5. **Maintain Your Fork**:
   - Keep in sync with upstream
   - Release your own builds if desired

---

## 7. Implementation Roadmap for UPnP/DLNA

### Phase 1: Core UPnP Discovery (2-3 weeks)
- [ ] Implement SSDP client for device discovery
- [ ] Parse device descriptions (XML)
- [ ] Create `UPnPDevice` model
- [ ] Basic device listing

### Phase 2: Content Browsing (2-3 weeks)
- [ ] Implement ContentDirectory service client
- [ ] Browse and list media items
- [ ] Parse media metadata
- [ ] Create `UPnPItem` model

### Phase 3: Playback Integration (1-2 weeks)
- [ ] Generate playable URLs from UPnP items
- [ ] Integrate with `PlayerCore.openURL()`
- [ ] Handle different media types
- [ ] Error handling

### Phase 4: UI Implementation (2-3 weeks)
- [ ] Create browser window controller
- [ ] Device list view
- [ ] Content browser view
- [ ] Add to menu system
- [ ] Preferences panel

### Phase 5: Polish & Testing (1-2 weeks)
- [ ] Error handling and user feedback
- [ ] Loading states and progress indicators
- [ ] Documentation
- [ ] Testing with various servers

**Total Estimated Time**: 8-13 weeks for a complete implementation

---

## 8. Recommended Libraries for UPnP/DLNA

### Swift Libraries (Preferred)
1. **Check Swift Package Manager**:
   - Search for "UPnP" or "DLNA" packages
   - Consider creating your own minimal implementation

2. **CocoaUPnP** (if maintained):
   - Objective-C library, can be bridged to Swift
   - Check license compatibility

### C/C++ Libraries (Via Bridging)
1. **gupnp** (LGPL):
   - GObject-based UPnP library
   - More permissive license
   - Would need Objective-C bridging

2. **libupnp** (BSD-style):
   - Older but stable
   - Check license terms

### Minimal Implementation
- Implement SSDP client from scratch (not too complex)
- Use URLSession for HTTP requests
- Parse XML with Foundation's XMLParser
- This gives you full control and no licensing issues

---

## 9. Code Locations for Integration

### Files to Modify/Create:

**New Files**:
- `iina/UPnPManager.swift` - Core UPnP functionality
- `iina/UPnPDevice.swift` - Device model
- `iina/UPnPItem.swift` - Media item model
- `iina/UPnPBrowserWindowController.swift` - Main browser UI
- `iina/UPnPDeviceListViewController.swift` - Device list
- `iina/UPnPContentViewController.swift` - Content browser

**Files to Modify**:
- `iina/AppDelegate.swift` - Add menu action
- `iina/PlayerCore.swift` - Integration point for opening UPnP URLs
- `iina/PreferenceWindowController.swift` - Add UPnP preferences
- `iina/Base.lproj/MainMenu.xib` - Add menu item

---

## 10. Next Steps

1. **Explore the Codebase**:
   - Read `PlayerCore.swift` to understand playback flow
   - Study `MainWindowController.swift` for UI patterns
   - Review `AppDelegate.swift` for menu integration

2. **Research UPnP/DLNA**:
   - Understand SSDP protocol
   - Study DLNA ContentDirectory service
   - Review UPnP device architecture documents

3. **Choose Implementation Approach**:
   - Decide on library vs. custom implementation
   - Consider licensing implications
   - Plan architecture

4. **Start Small**:
   - Begin with device discovery
   - Test with a simple DLNA server
   - Iterate and expand

5. **Engage with Community**:
   - Check IINA's Telegram group
   - Discuss on GitHub issues
   - Get feedback early

---

## 11. Additional Resources

- **IINA GitHub**: https://github.com/iina/iina
- **IINA Website**: https://iina.io/
- **mpv Documentation**: https://mpv.io/manual/master/
- **DLNA Guidelines**: http://www.dlna.org/
- **UPnP Device Architecture**: http://upnp.org/specs/arch/

---

## Summary

✅ **Apple Silicon**: Fully optimized  
✅ **Glass UI**: Good visual effects, could use newer materials  
❌ **UPnP/DLNA**: Not implemented - **Great opportunity for contribution!**

The codebase is well-structured and follows good practices. Adding UPnP/DLNA support would be a valuable contribution that many users would appreciate. The implementation is feasible and would integrate well with the existing architecture.

Good luck with your contribution! 🚀

