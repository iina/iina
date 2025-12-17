# Release Guide - Terminal Only

This guide shows how to build and release IINA with UPnP/DLNA support **entirely from the terminal**, without opening Xcode.

## Prerequisites

1. **GitHub CLI (`gh`)** - Already installed and authenticated ✅
2. **Xcode Command Line Tools** - Should already be installed
3. **Git** - Should already be installed

## Quick Release

To build and create a release in one command:

```bash
cd /Users/jay/Work/projects/iina/iina
./build-and-release.sh [VERSION]
```

**Examples:**
```bash
# Create release with version 1.4.1-upnp
./build-and-release.sh 1.4.1-upnp

# Create release with custom version
./build-and-release.sh 1.4.2-upnp-beta

# Skip build (if you already built manually)
./build-and-release.sh 1.4.1-upnp --skip-build
```

## What the Script Does

1. **Builds** the Release configuration using `xcodebuild`
2. **Locates** the built `.app` file
3. **Creates** a zip archive
4. **Tags** the git repository
5. **Pushes** the tag to GitHub
6. **Creates** a GitHub release with the zip file attached

## Manual Steps (if needed)

### Build Only

```bash
cd /Users/jay/Work/projects/iina/iina

# Clean and build
xcodebuild clean -project iina.xcodeproj -scheme iina -configuration Release
xcodebuild -project iina.xcodeproj -scheme iina -configuration Release build
```

### Find Built App

```bash
find ~/Library/Developer/Xcode/DerivedData -name "IINA.app" -path "*/Release/*"
```

### Create Zip Manually

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "IINA.app" -path "*/Release/*" | head -1)
cd "$(dirname "$APP_PATH")"
zip -r IINA-UPnP-1.4.1-upnp.zip IINA.app
```

### Create Release Manually

```bash
# Tag
git tag -a 1.4.1-upnp -m "Release 1.4.1-upnp"
git push jay 1.4.1-upnp

# Create release with gh CLI
gh release create 1.4.1-upnp \
  IINA-UPnP-1.4.1-upnp.zip \
  --title "IINA with UPnP/DLNA Support - 1.4.1-upnp" \
  --notes "Release notes here" \
  --repo jgkme/iina-dlna
```

## Release Locations

- **Built app**: `~/Library/Developer/Xcode/DerivedData/iina-*/Build/Products/Release/IINA.app`
- **Zip file**: `./releases/IINA-UPnP-[VERSION].zip`
- **GitHub release**: `https://github.com/jgkme/iina-dlna/releases/tag/[VERSION]`

## Troubleshooting

### Build Fails

```bash
# Clean DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/iina-*

# Clean build folder
xcodebuild clean -project iina.xcodeproj -scheme iina -configuration Release

# Try building again
./build-and-release.sh [VERSION]
```

### GitHub CLI Not Authenticated

```bash
# Load token from .envrc
source .envrc

# Authenticate
gh auth login --with-token <<< "$GH_TOKEN"
```

### Tag Already Exists

The script will automatically delete and recreate the tag. If you need to do it manually:

```bash
# Delete local tag
git tag -d [VERSION]

# Delete remote tag
git push jay :refs/tags/[VERSION]

# Recreate
git tag -a [VERSION] -m "Release [VERSION]"
git push jay [VERSION]
```

## Version Naming Convention

Recommended format: `[BASE_VERSION]-upnp[-SUFFIX]`

Examples:
- `1.4.1-upnp` - First UPnP release based on 1.4.1
- `1.4.1-upnp-v2` - Second iteration
- `1.4.2-upnp-beta` - Beta release
- `1.4.2-upnp-rc1` - Release candidate

## Automation

You can add this to your `~/.zshrc` or `~/.bash_profile`:

```bash
alias iina-release='cd /Users/jay/Work/projects/iina/iina && ./build-and-release.sh'
```

Then use:
```bash
iina-release 1.4.1-upnp
```

