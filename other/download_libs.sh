#!/bin/bash

PROJECT_NAME='iina'

# universal | arm64 | x86_64
ARCH="universal"
# github | iina (use iina to get the binary included in the latest release)
YT_DLP_SOURCE="github"

DYLIBS_DOWNLOAD_PATH="https://iina.io/dylibs/${ARCH}"
YT_DLP_DOWNLOAD_PATH="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

# Reset in case getopts has been used previously in the shell.
if ! OPTS=$(getopt -o "h": --long "arch:,yt-dlp-src,help": -n 'parse-options' -- "$@"); then
  echo "Failed parsing options." >&2
  exit 1
fi

printUsageHelp() {
  echo
  echo "Usage:"
  echo "    $0 [-h|--help]:           Displays this help message"
  echo "    $0 [--arch] <ARCH>:       Architecture to download dylibs for: universal | arm64 | x86_64"
  echo "    $0 [--yt-dlp-src] <SRC>:  Source to download youtube-dl from: github | iina"
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
      echo "You need to specify an architecture when using --arch"
      printUsageHelp
      exit 1
    fi
    ARCH=$2
    shift 2
    ;;
  --yt-dlp-src)
    if [[ -z "$2" ]]; then
      echo "You need to specify a source when using --yt-dlp-src"
      printUsageHelp
      exit 1
    fi
    YT_DLP_SOURCE=$2
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
  echo "Invalid youtube-dl source: $YT_DLP_SOURCE"
  printUsageHelp
  exit 1
  ;;
esac

case $ARCH in
universal | arm64 | x86_64)
  DYLIBS_DOWNLOAD_PATH="https://iina.io/dylibs/${ARCH}"
  ;;
*)
  echo "Invalid architecture: $ARCH"
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
    echo "Unable to find the root directory '$PROJECT_NAME' containing the script file." >&2
    exit 1
  fi
fi

DEPS_PATH="$ROOT_PATH/deps"
LIB_PATH="$DEPS_PATH/lib"
EXEC_PATH="$DEPS_PATH/executable"
YT_DLP_PATH="$EXEC_PATH/youtube-dl"

IFS=$'\n' read -r -d '' -a files < <(curl "${DYLIBS_DOWNLOAD_PATH}/filelist.txt" && printf '\0')

mkdir -p "$LIB_PATH"

for FILE in "${files[@]}"; do
  set -x
  curl "${DYLIBS_DOWNLOAD_PATH}/${FILE}" >"$LIB_PATH/$FILE"
  { set +x; } 2>/dev/null
done

mkdir -p "$EXEC_PATH"
curl -L "$YT_DLP_DOWNLOAD_PATH" -o "$YT_DLP_PATH"
chmod +x "$YT_DLP_PATH"
