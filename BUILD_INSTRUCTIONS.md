# Build Instructions - UPnP/DLNA Feature

## Quick Setup

The UPnP/DLNA files have been created but need to be added to the Xcode project. Follow these steps:

### Step 1: Add Files to Xcode Project

1. **Open the project** (already opened):
   ```bash
   open iina.xcodeproj
   ```

2. **Add Swift files**:
   - In Xcode, right-click on the `iina` folder in the Project Navigator
   - Select "Add Files to 'iina'..."
   - Navigate to `iina/` directory
   - Select these files:
     - `UPnPDevice.swift`
     - `UPnPItem.swift`
     - `UPnPManager.swift`
     - `UPnPBrowserWindowController.swift`
   - Make sure "Copy items if needed" is **UNCHECKED** (files are already in place)
   - Make sure "Add to targets: iina" is **CHECKED**
   - Click "Add"

3. **Add XIB file**:
   - Right-click on `iina/Base.lproj/` folder
   - Select "Add Files to 'iina'..."
   - Select `UPnPBrowserWindowController.xib`
   - Make sure "Copy items if needed" is **UNCHECKED**
   - Make sure "Add to targets: iina" is **CHECKED**
   - Click "Add"

### Step 2: Verify Files Are Added

Check that all files appear in the Project Navigator:
- ✅ `UPnPDevice.swift`
- ✅ `UPnPItem.swift`
- ✅ `UPnPManager.swift`
- ✅ `UPnPBrowserWindowController.swift`
- ✅ `UPnPBrowserWindowController.xib` (in Base.lproj folder)

### Step 3: Build

1. **Clean build folder**: `Product` → `Clean Build Folder` (⇧⌘K)
2. **Build**: `Product` → `Build` (⌘B)

### Step 4: Run

1. **Run**: `Product` → `Run` (⌘R)
2. **Test**: Menu → `File` → `Open from UPnP/DLNA Server...`

---

## Alternative: Command Line Build (After Adding Files)

Once files are added in Xcode, you can build from terminal:

```bash
cd /Users/jay/Work/projects/iina/iina
xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug build
```

---

## Troubleshooting

### "File not found" errors
- Make sure files are added to the Xcode project
- Check that files are in the correct target (iina)

### "Cannot find type" errors
- Clean build folder (⇧⌘K)
- Rebuild (⌘B)

### XIB connection errors
- Open `UPnPBrowserWindowController.xib` in Xcode
- Verify File's Owner is set to `UPnPBrowserWindowController`
- Check that all outlets are connected

---

## What's Been Done

✅ All Swift files created
✅ XIB file created
✅ Menu item added to MainMenu.xib
✅ Localization strings added
✅ AppDelegate integration complete
✅ Security fixes applied

## What You Need to Do

1. Add files to Xcode project (see Step 1 above)
2. Build and test

---

**Status**: Ready to build once files are added to Xcode project!

