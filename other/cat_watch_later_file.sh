#!/bin/bash

#
#  cat_watch_later_file.sh
#  iina
#
#  Created by low-batt on 6/1/26.
#  Copyright © 2026 lhc. All rights reserved.
#

# Show the contents of the mpv watch later file for the specified media. This
# script expects the full pathname or URL of the media as the first and only
# argument. This must match the string IINA passed to libmpv in the loadfile
# command for the watch later file to be found. This is a tool for developers
# to use when working on watch later related issues.
#
# Example use:
# low-batt@gag other (md5 *$%=)$ ./cat_watch_later_file.sh "$HOME/Movies/big_buck_bunny.mp4"
# start=212.600000
# sid=1
# low-batt@gag other (md5 *$%=)$ 

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Must be invoked with one argument.
if [ "$#" -lt 1 ]
then
  echo -e "${RED}Usage: $0 <full pathname or URL of the media>${NC}" >&2
  exit 1
fi
# The argument must not be empty.
if [ -z "$1" ]
then
  echo -e "${RED}Pathname / URL argument cannot be empty${NC}" >&2
  exit 1
fi
# No more than one argument can be supplied.
if [ "$#" -ne 1 ]
then
  echo -e "${RED}Too many arguments${NC}" >&2
  exit 1
fi

filename=$(md5 -qs "$1" | awk '{print toupper($0)}')
path="$HOME/Library/Application Support/com.colliderli.iina/watch_later/$filename"

# The media won't have a file if it is currently being played, if it was played
# to the end or if the user switched to another file in the playlist, etc.
if [ ! -f "$path" ]; then
  echo -e "${GREEN}No watch later file found for this media${NC}" >&2
  exit
fi

cat "$path"
