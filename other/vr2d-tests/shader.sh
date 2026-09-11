#!/bin/bash
#
# Measure the reprojection shader against ffmpeg's `v360` filter.
#
# `v360` is the reference implementation for what these files mean — it is what
# the plugin this fork replaces used — so matching it is the working definition
# of a correct projection. For each case this renders the same view twice, once
# through IINA's shader and once through `v360`, and reports PSNR.
#
#   other/vr2d-tests/shader.sh <path-to-IINA.app> [work-directory]
#
# Every case is one line of the table below:
#
#   name | pattern | v360 input | shader projection | in h-fov | in v-fov | layout | swap | eye | yaw | pitch | fov
#
# The pattern's red and green channels are the source coordinates themselves, so
# each rendered pixel says which direction on the sphere it sampled. The measure
# is therefore the angle between the direction this shader sampled and the one
# v360 sampled — see compare.py for why that beats PSNR here.

set -e

app="${1:?usage: shader.sh <path-to-IINA.app> [work-directory]}"
work="${2:-$(mktemp -d)}"
here="$(cd "$(dirname "$0")" && pwd)"
# Pass marks, in degrees. The pattern encodes longitude in 8 bits over 360°, so
# one colour step is 1.41° and the measurement cannot resolve anything finer:
# two renders that sample the very same source pixel still report up to one step
# apart at the edges of a bilinear tap. The bar is therefore a median inside
# half a step — most pixels identical — and a 95th percentile inside one step.
median_threshold="${VR2D_MEDIAN_THRESHOLD:-0.75}"
threshold="${VR2D_ANGLE_THRESHOLD:-1.5}"

"$here/fixtures.sh" "$work" >/dev/null
mkdir -p "$work/run" "$work/home"

cases=$(cat <<'EOF'
he_centre|he|he|he|180|180|mono|false|left|0|0|90
he_yaw30|he|he|he|180|180|mono|false|left|30|0|90
he_yaw-30|he|he|he|180|180|mono|false|left|-30|0|90
he_pitch20|he|he|he|180|180|mono|false|left|0|20|90
he_pitch-20|he|he|he|180|180|mono|false|left|0|-20|90
he_wide|he|he|he|180|180|mono|false|left|15|-10|130
he_narrow|he|he|he|180|180|mono|false|left|-40|25|40
e_centre|e|e|e|360|180|mono|false|left|0|0|90
e_yaw90|e|e|e|360|180|mono|false|left|90|0|90
e_yaw-120|e|e|e|360|180|mono|false|left|-120|0|90
e_pitch60|e|e|e|360|180|mono|false|left|0|60|90
e_pitch-75|e|e|e|360|180|mono|false|left|0|-75|90
e_corner|e|e|e|360|180|mono|false|left|140|-35|120
fisheye180|fisheye180|fisheye|fisheye|180|180|mono|false|left|0|0|90
fisheye190_yaw25|fisheye190|fisheye|fisheye|190|190|mono|false|left|25|0|90
fisheye200_pitch20|fisheye200|fisheye|fisheye|200|200|mono|false|left|0|20|90
fisheye200_corner|fisheye200|fisheye|fisheye|200|200|mono|false|left|-35|15|110
fisheye220|fisheye220|fisheye|fisheye|220|220|mono|false|left|20|-20|90
eac_centre|eac|eac|eac|360|180|mono|false|left|0|0|90
eac_yaw90|eac|eac|eac|360|180|mono|false|left|90|0|90
eac_yaw180|eac|eac|eac|360|180|mono|false|left|180|0|90
eac_pitch70|eac|eac|eac|360|180|mono|false|left|0|70|90
eac_pitch-70|eac|eac|eac|360|180|mono|false|left|0|-70|90
sbs_left|he_sbs|he|he|180|180|sbs|false|left|10|5|90
sbs_right|he_sbs|he|he|180|180|sbs|false|right|10|5|90
sbs_swapped_left|he_sbs|he|he|180|180|sbs|true|left|10|5|90
tb_left|he_tb|he|he|180|180|tb|false|left|-15|8|90
tb_right|he_tb|he|he|180|180|tb|false|right|-15|8|90
EOF
)

# `VR2D_ONLY` narrows the run to the cases whose name matches, for when one
# projection is being worked on.
if [ -n "${VR2D_ONLY:-}" ]; then
  cases=$(echo "$cases" | grep -E "^${VR2D_ONLY}")
fi

# One IINA run per pattern: the self-test fires when a file loads, and each run
# opens one file.
patterns=$(echo "$cases" | cut -d'|' -f2 | sort -u)

for pattern in $patterns; do
  rm -rf "$work/run"; mkdir -p "$work/run"
  {
    echo "["
    echo "$cases" | awk -F'|' -v p="$pattern" 'BEGIN {first = 1}
      $2 == p {
        if (!first) printf ",\n"; first = 0
        printf "  {\"name\":\"%s\",\"projection\":\"%s\",\"inHFov\":%s,\"inVFov\":%s,\"layout\":\"%s\",\"swapEyes\":%s,\"eye\":\"%s\",\"yaw\":%s,\"pitch\":%s,\"fov\":%s}",
               $1, $4, $5, $6, $7, $8, $9, $10, $11, $12
      }
      END { print "" }'
    echo "]"
  } > "$work/run/cases.json"

  # `-key value` pairs land in NSUserDefaults' argument domain, which overrides
  # the stored preferences for this launch only and leaves the user's own
  # settings alone. IINA's own argument parser skips them.
  #
  # Plugins have to be off: a JS plugin that reprojects with the `v360` filter —
  # such as the one this fork replaces — would hand the shader an already
  # reprojected frame, and the resulting mess looks exactly like a shader bug.
  HOME="$work/home" IINA_VR2D_SELFTEST="$work/run" \
    timeout 180 "$app/Contents/MacOS/IINA" \
      -vr2dAutoDetect NO \
      "$work/pattern_$pattern.mkv" >"$work/run/iina.log" 2>&1 || true

  if grep -q "Loaded JS plugin" "$work/run/iina.log"; then
    echo "a plugin loaded during the self-test; its filters would corrupt the comparison" >&2
    exit 1
  fi

  echo "$cases" | awk -F'|' -v p="$pattern" '$2 == p' | while IFS='|' read -r name pat input proj inh inv layout swap eye yaw pitch fov; do
    rendered="$work/run/$name.png"
    if [ ! -f "$rendered" ]; then
      printf '%-22s NOT RENDERED\n' "$name"
      echo "$name FAIL" >> "$work/results"
      continue
    fi

    size=$(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$rendered")
    w="${size%%,*}"; h="${size##*,}"

    # The plugin cropped one eye out before reprojecting, and that crop is what
    # the shader's eye transform reproduces. Same crop here.
    crop=""
    if [ "$layout" = "sbs" ]; then
      if [ "$eye$swap" = "leftfalse" ] || [ "$eye$swap" = "righttrue" ]; then
        crop="crop=iw/2:ih:0:0,"
      else
        crop="crop=iw/2:ih:iw/2:0,"
      fi
    elif [ "$layout" = "tb" ]; then
      if [ "$eye$swap" = "leftfalse" ] || [ "$eye$swap" = "righttrue" ]; then
        crop="crop=iw:ih/2:0:0,"
      else
        crop="crop=iw:ih/2:0:ih/2,"
      fi
    fi

    infov_opts=""
    if [ "$input" = "he" ] || [ "$input" = "fisheye" ]; then
      infov_opts="ih_fov=$inh:iv_fov=$inv:"
    fi

    reference="$work/run/${name}_reference.png"
    ffmpeg -v error -y -i "$work/pattern_$pat.png" \
      -vf "format=gbrp,${crop}v360=input=$input:output=flat:${infov_opts}interp=line:w=$w:h=$h:d_fov=$fov:yaw=$yaw:pitch=$pitch:roll=0" \
      "$reference"

    ffmpeg -v error -y -i "$rendered" -f rawvideo -pix_fmt rgb24 "$work/run/a.rgb"
    ffmpeg -v error -y -i "$reference" -f rawvideo -pix_fmt rgb24 "$work/run/b.rgb"
    set -- $(python3 "$here/compare.py" "$work/run/a.rgb" "$work/run/b.rgb" "$w" "$h")

    verdict=$(awk -v med="$1" -v p95="$2" -v void="$3" -v tint="$4" \
                   -v t="$threshold" -v m="$median_threshold" \
      'BEGIN { print (med + 0 <= m && p95 + 0 <= t && void + 0 <= 0.5 && tint + 0 <= 5) ? "ok" : "FAIL" }')
    printf '%-22s  median %6s°  p95 %6s°  edge %5s%%  eye %6s%%  %s\n' \
      "$name" "$1" "$2" "$3" "$4" "$verdict"
    echo "$name $verdict" >> "$work/results"
  done
done

failures=$(grep -c FAIL "$work/results" 2>/dev/null || true)
total=$(wc -l < "$work/results" | tr -d ' ')
rm -f "$work/results"
echo
if [ "${failures:-0}" -gt 0 ]; then
  echo "$failures of $total cases exceed ${median_threshold}° median or ${threshold}° p95 — work directory kept at $work"
  exit 1
fi
echo "all $total cases agree with v360 to within one step of the encoding"
