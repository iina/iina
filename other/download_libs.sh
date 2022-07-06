#!/bin/bash

location="https://iina.io/dylibs/universal"
IFS=$'\n' read -r -d '' -a files < <(curl "${location}/filelist.txt" && printf '\0')
mkdir -p deps/lib
for file in "${files[@]}"
do
  set -x
  curl "${location}/${file}" > deps/lib/$file
  { set +x; } 2>/dev/null
done

# Use https://iina.io/dylibs/youtube-dl to get the binary included in the latest release.
mkdir -p deps/executable
curl -L 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos' -o deps/executable/youtube-dl
chmod +x deps/executable/youtube-dl
