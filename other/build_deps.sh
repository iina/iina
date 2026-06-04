#!/bin/bash

NIX_BUILD=true
REPLACE_LIBS=true
REPLACE_EXECUTABLES=true
REPLACE_INCLUDES=false

MIN_NIX_VERSION="2.34.6"
DEBUG_NIX=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_script_dir() {
  local SOURCE_PATH="${BASH_SOURCE[0]}"
  local SYMLINK_DIR
  local SCRIPT_DIR
  # Resolve symlinks recursively
  while [ -L "$SOURCE_PATH" ]; do
    # Get symlink directory
    SYMLINK_DIR="$( cd -P "$( dirname "$SOURCE_PATH" )" >/dev/null 2>&1 && pwd )"
    # Resolve symlink target (relative or absolute)
    SOURCE_PATH="$(readlink "$SOURCE_PATH")"
    # Check if candidate path is relative or absolute
    if [[ $SOURCE_PATH != /* ]]; then
      # Candidate path is relative, resolve to full path
      SOURCE_PATH=$SYMLINK_DIR/$SOURCE_PATH
    fi
  done
  # Get final script directory path from fully resolved source path
  SCRIPT_DIR="$(cd -P "$( dirname "$SOURCE_PATH" )" >/dev/null 2>&1 && pwd)"
  echo "$SCRIPT_DIR"
}

NIX_EXE="$(which nix)"
set -euo pipefail
SCRIPT_DIR="$(print_script_dir)"
PROJ_DIR="$(realpath ${SCRIPT_DIR}/..)"
echo "Project root directory seems to be: $PROJ_DIR"

if [[ "$NIX_BUILD" = true ]]; then

  if [[ -z "$NIX_EXE" ]]; then
    echo -e "${RED}ERROR: Could not find 'nix' command. Please ensure Nix $MIN_NIX_VERSION or higher is installed.${NC}" >&2
    echo -e "Recommended: install Determinate Nix for MacOS: https://docs.determinate.systems/" >&2
    echo -e "Aborting build." >&2
    exit 1
  fi

  if [[ ! -f $PROJ_DIR/flake.nix ]]; then
    echo -e "${RED}ERROR: Could not find 'flake.nix' (expected location: $PROJ_DIR/flake.nix).${NC}" >&2
    echo -e "${RED}Please ensure it is present and this script is located in $PROJ_DIR/other/${NC}" >&2
    echo -e "Aborting build." >&2
    exit 1
  fi

  cd "$PROJ_DIR"

  NIX_ARGS="build --print-build-logs --verbose"

  if [[ "$DEBUG_NIX" = true ]]; then
    nixStoreRefs=$(grep '/nix/store/' "$PROJ_DIR/iina.xcodeproj/project.pbxproj" || true)
    if [ -n "$nixStoreRefs" ]; then
      echo -e "${RED}ERROR: Found reference(s) to '/nix/store/' in project.pbxproj!${NC}" >&2
      echo -e "${RED}Ensure all framework references in the project files use relative paths which begin with 'deps/lib/'${NC}" >&2
      echo -e "Aborting build." >&2
      exit 1
    fi
    "$NIX_EXE" $NIX_ARGS --keep-failed
  else
    "$NIX_EXE" $NIX_ARGS
  fi
else
  echo -e "${YELLOW}Skipping Nix build.${NC}"
fi

APP_CONTENTS_DIR="$PROJ_DIR/result/Applications/IINA.app/Contents"

if [[ "$REPLACE_LIBS" = true ]]; then
  SRC_DIR="$APP_CONTENTS_DIR/Frameworks"
  DST_DIR="$PROJ_DIR/deps/lib"
  echo -e "${YELLOW}📎 Replacing libs @ $DST_DIR …${NC}"
  rm -rf "$DST_DIR"
  mkdir -p "$DST_DIR"

  for srclib in "$SRC_DIR/"*; do
    if [[ "$srclib" == *".dylib" ]]; then
      cp -v "$srclib" "$DST_DIR/"
    fi
  done
else
  echo -e "${YELLOW}Skipping deps/lib.${NC}"
fi

if [[ "$REPLACE_EXECUTABLES" = true ]]; then
  SRC_DIR="$APP_CONTENTS_DIR/MacOS"
  DST_DIR="$PROJ_DIR/deps/executable"
  echo -e "${YELLOW}📎 Replacing executables @ $DST_DIR …${NC}"
  rm -rf "$DST_DIR"
  mkdir -p "$DST_DIR"
  for executable in "$SRC_DIR/"*; do
    filename="${executable##*/}"
    if [[ "$filename" != *"iina"* ]] && [[ "$filename" != 'IINA' ]]; then
      cp -v "$executable" "$DST_DIR/"
    fi
  done
else
  echo -e "${YELLOW}Skipping deps/executable.${NC}"
fi

if [[ "$REPLACE_INCLUDES" = true ]]; then
  SRC_DIR="$PROJ_DIR/result/include"
  DST_DIR="$PROJ_DIR/deps/include"
  echo -e "${YELLOW}📎 Replacing include files @ $DST_DIR …${NC}"
  mkdir -p "$DST_DIR"
  find "$DST_DIR" -name "*.h" -print0 | xargs -0 rm
  rsync -rv "$SRC_DIR/" "$DST_DIR/"
  chmod -R u+rw "$DST_DIR"
else
  echo -e "${YELLOW}Skipping deps/include.${NC}"
fi

echo ""
echo -e "${GREEN}✅ Done${NC}"

