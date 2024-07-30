#!/bin/bash

PROJECT_NAME='iina'

# universal | arm64 | x86_64
ARCH="universal"
# github | iina (use iina to get the binary included in the latest release)
YT_DLP_SOURCE="github"
PARALLEL_DOWNLOADS=5

DYLIBS_DOWNLOAD_PATH="https://iina.io/dylibs/${ARCH}"
YT_DLP_DOWNLOAD_PATH="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Reset in case getopts has been used previously in the shell.
if ! OPTS=$(getopt -o "h": --long "arch:,yt-dlp-src:,parallel:,help": -n 'parse-options' -- "$@"); then
  echo -e "${RED}Failed parsing options.${NC}" >&2
  exit 1
fi

printUsageHelp() {
  echo
  echo -e "${BLUE}Usage:${NC}"
  echo -e "    ${GREEN}$0 [-h|--help]:${NC}           Displays this help message"
  echo -e "    ${GREEN}$0 [--arch] <ARCH>:${NC}       Architecture to download dylibs for: universal | arm64 | x86_64"
  echo -e "    ${GREEN}$0 [--yt-dlp-src] <SRC>:${NC}  Source to download youtube-dl from: github | iina"
  echo -e "    ${GREEN}$0 [--parallel] <N>:${NC}      Number of parallel downloads (default: 5)"
  echo
}

realpath() (
  OURPWD=$PWD
  cd "$(dirname "$1")" || exit
  LINK=$(readlink "$(basename "$1")")
  while [ "$LINK" ]; do
    cd "$(dirname "$LINK")" || exit
    LINK=$(readlink "$(basename "$1")")
  done
  REALPATH="$PWD/$(basename "$1")"
  cd "$OURPWD" || exit
  echo "$REALPATH"
)

while true; do
  case "$1" in
  -h | --help)
    printUsageHelp
    exit 0
    ;;
  --arch)
    if [[ -z "$2" ]]; then
      echo -e "${RED}You need to specify an architecture when using --arch${NC}"
      printUsageHelp
      exit 1
    fi
    ARCH=$2
    shift 2
    ;;
  --yt-dlp-src)
    if [[ -z "$2" ]]; then
      echo -e "${RED}You need to specify a source when using --yt-dlp-src${NC}"
      printUsageHelp
      exit 1
    fi
    YT_DLP_SOURCE=$2
    shift 2
    ;;
  --parallel)
    if [[ -z "$2" ]]; then
      echo -e "${RED}You need to specify a number of parallel downloads when using --parallel${NC}"
      printUsageHelp
      exit 1
    fi
    PARALLEL_DOWNLOADS=$2
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *) break ;;
  esac
done

case $YT_DLP_SOURCE in
github)
  YT_DLP_DOWNLOAD_PATH="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
  ;;
iina)
  YT_DLP_DOWNLOAD_PATH="https://iina.io/dylibs/youtube-dl"
  ;;
*)
  echo -e "${RED}Invalid youtube-dl source: $YT_DLP_SOURCE${NC}"
  printUsageHelp
  exit 1
  ;;
esac

case $ARCH in
universal | arm64 | x86_64)
  DYLIBS_DOWNLOAD_PATH="https://iina.io/dylibs/${ARCH}"
  ;;
*)
  echo -e "${RED}Invalid architecture: $ARCH${NC}"
  printUsageHelp
  exit 1
  ;;
esac

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

DEPS_PATH="$ROOT_PATH/deps"
LIB_PATH="$DEPS_PATH/lib"
EXEC_PATH="$DEPS_PATH/executable"
YT_DLP_PATH="$EXEC_PATH/youtube-dl"

IFS=$'\n' read -r -d '' -a files < <(curl -s "${DYLIBS_DOWNLOAD_PATH}/filelist.txt" && printf '\0')

mkdir -p "$LIB_PATH"

echo -e "${BLUE}Starting downloads in parallel...${NC}"

# Function to download a single file
download_file() {
  local file="$1"
  echo -e "${YELLOW}Downloading ${file}...${NC}"
  curl -s "${DYLIBS_DOWNLOAD_PATH}/${file}" -o "${LIB_PATH}/${file}" && echo -e "${GREEN}Downloaded ${file}${NC}"
}

# Export the function so it can be used by xargs
export -f download_file
export DYLIBS_DOWNLOAD_PATH
export LIB_PATH
export YELLOW
export GREEN
export NC

# Process files in smaller batches using xargs
printf "%s\n" "${files[@]}" | xargs -n 1 -P "$PARALLEL_DOWNLOADS" bash -c 'download_file "$@"' _

mkdir -p "$EXEC_PATH"
echo -e "${YELLOW}Downloading yt-dlp...${NC}"
curl -s -L "$YT_DLP_DOWNLOAD_PATH" -o "$YT_DLP_PATH" && echo -e "${GREEN}yt-dlp downloaded${NC}"
chmod +x "$YT_DLP_PATH"

echo -e "${GREEN}All downloads completed.${NC}"

