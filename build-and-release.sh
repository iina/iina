#!/bin/bash
# Build and release script for IINA with UPnP/DLNA support
# Usage: ./build-and-release.sh [version] [--skip-build]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get version from argument or use default
VERSION="${1:-1.4.1-upnp}"
SKIP_BUILD=false

if [[ "$*" == *"--skip-build"* ]]; then
  SKIP_BUILD=true
fi

echo -e "${GREEN}🚀 IINA UPnP/DLNA Build and Release Script${NC}"
echo "Version: $VERSION"
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Build configuration
SCHEME="iina"
CONFIGURATION="Release"
PROJECT="iina.xcodeproj"

# DerivedData path
DERIVED_DATA_BASE="$HOME/Library/Developer/Xcode/DerivedData"
APP_NAME="IINA.app"

# Step 1: Build
if [ "$SKIP_BUILD" = false ]; then
  echo -e "${YELLOW}📦 Building IINA (this may take 5-10 minutes)...${NC}"
  
  # Clean previous build
  echo "Cleaning previous builds..."
  xcodebuild clean -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" > /dev/null 2>&1 || true
  
  # Build
  echo "Building Release configuration..."
  xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_BASE" \
    build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" || true
  
  # Check if build succeeded
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}✅ Build completed${NC}"
else
  echo -e "${YELLOW}⏭️  Skipping build (--skip-build flag)${NC}"
fi

# Step 2: Find the built app
echo ""
echo -e "${YELLOW}🔍 Locating built app...${NC}"
APP_PATH=$(find "$DERIVED_DATA_BASE" -name "$APP_NAME" -path "*/$CONFIGURATION/*" -type d | head -1)

if [ -z "$APP_PATH" ]; then
  echo -e "${RED}❌ Could not find built app in $DERIVED_DATA_BASE${NC}"
  echo "Please build the project first or check the DerivedData path"
  exit 1
fi

echo -e "${GREEN}✅ Found app: $APP_PATH${NC}"

# Step 3: Create release directory
RELEASE_DIR="$SCRIPT_DIR/releases"
mkdir -p "$RELEASE_DIR"

# Step 4: Create zip file
ZIP_NAME="IINA-UPnP-${VERSION}.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

echo ""
echo -e "${YELLOW}📦 Creating zip archive...${NC}"
cd "$(dirname "$APP_PATH")"
zip -r -q "$ZIP_PATH" "$APP_NAME"
cd "$SCRIPT_DIR"

ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo -e "${GREEN}✅ Created: $ZIP_NAME ($ZIP_SIZE)${NC}"

# Step 5: Create git tag
echo ""
echo -e "${YELLOW}🏷️  Creating git tag...${NC}"
git fetch origin develop 2>/dev/null || true

# Check if tag already exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  Tag $VERSION already exists. Deleting and recreating...${NC}"
  git tag -d "$VERSION" 2>/dev/null || true
  git push jay ":refs/tags/$VERSION" 2>/dev/null || true
fi

git tag -a "$VERSION" -m "Release $VERSION - IINA with UPnP/DLNA support"
echo -e "${GREEN}✅ Tag created: $VERSION${NC}"

# Step 6: Push tag
echo ""
echo -e "${YELLOW}📤 Pushing tag to GitHub...${NC}"
git push jay "$VERSION"
echo -e "${GREEN}✅ Tag pushed${NC}"

# Step 7: Create GitHub release
echo ""
echo -e "${YELLOW}🚀 Creating GitHub release...${NC}"

# Release notes
RELEASE_NOTES="## IINA with UPnP/DLNA Support - $VERSION

This release adds experimental UPnP/DLNA media server discovery and browsing capabilities to IINA.

### Features

- **SSDP Discovery**: Automatically discovers UPnP/DLNA media servers on the local network
- **Device Browsing**: Browse media content from discovered servers  
- **Playback Integration**: Play videos directly from UPnP/DLNA servers
- **UI Integration**: 
  - Menu item: \`File\` → \`Open from UPnP/DLNA Server...\`
  - Welcome window button: \"Open from UPnP/DLNA Server...\"

### Installation

1. Download \`$ZIP_NAME\`
2. Extract the \`.app\` file
3. Move it to your \`/Applications\` folder
4. Grant network permission when prompted (System Settings → Privacy & Security → Local Network)

### Technical Details

- Uses BSD sockets for SSDP discovery (similar to VLC/libupnp approach)
- Parses UPnP device descriptions and ContentDirectory service
- Supports DIDL-Lite XML parsing for media items
- Network permission (\`NSLocalNetworkUsageDescription\`) added to Info.plist

### Testing

Tested with:
- MiniDLNA on DietPi
- Various UPnP/DLNA servers on local network

### Known Limitations

- No authentication support (basic servers only)
- No transcoding support (plays direct URLs)
- Some servers may not be fully compatible

### Source

Built from: [jgkme/iina-dlna](https://github.com/jgkme/iina-dlna) branch \`feature/upnp-dlna\`

### PR Status

Upstream PR: [#5852](https://github.com/iina/iina/pull/5852)
"

# Create release using gh CLI
gh release create "$VERSION" \
  "$ZIP_PATH" \
  --title "IINA with UPnP/DLNA Support - $VERSION" \
  --notes "$RELEASE_NOTES" \
  --repo jgkme/iina-dlna

echo ""
echo -e "${GREEN}✅ Release created successfully!${NC}"
echo ""
echo -e "${GREEN}📋 Summary:${NC}"
echo "  Version: $VERSION"
echo "  Zip file: $ZIP_PATH ($ZIP_SIZE)"
echo "  Release URL: https://github.com/jgkme/iina-dlna/releases/tag/$VERSION"
echo ""
echo -e "${GREEN}🎉 Done!${NC}"

