#!/bin/bash
set -eu
repo_dir="$(cd "$(dirname "$0")/../../.." && pwd)"
TRACK_SETTINGS_ONLY=1 MULTITRACK_OUTPUT_DIR="${TRACK_SETTINGS_OUTPUT_DIR:-$repo_dir/build/track-processing-tests}" bash "$repo_dir/other/tests/multitrack-playback/run.sh"
