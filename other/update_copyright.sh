#!/bin/bash

# This script will update the copyright year displayed to users.
# No files are committed. Files are only changed locally. Up to
# you to review the changes and create a commit.

# Support running from either the top of the source tree or the
# "other" directory containing this script.
indir=${PWD##*/}
srcdir='iina'
if [ "$indir" = 'other' ]; then
    srcdir="../$srcdir"
fi

year=$(date +%Y)

echo "Updating copyright year to $year"

function update () {
    local dir="$1"
    local file="$2"
    find "$(cd $srcdir/$dir; pwd)" -name "$file" -exec sed -i '' "s/ 2017-2[0-9]\{3\}/ 2017-$year/" {} +
}

# Update the copyright displayed in the macOS "Get Info" window for
# the application and at the start of the log file.
update ../iina.xcodeproj project.pbxproj
update en.lproj InfoPlist.strings

# Update the copyright displayed in the about window.
update . Contribution.rtf
