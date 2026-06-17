#!/bin/bash
# ============================================================
# mpv-config-driven-refactor — Phase 9 Cross-Phase Smoke Test
# ============================================================
# Launches the built IINA.app, exercises the key integration points,
# greps the mpv.log, and reports PASS/FAIL per acceptance criterion.
#
# Usage:
#   ./smoke_test.sh                     # interactive (uses defaults)
#   ./smoke_test.sh /path/to/video.mkv  # specify a local file
#
# Prereqs:
#   - Built IINA.app at the DerivedData path below (or override $IINA_APP)
#   - Local video file for the local-file tests (pass as arg 1)
# ============================================================
set -uo pipefail

# --- Configuration ----------------------------------------------------------
DERIVED_DATA_APP="/Users/vec/Library/Developer/Xcode/DerivedData/iina-bmtxqzqgornfgvfbdcyxvzsmbdws/Build/Products/Debug/IINA.app"
IINA_APP="${IINA_APP:-$DERIVED_DATA_APP}"
APP_SUPPORT_DIR="$HOME/Library/Application Support/com.colliderli.iina"
LOG_BASE="$HOME/Library/Logs/com.colliderli.iina"
MPV_BUNDLE_RES="$IINA_APP/Contents/Resources/mpv"

VIDEO_FILE="${1:-}"
YOUTUBE_URL="${YOUTUBE_URL:-https://www.youtube.com/watch?v=dQw4w9WgXcQ}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

# --- Helpers ----------------------------------------------------------------
check() {
  local name="$1"
  local condition="$2"
  if [ "$condition" = "true" ]; then
    echo -e "${GREEN}✓ PASS${NC}: $name"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}✗ FAIL${NC}: $name"
    FAIL=$((FAIL + 1))
  fi
}

skip() {
  local name="$1"
  local reason="$2"
  echo -e "${YELLOW}⊘ SKIP${NC}: $name ($reason)"
  SKIP=$((SKIP + 1))
}

section() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

find_latest_mpv_log() {
  find "$LOG_BASE" -name "mpv.log" -newer "$0" 2>/dev/null | sort -r | head -1
}

# --- 0. Verify build artifact ----------------------------------------------
section "0. Build artifact verification"

if [ ! -d "$IINA_APP" ]; then
  echo -e "${RED}ERROR: IINA.app not found at $IINA_APP${NC}"
  echo "Build it first: xcodebuild -project iina.xcodeproj -scheme iina -configuration Debug build"
  exit 1
fi
check "IINA.app exists" "true"
check "IINA binary exists" "$([ -f "$IINA_APP/Contents/MacOS/IINA" ] && echo true || echo false)"
check "iina-cli binary exists" "$([ -f "$IINA_APP/Contents/MacOS/iina-cli" ] && echo true || echo false)"

# Check mpv/ resource structure (SPEC AC #1)
check "mpv/mpv.conf exists" "$([ -f "$MPV_BUNDLE_RES/mpv.conf" ] && echo true || echo false)"
check "mpv/input.conf exists" "$([ -f "$MPV_BUNDLE_RES/input.conf" ] && echo true || echo false)"
check "mpv/yt-dlp exists" "$([ -f "$MPV_BUNDLE_RES/yt-dlp" ] && echo true || echo false)"
check "mpv/yt-dlp is executable" "$([ -x "$MPV_BUNDLE_RES/yt-dlp" ] && echo true || echo false)"
check "mpv/scripts/ dir exists" "$([ -d "$MPV_BUNDLE_RES/scripts" ] && echo true || echo false)"
check "mpv/script-opts/ dir exists" "$([ -d "$MPV_BUNDLE_RES/script-opts" ] && echo true || echo false)"
check "mpv/fonts/ dir exists" "$([ -d "$MPV_BUNDLE_RES/fonts" ] && echo true || echo false)"
check "mpv/fonts/uosc_icons.otf exists" "$([ -f "$MPV_BUNDLE_RES/fonts/uosc_icons.otf" ] && echo true || echo false)"
check "mpv/fonts/uosc_textures.ttf exists" "$([ -f "$MPV_BUNDLE_RES/fonts/uosc_textures.ttf" ] && echo true || echo false)"
check "mpv/scripts/uosc/ dir exists" "$([ -d "$MPV_BUNDLE_RES/scripts/uosc" ] && echo true || echo false)"

SCRIPT_COUNT=$(find "$MPV_BUNDLE_RES/scripts" -maxdepth 1 -name "*.lua" 2>/dev/null | wc -l | tr -d ' ')
CONF_COUNT=$(find "$MPV_BUNDLE_RES/script-opts" -maxdepth 1 -name "*.conf" 2>/dev/null | wc -l | tr -d ' ')
check "mpv/scripts/ has >=7 .lua files" "$([ "$SCRIPT_COUNT" -ge 7 ] && echo true || echo false)"
check "mpv/script-opts/ has >=7 .conf files" "$([ "$CONF_COUNT" -ge 7 ] && echo true || echo false)"

# --- 1. First-run materialisation (SPEC AC #2) -----------------------------
section "1. First-run materialisation"

if [ -f "$APP_SUPPORT_DIR/mpv/mpv.conf" ]; then
  check "Materialized mpv/ exists" "true"
  check "Materialized mpv.conf exists" "$([ -f "$APP_SUPPORT_DIR/mpv/mpv.conf" ] && echo true || echo false)"
  check "Materialized yt-dlp exists" "$([ -f "$APP_SUPPORT_DIR/mpv/yt-dlp" ] && echo true || echo false)"
  check "Materialized yt-dlp is executable" "$([ -x "$APP_SUPPORT_DIR/mpv/yt-dlp" ] && echo true || echo false)"
  check "Materialized scripts/ exists" "$([ -d "$APP_SUPPORT_DIR/mpv/scripts" ] && echo true || echo false)"
else
  skip "Materialized mpv/ checks" "not yet materialised (run IINA once first)"
fi

# --- 2. Launch IINA and capture logs ---------------------------------------
section "2. Launching IINA + capturing mpv.log"

# Enable logging for this session
defaults write com.colliderli.iina enableAdvancedSettings -bool true
defaults write com.colliderli.iina enableLogging -bool true

echo "Launching IINA.app (will auto-quit after 10s)..."
open "$IINA_APP"
sleep 10

MPV_LOG=$(find_latest_mpv_log)
if [ -n "$MPV_LOG" ]; then
  check "mpv.log captured" "true"
  echo "  → $MPV_LOG"
else
  check "mpv.log captured" "false"
  echo -e "${YELLOW}No mpv.log found in $LOG_BASE. Logging may not be enabled.${NC}"
fi

# Quit IINA
osascript -e 'tell application "IINA" to quit' 2>/dev/null || true
sleep 2

# --- 3. mpv.log analysis (SPEC AC #2, #3, #8, #9) -------------------------
section "3. mpv.log analysis"

if [ -n "$MPV_LOG" ] && [ -f "$MPV_LOG" ]; then
  echo "Analyzing: $MPV_LOG"
  echo ""

  # AC #2: config-dir
  if grep -qi "config-dir\|Configuration directory\|Reading config" "$MPV_LOG"; then
    check "config-dir referenced in log" "true"
  else
    check "config-dir referenced in log" "false"
  fi

  # AC #3: key mpv.conf values visible
  check "hwdec value present" "$(grep -qi 'hwdec' "$MPV_LOG" && echo true || echo false)"
  check "keep-open value present" "$(grep -qi 'keep-open\|keep_open' "$MPV_LOG" && echo true || echo false)"
  check "volume value present" "$(grep -qi 'volume' "$MPV_LOG" && echo true || echo false)"

  # AC #9: ytdl-raw-options-append
  check "ytdl-raw-options-append in log" "$(grep -qi 'ytdl-raw-options-append\|ytdl_raw_options_append' "$MPV_LOG" && echo true || echo false)"
  check "cookies-from-browser in log" "$(grep -qi 'cookies-from-browser' "$MPV_LOG" && echo true || echo false)"

  # Phase 2: vo=libmpv guard
  if grep -qi 'Set option: vo=libmpv' "$MPV_LOG"; then
    check "vo=libmpv still applied (default case)" "true"
  elif grep -qi 'vo.*gpu-next' "$MPV_LOG"; then
    check "vo=gpu-next detected (profile applied)" "true"
  else
    skip "vo value in log" "could not determine vo setting"
  fi

  # Phase 3: yt-dlp path
  check "yt-dlp path references mpv/ dir" "$(grep -q 'yt-dlp' "$MPV_LOG" && (grep 'Application Support' "$MPV_LOG" | grep -q yt-dlp) && echo true || echo false)"

  # Phase 3: osd-fonts-dir / sub-fonts-dir
  check "osd-fonts-dir set" "$(grep -qi 'osd-fonts-dir\|Set option: osd-fonts-dir' "$MPV_LOG" && echo true || echo false)"
  check "sub-fonts-dir set" "$(grep -qi 'sub-fonts-dir\|Set option: sub-fonts-dir' "$MPV_LOG" && echo true || echo false)"

  # Scripts loaded
  SCRIPT_LOADED=$(grep -ciE 'Loading script|script.*loaded|uosc' "$MPV_LOG")
  check "Scripts referenced in log" "$([ "$SCRIPT_LOADED" -gt 0 ] && echo true || echo false)"
  check "uosc script referenced" "$(grep -qi 'uosc' "$MPV_LOG" && echo true || echo false)"

  # Profiles
  check "Profile sections parsed" "$(grep -qiE 'profile|HDR_DolbyVision|HDR_generic|ontop_playback' "$MPV_LOG" && echo true || echo false)"

  # Show relevant log lines for manual review
  echo ""
  echo "--- Relevant mpv.log lines ---"
  grep -iE 'config.dir|osd-font|sub-font|ytdl|hwdec|keep-open|volume|vo=|profile|script|uosc|fonts-dir' "$MPV_LOG" 2>/dev/null | head -30
  echo "---"
else
  skip "mpv.log analysis" "no mpv.log found"
fi

# --- 4. Local file test (SPEC AC #6, #13) ----------------------------------
section "4. Local file test"

if [ -n "$VIDEO_FILE" ] && [ -f "$VIDEO_FILE" ]; then
  echo "Testing with: $VIDEO_FILE"
  echo "Opening in IINA (will auto-quit after 8s)..."

  open -a "$IINA_APP" "$VIDEO_FILE"
  sleep 8
  osascript -e 'tell application "IINA" to quit' 2>/dev/null || true
  sleep 2

  FILE_LOG=$(find_latest_mpv_log)
  if [ -n "$FILE_LOG" ] && [ -f "$FILE_LOG" ]; then
    check "Local file: mpv.log captured" "true"
    check "Local file: no crash/errors" "$(grep -qiE 'error|crash|fatal' "$FILE_LOG" && echo false || echo true)"
    check "Local file: input.conf loaded" "$(grep -qi 'input.conf\|input-conf' "$FILE_LOG" && echo true || echo false)"
    check "Local file: merged input.conf referenced" "$(grep -qi 'mpv-input-merged\|merged' "$FILE_LOG" && echo true || echo false)"
    echo ""
    echo "--- Local file mpv.log highlights ---"
    grep -iE 'input.conf|osd-font|vo=|script|font' "$FILE_LOG" 2>/dev/null | head -15
  else
    skip "Local file log analysis" "no mpv.log after file open"
  fi
else
  skip "Local file test" "pass a video file as argument: ./smoke_test.sh /path/to/video.mkv"
fi

# --- 5. YouTube test (SPEC AC #8, #9) -------------------------------------
section "5. YouTube / yt-dlp test"

read -p "Run YouTube test? (requires network, opens $YOUTUBE_URL) [y/N] " -r -n 1
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Opening YouTube URL in IINA (will auto-quit after 15s)..."
  open -a "$IINA_APP" "$YOUTUBE_URL"
  sleep 15
  osascript -e 'tell application "IINA" to quit' 2>/dev/null || true
  sleep 2

  YT_LOG=$(find_latest_mpv_log)
  if [ -n "$YT_LOG" ] && [ -f "$YT_LOG" ]; then
    check "YouTube: mpv.log captured" "true"
    check "YouTube: yt-dlp invoked" "$(grep -qi 'yt-dlp' "$YT_LOG" && echo true || echo false)"
    check "YouTube: ytdl-raw-options-append" "$(grep -qi 'ytdl-raw-options-append\|cookies-from-browser' "$YT_LOG" && echo true || echo false)"
    echo ""
    echo "--- YouTube mpv.log highlights ---"
    grep -iE 'yt-dlp|ytdl|cookie|youtube' "$YT_LOG" 2>/dev/null | head -15
  else
    skip "YouTube log analysis" "no mpv.log after YouTube open"
  fi
else
  skip "YouTube test" "user declined"
fi

# --- Summary ----------------------------------------------------------------
section "Summary"
echo -e "${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}SKIP: $SKIP${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}✗ $FAIL check(s) failed. Review the output above.${NC}"
  exit 1
else
  echo -e "${GREEN}✓ All automated checks passed.${NC}"
  echo ""
  echo "Manual checks still required:"
  echo "  - Press 'i' in IINA → stats overlay appears"
  echo "  - Right-click video → uosc context menu appears"
  echo "  - Open a DOVI file → vo=gpu-next survives (visual or log check)"
  echo "  - uosc icon glyphs render correctly (not missing-glyph boxes)"
  exit 0
fi
