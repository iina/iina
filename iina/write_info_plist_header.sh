#!/bin/sh

#  write_info_plist_header.sh
#  iina
#
#  Created by low-batt on 10/5/22.
#  Copyright © 2022 lhc. All rights reserved.

# Xcode supports a "Preprocess Info.plist File" setting. When this is enabled Xcode will preprocess
# the Info.plist file using the C Preprocessor. The setting "Info.plist Preprocessor Prefix File"
# can then be used to implicitly include a file when preprocessing the Info.plist file. That include
# file can contain definitions for identifiers to be replaced by the C preprocessor.

# IINA enables preprocessing and sets the name of the header file to "Info.h". This script is
# executed in a Xcode build phase to generate that file each time a build is run. This is how build
# specific information can be included in the Info.plist file.

# Follow Xcode guidelines on how to use the echo command to log messages from a script.
alias error='echo [write_info_plist_header.sh]: error:'
alias note='echo [write_info_plist_header.sh]: note:'

# Confirm the environment variable supplied by Xcode giving the path to the header file to create
# is present.
if [[ -z "$INFOPLIST_PREFIX_HEADER" ]]; then
  error Missing build-system environment variable INFOPLIST_PREFIX_HEADER
  note This script is intended to be run in a Xcode build phase
  exit 1
fi

# Check if git is on the path.
GIT=$(which git)
if [[ -z "$GIT" ]]; then
  # Use Xcode's git.
  GIT=`xcrun -find git`
fi
if [[ -z "$GIT" ]]; then
  error Unable to locate git executable
  exit 1
fi

# Get the information needed for the header file.
BRANCH=$($GIT rev-parse --abbrev-ref HEAD)
COMMIT=$($GIT rev-parse HEAD)
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Write the Info.plist header file.
cat <<-EOF > "$INFOPLIST_PREFIX_HEADER"
#define IINA_BUILD_BRANCH ${BRANCH}
#define IINA_BUILD_COMMIT ${COMMIT}
#define IINA_BUILD_DATE ${DATE}
EOF

note Wrote $INFOPLIST_PREFIX_HEADER
