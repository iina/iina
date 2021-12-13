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
