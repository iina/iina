#!/bin/bash

NIX_BUILD=true
REPLACE_LIBS=true
REPLACE_EXECUTABLES=true
REPLACE_INCLUDES=false
DEBUG_NIX=false

MIN_NIX_VERSION="2.34.6"

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

printUsageHelp() {
  echo
  echo -e "Usage:"
  echo -e "${GREEN}$0 [-h|--help] [--nix-build[=yes|=no] [--debug[=yes|=no] [--replace-libs[=yes|=no] [--replace-executables[=yes|=no] [--replace-includes[=yes|=no]${NC}"
  echo -e ""
  echo -e "Arguments:"
  echo -e "    ${GREEN}-h, --help${NC}             Displays this help message"
  echo -e "    ${GREEN}--nix-build${NC}            Whether to do a new Nix build: yes | no (default: yes)"
  echo -e "    ${GREEN}--debug${NC}                Enable debugging (Nix build only): yes | no (default: no)"
  echo -e "    ${GREEN}--replace-libs${NC}         Whether to replace deps/lib: yes | no (default: yes)"
  echo -e "    ${GREEN}--replace-executables${NC}  Whether to replace deps/executable: yes | no (default: yes)"
  echo -e "    ${GREEN}--replace-includes${NC}     Whether to replace deps/include: yes | no (default: no)"
  echo
}

NIX_EXE="$(which nix)"
set -euo pipefail
SCRIPT_DIR="$(print_script_dir)"
PROJ_DIR="$(realpath ${SCRIPT_DIR}/..)"
APP_CONTENTS_DIR="$PROJ_DIR/result/Applications/IINA.app/Contents"
echo "Project root directory seems to be: $PROJ_DIR"

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    printUsageHelp
    exit 0
    ;;
  --nix-build)
    NIX_BUILD=true
    shift
    ;;
  --nix-build=*)
    YESNO=${1#*=}
    if [[ -z "$YESNO" ]] || [[ "$YESNO" = "yes" ]]; then
      NIX_BUILD=true
    elif [[ "$YESNO" = "no" ]]; then
      NIX_BUILD=false
    else
      printUsageHelp
      exit 1
    fi
    shift
    ;;
  --debug)
    DEBUG_NIX=true
    shift
    ;;
  --debug=*)
    YESNO=${1#*=}
    if [[ -z "$YESNO" ]] || [[ "$YESNO" = "yes" ]]; then
      DEBUG_NIX=true
    elif [[ "$YESNO" = "no" ]]; then
      DEBUG_NIX=false
    else
      printUsageHelp
      exit 1
    fi
    shift
    ;;
  --replace-libs)
    REPLACE_LIBS=true
    shift
    ;;
  --replace-libs=*)
    YESNO=${1#*=}
    if [[ -z "$YESNO" ]] || [[ "$YESNO" = "yes" ]]; then
      REPLACE_LIBS=true
    elif [[ "$YESNO" = "no" ]]; then
      REPLACE_LIBS=false
    else
      printUsageHelp
      exit 1
    fi
    shift
    ;;
  --replace-executables)
    REPLACE_EXECUTABLES=true
    shift
    ;;
  --replace-executables=*)
    YESNO=${1#*=}
    if [[ -z "$YESNO" ]] || [[ "$YESNO" = "yes" ]]; then
      REPLACE_EXECUTABLES=true
    elif [[ "$YESNO" = "no" ]]; then
      REPLACE_EXECUTABLES=false
    else
      printUsageHelp
      exit 1
    fi
    shift
    ;;
  --replace-includes)
    REPLACE_INCLUDES=true
    shift
    ;;
  --replace-includes=*)
    YESNO=${1#*=}
    if [[ -z "$YESNO" ]] || [[ "$YESNO" = "yes" ]]; then
      REPLACE_INCLUDES=true
    elif [[ "$YESNO" = "no" ]]; then
      REPLACE_INCLUDES=false
    else
      printUsageHelp
      exit 1
    fi
    shift
    ;;
  -*)
    echo -e "${RED}Unknown option: $1${NC}" >&2
    printUsageHelp
    exit 1
    ;;
  *)
    echo -e "${RED}Unexpected argument: $1${NC}" >&2
    printUsageHelp
    exit 1
    ;;
  esac
done
if [[ $# -gt 0 ]]; then
  echo -e "${RED}Unexpected argument: $1${NC}" >&2
  printUsageHelp
  exit 1
fi


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
afplay /System/Library/Sounds/Glass.aiff

