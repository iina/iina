#!/bin/bash
#
# Unit tests for the pure parts of VR2D.
#
# `VR2DGeometry.swift` and `VR2DDetect.swift` deliberately depend on nothing but
# Foundation, so they can be compiled straight out of the app target and tested
# without building — or launching — IINA.

set -e

here="$(cd "$(dirname "$0")" && pwd)"
vr2d="$here/../../iina/VR2D"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

swiftc -O \
  "$vr2d/VR2DGeometry.swift" \
  "$vr2d/VR2DDetect.swift" \
  "$here/main.swift" \
  -o "$out/vr2d-tests"

"$out/vr2d-tests"
