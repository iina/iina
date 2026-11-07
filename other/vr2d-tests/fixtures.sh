#!/bin/bash
#
# Build the test patterns the shader is measured against.
#
# The base pattern is an equirectangular image whose red and green channels
# encode the pixel's own position, overlaid with a 15° graticule. Because the
# colour *is* the coordinate, a render of it says exactly which source pixel was
# sampled — so a transposed axis or a rotated cube face shows up as a wrong
# colour rather than as a picture that merely looks a bit odd. The graticule is
# there for the human check: in a rectilinear projection its lines must come out
# straight.
#
# The other projections are made from the base pattern by `v360`, so every
# fixture describes the same sphere.

set -e

out="${1:?usage: fixtures.sh <output-directory>}"
mkdir -p "$out"

# Equirectangular, 2:1. R encodes longitude, G encodes latitude.
if [ ! -f "$out/pattern_e.png" ]; then
  ffmpeg -v error -y -f lavfi -i color=c=black:s=2048x1024 -frames:v 1 \
    -vf "geq=r='255*X/W':g='255*Y/H':b='if(lt(mod(X,85.33),2)+lt(mod(Y,85.33),2),255,40)'" \
    "$out/pattern_e.png"
fi

# 180° equirectangular, one square hemisphere.
if [ ! -f "$out/pattern_he.png" ]; then
  ffmpeg -v error -y -i "$out/pattern_e.png" \
    -vf "format=gbrp,v360=input=e:output=he:h_fov=180:v_fov=180:w=1024:h=1024" \
    "$out/pattern_he.png"
fi

# Equidistant fisheye at a few lens angles.
for fov in 180 190 200 220; do
  if [ ! -f "$out/pattern_fisheye$fov.png" ]; then
    ffmpeg -v error -y -i "$out/pattern_e.png" \
      -vf "format=gbrp,v360=input=e:output=fisheye:h_fov=$fov:v_fov=$fov:w=1024:h=1024" \
      "$out/pattern_fisheye$fov.png"
  fi
done

# Equi-angular cubemap, in the 3x2 packing.
if [ ! -f "$out/pattern_eac.png" ]; then
  ffmpeg -v error -y -i "$out/pattern_e.png" \
    -vf "format=gbrp,v360=input=e:output=eac:w=1536:h=1024" \
    "$out/pattern_eac.png"
fi

# Stereo packings. The second eye is tinted so that picking the wrong one is
# unmistakable rather than merely suspicious.
if [ ! -f "$out/pattern_he_sbs.png" ]; then
  ffmpeg -v error -y -i "$out/pattern_he.png" -i "$out/pattern_he.png" \
    -filter_complex "[1:v]colorchannelmixer=bb=0.3[right];[0:v][right]hstack" \
    "$out/pattern_he_sbs.png"
fi
if [ ! -f "$out/pattern_he_tb.png" ]; then
  ffmpeg -v error -y -i "$out/pattern_he.png" -i "$out/pattern_he.png" \
    -filter_complex "[1:v]colorchannelmixer=bb=0.3[bottom];[0:v][bottom]vstack" \
    "$out/pattern_he_tb.png"
fi

# IINA needs something it will keep on screen, and mpv drops a still image after
# a second. A lossless RGB video of the same picture is byte-identical to the
# PNG the references are rendered from, so nothing is lost to encoding.
for pattern in "$out"/pattern_*.png; do
  movie="${pattern%.png}.mkv"
  if [ ! -f "$movie" ]; then
    ffmpeg -v error -y -loop 1 -i "$pattern" -t 20 -r 5 -c:v ffv1 -pix_fmt gbrp "$movie"
  fi
done

echo "fixtures ready in $out"
