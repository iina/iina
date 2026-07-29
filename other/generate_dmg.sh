#!/bin/bash

#
#  generate_dmg.sh
#  iina
#
#  Created by low-batt on 4/20/26.
#  Copyright © 2026 lhc. All rights reserved.
#

# Running this script generates an IINA DMG file in Xcode's build directory.
# Before running this script you must in Xcode edit the iina scheme and set the
# build configuration to the desired type of IINA release (Beta, Debug, Nightly or
# Release) and then build an IINA.app that can be run on any Mac. This script will
# refuse to generate a DMG if the app is not universal. This script also tests
# that the Safari extension can be installed and uninstalled.

# IMPORTANT! This script requires that create-dmg has been installed.
# See: https://github.com/create-dmg/create-dmg

PROJECT_NAME='iina'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

printUsageHelp() {
  echo
  echo -e "${BLUE}Usage:${NC}"
  echo -e "    ${GREEN}$0 -h:${NC}        Displays this help message"
  echo -e "    ${GREEN}$0 -v:${NC}        Show details during disk image creation"
  echo
}

args=`getopt hv $*`
if [ $? -ne 0 ]; then
  printUsageHelp
  echo -e "${RED}Failed parsing options.${NC}" >&2
  exit 1
fi
set -- $args

VERBOSE=1
while true; do
  case "$1" in
  -h)
    printUsageHelp
    exit 0
    ;;
  -v)
    VERBOSE=0
    shift
    ;;
  --)
    shift
    break
    ;;
  *) break ;;
  esac
done

echo -e "${BLUE}Starting disk image generation…${NC}"

# This script requires that create-dmg has been installed.
# See: https://github.com/create-dmg/create-dmg
if ! [ -x "$(command -v create-dmg)" ]; then
  echo -e "${RED}Error create-dmg is not installed.${NC}" >&2
  exit 1
fi

# Find the root directory of this repository clone.
SCRIPT_PATH=$(realpath "$0")
ROOT_PATH=$(dirname "$SCRIPT_PATH")

if [[ $(basename "$ROOT_PATH") != "$PROJECT_NAME" ]]; then
  while [[ "$ROOT_PATH" != "/" && $(basename "$ROOT_PATH") != "$PROJECT_NAME" ]]; do
    ROOT_PATH=$(dirname "$ROOT_PATH")
  done
  if [[ "$ROOT_PATH" == "/" ]]; then
    echo -e "${RED}Unable to find the root directory '$PROJECT_NAME' containing the script file.${NC}" >&2
    exit 1
  fi
fi

# Confirm the background image for the DMG exists.
DMG_BACKGROUND_PATH="$ROOT_PATH/other/dmg_background.png"
if [ ! -e "$DMG_BACKGROUND_PATH" ]; then
  echo -e "${RED}Background image for DMG is missing: ${DMG_BACKGROUND_PATH}${NC}" >&2
  exit 1
fi

# Base the size of the Finder window shown when the DMG is opened on the size of
# the background image.
WIDTH=$(sips -g pixelWidth "$DMG_BACKGROUND_PATH" | tail -n1 | cut -d" " -f4)
if [ -z "$WIDTH" ]; then
  echo -e "${RED}Failed to obtain width of background image.${NC}" >&2
  exit 1
fi
if ! [[ "$WIDTH" =~ ^[0-9]+$ ]] ; then
  echo -e "${RED}Width is not an integer: ${WIDTH}${NC}" >&2
  exit 1
fi
HEIGHT=$(sips -g pixelHeight "$DMG_BACKGROUND_PATH" | tail -n1 | cut -d" " -f4)
if [ -z "$HEIGHT" ]; then
  echo -e "${RED}Failed to obtain height of background image.${NC}" >&2
  exit 1  
fi
if ! [[ "$HEIGHT" =~ ^[0-9]+$ ]] ; then
  echo -e "${RED}Height is not an integer: ${HEIGHT}${NC}" >&2
  exit 1
fi
# Increase the window height to account for the title bar (32 px in macOS Tahoe).
HEIGHT=$(($HEIGHT + 32))

# Obtain a copy of the Xcode build settings.
echo -e "${YELLOW}Obtaining Xcode build settings…${NC}"

SETTINGS=$(xcodebuild \
  -workspace ${ROOT_PATH}/iina.xcodeproj/project.xcworkspace \
  -scheme iina -destination 'generic/platform=macOS,name=Any Mac' \
  -showBuildSettings)

echo -e "${GREEN}Obtained Xcode build settings${NC}"

# Find the Xcode build directory.
TARGET_BUILD_DIR=$(echo "$SETTINGS" | sed -rn 's/.*TARGET_BUILD_DIR = (.*)/\1/p')
if [ -z "$TARGET_BUILD_DIR" ]; then
  echo -e "${RED}Unable to find the target build directory in Xcode build settings.${NC}" >&2
  exit 1
fi

# Confirm IINA.app has been built.
APP_PATH="$TARGET_BUILD_DIR/IINA.app"
if [ ! -e "$APP_PATH" ]; then
  echo -e "${RED}An IINA.app file was not found in ${TARGET_BUILD_DIR}.${NC}" >&2
  exit 1
fi
echo -e "${GREEN}Found IINA.app: ${APP_PATH}${NC}"

# Confirm app was built for all Macs.
IINA_BINARY_PATH="${APP_PATH}/Contents/MacOS/iina"
if ! lipo "$IINA_BINARY_PATH" -verify_arch arm64; then
  echo -e "${RED}IINA.app is missing support for arm64.${NC}" >&2
  exit 1
fi
if ! lipo "$IINA_BINARY_PATH" -verify_arch x86_64; then
  echo -e "${RED}IINA.app is missing support for x86_64.${NC}" >&2
  exit 1
fi

# As testing the Safari extension alters the user's environment make it clear
# to the user the extension is being installed and uninstalled.
echo -e "${YELLOW}Confirming Safari extension exists and can be installed…${NC}"
EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/OpenInIINA.appex"
if [ ! -e "$EXTENSION_PATH" ]; then
  echo -e "${RED}IINA.app is missing the Safari extension.${NC}" >&2
  exit 1
fi
echo -e "${YELLOW}Installing Safari extension…${NC}"
if ! pluginkit -a "$EXTENSION_PATH"; then
  echo -e "${RED}Unable to install Safari extension.${NC}" >&2
  exit 1
fi
if ! pluginkit -mAvvv -p com.apple.Safari.extension | grep -q "$EXTENSION_PATH"; then
  echo -e "${RED}Plugin not found in Safari extension list.${NC}" >&2
  exit 1
fi
echo -e "${YELLOW}Uninstalling Safari extension…${NC}"
if ! pluginkit -r "$EXTENSION_PATH"; then
  echo -e "${RED}Unable to uninstall Safari extension.${NC}" >&2
  exit 1
fi
echo -e "${GREEN}Confirmed Safari extension is installable.${NC}"

# Find the Xcode build configuration. The app icon differs based on the configuration.
CONFIGURATION=$(echo "$SETTINGS" | sed -rn 's/.*CONFIGURATION = (.*)/\1/p')
if [ -z  "$CONFIGURATION" ]; then
  echo -e "${RED}Unable to find build configuration in Xcode build settings.${NC}" >&2
  exit 1
fi
validConfiguration() {
  CONFIG=$1
  for valid in Beta Debug Nightly Release; do
    if [ "$CONFIG" = "$valid" ]; then
      return 0
    fi
  done
  return 1
}
if ! validConfiguration "$CONFIGURATION"; then
  echo -e "${RED}Build configuration '$CONFIGURATION' not recognized.${NC}" >&2
  exit 1
fi

# Form a path to the correct app icon for use as the volume's icon.
if [ "${CONFIGURATION}" = "Release" ]; then
  VOL_ICON_PATH="$TARGET_BUILD_DIR/IINA.app/Contents/Resources/AppIcon.icns"
else
  VOL_ICON_PATH="$TARGET_BUILD_DIR/IINA.app/Contents/Resources/AppIcon${CONFIGURATION}.icns"
fi
if [ ! -e "$VOL_ICON_PATH" ]; then
  echo -e "${RED}Icon for volume does not exist: ${VOL_ICON_PATH}${NC}" >&2
  exit 1
fi
echo -e "${GREEN}Found icon file to use for volume: ${VOL_ICON_PATH}${NC}"

# Find the IINA version so it can be used in the DMG filename.
MARKETING_VERSION=$(echo "$SETTINGS" | sed -rn 's/.*MARKETING_VERSION = (.*)/\1/p')
if [ -z  "$MARKETING_VERSION" ]; then
  echo -e "${RED}Unable to find IINA version in Xcode build settings.${NC}" >&2
  exit 1
fi
DISK_IMAGE_PATH="$TARGET_BUILD_DIR/IINA.v"$MARKETING_VERSION".dmg"

# If the disk image file already exists it must be removed or create-dmg will fail.
if [ -e "$DISK_IMAGE_PATH" ]; then
  if rm "$DISK_IMAGE_PATH"; then
    echo -e "${YELLOW}Removed existing disk image: ${DISK_IMAGE_PATH}${NC}"
  else
    echo -e "${RED}Unable to remove existing disk image: ${DISK_IMAGE_PATH}${NC}" >&2
    exit 1
  fi
fi

echo -e "${YELLOW}Generating disk image…${NC}"

if [ $VERBOSE -eq 0 ]; then
  QUITE='--hdiutil-verbose'
else
  QUITE='--hdiutil-quiet'
fi

if ! create-dmg $QUITE --volname IINA --volicon "$VOL_ICON_PATH" --background "$DMG_BACKGROUND_PATH" \
    --window-pos 200 120 --window-size $WIDTH $HEIGHT --icon-size 128 \
    --icon "IINA.app" 140 230 --app-drop-link 400 230 \
    "$DISK_IMAGE_PATH" "$APP_PATH"; then
  echo -e "${RED}Failed to create disk image.${NC}" >&2
  exit 1
fi

echo -e "${GREEN}Generated disk image: ${DISK_IMAGE_PATH}${NC}"
echo -e "${GREEN}Successfully generated DMG file.${NC}"
