# Building IINA with UPnP/DLNA Support

This guide covers how to build and maintain your fork of IINA with UPnP/DLNA support.

## Prerequisites

- **macOS** (tested on macOS 15.6, but should work on macOS 11+)
- **Xcode** (latest version recommended, tested with Xcode 26.2)
- **Git** (for cloning and managing branches)
- **Network permission** (macOS will prompt on first run)

## Building from Xcode (Recommended)

### Initial Setup

1. **Open the project in Xcode:**
   ```bash
   cd /Users/jay/Work/projects/iina/iina
   open iina.xcodeproj
   ```

2. **Select the correct scheme:**
   - In Xcode's toolbar, select **`iina`** from the scheme dropdown
   - Configuration: **`Debug`** (for development) or **`Release`** (for distribution)

3. **Build:**
   - Press **⌘B** (Command+B) or go to `Product` → `Build`
   - Wait for the build to complete (first build may take 5-10 minutes)

4. **Run:**
   - Press **⌘R** (Command+R) or go to `Product` → `Run`
   - The app will launch from `~/Library/Developer/Xcode/DerivedData/iina-*/Build/Products/Debug/IINA.app`

### Building from Terminal

If you prefer command-line builds:

```bash
cd /Users/jay/Work/projects/iina/iina

# Debug build
xcodebuild -project iina.xcodeproj \
  -scheme iina \
  -configuration Debug \
  build

# Release build
xcodebuild -project iina.xcodeproj \
  -scheme iina \
  -configuration Release \
  build
```

The built app will be in:
```
~/Library/Developer/Xcode/DerivedData/iina-*/Build/Products/Debug/IINA.app
```

### Running the Built App

**Option 1: From Xcode**
- Press **⌘R** after building

**Option 2: From Terminal**
```bash
# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "IINA.app" -path "*/Debug/*" | head -1)

# Launch it
open "$APP_PATH"
```

**Option 3: Create an alias**
```bash
# Add to your ~/.zshrc or ~/.bash_profile
alias iina-debug='open $(find ~/Library/Developer/Xcode/DerivedData -name "IINA.app" -path "*/Debug/*" | head -1)'
```

## Testing UPnP/DLNA

1. **Launch the app** (from Xcode or terminal)

2. **Grant network permission** (first time only):
   - macOS will prompt: "IINA would like to access your local network"
   - Click **Allow**
   - You can also check/change this in: `System Settings` → `Privacy & Security` → `Local Network`

3. **Open the UPnP browser:**
   - **From welcome window:** Click "Open from UPnP/DLNA Server..."
   - **From menu:** `File` → `Open from UPnP/DLNA Server...`

4. **Wait for discovery:**
   - The browser will automatically discover UPnP devices on your network
   - Status will show "Found X devices" when complete
   - Click a device in the left panel to browse its content

5. **Play content:**
   - Double-click any video file in the content browser
   - Or select a file and click "Play"

## Creating a Release Build

For distribution or personal use:

```bash
cd /Users/jay/Work/projects/iina/iina

# Build Release configuration
xcodebuild -project iina.xcodeproj \
  -scheme iina \
  -configuration Release \
  build

# Find the Release app
RELEASE_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "IINA.app" -path "*/Release/*" | head -1)

# Copy to Applications (optional)
cp -R "$RELEASE_APP" /Applications/IINA-UPnP.app
```

## Maintaining Your Fork

### Keeping Up with Upstream

When the main IINA repo gets updates:

```bash
cd /Users/jay/Work/projects/iina/iina

# Fetch latest from upstream
git fetch origin

# Merge upstream changes into your feature branch
git checkout feature/upnp-dlna
git merge origin/develop

# Resolve any conflicts if they occur
# Then rebuild in Xcode (⌘B)
```

### If Your PR Gets Accepted

If the IINA maintainers accept your PR:

1. **Your changes will be merged into `origin/develop`**
2. **You can switch back to upstream:**
   ```bash
   git remote set-url origin https://github.com/iina/iina.git
   git checkout develop
   git pull origin develop
   ```

### If Your PR Gets Rejected

If the PR is closed/rejected, maintain your fork:

1. **Keep your fork updated:**
   ```bash
   # Add upstream as a remote (if not already)
   git remote add upstream https://github.com/iina/iina.git
   
   # Fetch upstream changes
   git fetch upstream
   
   # Merge upstream into your fork's main branch
   git checkout develop
   git merge upstream/develop
   
   # Rebase your feature branch on top
   git checkout feature/upnp-dlna
   git rebase develop
   ```

2. **Create releases on your fork:**
   - On GitHub, go to your fork (`jgkme/iina-dlna`)
   - Click **Releases** → **Create a new release**
   - Tag: `v1.4.1-upnp` (or similar)
   - Attach the built `.app` (zip it first)

## Troubleshooting

### Build Errors

**"No such module 'X'"**
- Clean build folder: `Product` → `Clean Build Folder` (⌘⇧K)
- Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/iina-*`
- Rebuild

**"Code signing errors"**
- In Xcode: `Signing & Capabilities` → Select your development team
- Or set to "Sign to Run Locally" for Debug builds

**"Network permission denied"**
- Check: `System Settings` → `Privacy & Security` → `Local Network` → `IINA`
- Make sure it's enabled

### UPnP Discovery Issues

**"Found 0 devices"**
- Check that your UPnP server is running and accessible
- Try VLC to confirm the server works
- Check the Log window (`Window` → `Log`) for SSDP errors
- Make sure your firewall isn't blocking UDP port 1900

**"Found devices but 0 items"**
- The device may not have a ContentDirectory service
- Check the Log window for DIDL-Lite parsing errors
- Some servers require authentication (not yet implemented)

## File Structure

Key files added for UPnP/DLNA:

```
iina/
├── UPnPManager.swift          # Core UPnP discovery and browsing
├── UPnPDevice.swift            # Device model
├── UPnPItem.swift              # Media item model
├── UPnPBrowserWindowController.swift  # UI controller
└── Base.lproj/
    └── UPnPBrowserWindowController.xib  # UI layout

Modified files:
├── AppDelegate.swift           # Added menu action
├── InitialWindowController.swift  # Added welcome button
└── Info.plist                  # Added network permission
```

## Next Steps

- **Test with different UPnP servers** (MiniDLNA, Plex, Kodi, etc.)
- **Add authentication support** if needed
- **Improve error handling** for network failures
- **Add caching** for device descriptions
- **Support for more media types** (audio, images)
