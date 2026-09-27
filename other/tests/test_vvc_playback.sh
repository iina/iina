#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo "Usage: $0 <VVC media file>" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
LIB_DIR="$ROOT_DIR/deps/lib"
SOURCE="$SCRIPT_DIR/vvc_playback.c"

shopt -s nullglob
libmpv_candidates=("$LIB_DIR"/libmpv.*.dylib)
shopt -u nullglob

if [ "${#libmpv_candidates[@]}" -ne 1 ]; then
  echo "Expected one versioned libmpv dylib in $LIB_DIR, found ${#libmpv_candidates[@]}" >&2
  exit 1
fi

if [ ! -f "$1" ]; then
  echo "VVC media file not found: $1" >&2
  exit 1
fi

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/iina-vvc-test.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

xcrun clang \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I"$ROOT_DIR/deps/include" \
  "$SOURCE" \
  "${libmpv_candidates[0]}" \
  -Wl,-rpath,"$LIB_DIR" \
  -o "$build_dir/vvc_playback"

"$build_dir/vvc_playback" "$1"
