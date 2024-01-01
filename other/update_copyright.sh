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

# Update the copyright displayed in the macOS "Get Info" window for the application.
update ../iina.xcodeproj project.pbxproj

# Update the copyright displayed in the about window.
# This copyright text is contained in Contribution.rtf which is localized.
# To avoid conflicts when merging translations from Crowdin the procedure for
# modifying localized source is to only update the base and English source in
# GitHub. Changes for other languages must then be made using Crowdin.
update Base.lproj Contribution.rtf
update en.lproj Contribution.rtf
