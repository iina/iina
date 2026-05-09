#!/bin/bash

NIX_BUILD=true
REPLACE_LIBS=true
REPLACE_EXECUTABLES=true
REPLACE_INCLUDES=false

MIN_NIX_VERSION="2.34.6"
DEBUG_NIX=false

get_script_dir()
{
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

set -euo pipefail
scriptDir="$(get_script_dir)"
projDir=`realpath ${scriptDir}/..`
echo "Project root directory seems to be: $projDir"

if [[ "$NIX_BUILD" = true ]]; then
  nixExec=$(which nix)

  if [[ -z "$nixExec" ]]; then
    echo "ERROR: Could not find 'nix' command. Please ensure Nix $MIN_NIX_VERSION or higher is installed."
    exit 1
  fi

  if [[ ! -f $projDir/flake.nix ]]; then
    echo "ERROR: Could not find 'flake.nix' (expected location: $projDir/flake.nix)."
    echo "Please ensure it is present and this script is located in $projDir/other/"
    echo "Aborting build."
    exit 1
  fi

  cd "$projDir"

  if [[ "$DEBUG_NIX" = true ]]; then
    nixStoreRefs=`grep '/nix/store/' "$projDir/iina.xcodeproj/project.pbxproj" || true`
    if [ -n "$nixStoreRefs" ]; then
      echo "ERROR: Found reference(s) to '/nix/store/' in project.pbxproj!"
      echo "Ensure all framework references in the project files use relative paths which begin with 'deps/lib/'"
      echo "Aborting build."
      exit 1
    fi
    $nixExec build --keep-failed --print-build-logs --verbose
  else
    $nixExec build --print-build-logs --verbose
  fi
fi

appContentsDir="$projDir/result/Applications/IINA.app/Contents"

if [[ "$REPLACE_LIBS" = true ]]; then
  srcLibDir="$appContentsDir/Frameworks"
  dstLibDir="$projDir/deps/lib"
  echo "📎 Replacing libs @ $dstLibDir …"
  rm -rf "$dstLibDir"
  mkdir -p "$dstLibDir"

  for srclib in $(ls $srcLibDir)
  do
    if [[ "$srclib" == *".dylib" ]]; then
      cp -v "$srcLibDir/$srclib" "$dstLibDir/"
    fi
  done
fi

if [[ "$REPLACE_EXECUTABLES" = true ]]; then
  srcExecutablesDir="$appContentsDir/MacOS"
  dstExecutablesDir="$projDir/deps/executable"
  echo "📎 Replacing executables @ $dstExecutablesDir …"
  rm -rf "$dstExecutablesDir"
  mkdir -p "$dstExecutablesDir"
  for executable in $(ls $srcExecutablesDir)
  do
    if [[ "$executable" != *"iina"* ]] && [[ "$executable" != *"IINA"* ]]; then
      cp -v "$srcExecutablesDir/$executable" "$dstExecutablesDir/"
    fi
  done
fi

if [[ "$REPLACE_INCLUDES" = true ]]; then
  srcIncludeDir="$projDir/result/include"
  dstIncludeDir="$projDir/deps/include"
  echo "📎 Replacing include files @ $dstIncludeDir …"
  mkdir -p "$dstIncludeDir"
  find "$dstIncludeDir" -name "*.h" -print0 | xargs -0 rm
  rsync -rv "$srcIncludeDir/" "$dstIncludeDir/"
  chmod -R u+rw "$dstIncludeDir"
fi

echo ""
echo "✅ Done"

