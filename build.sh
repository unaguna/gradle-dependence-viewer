#!/usr/bin/env bash

################################################################################
# Error handling
################################################################################

set -eu
set -o pipefail

set -C

################################################################################
# Script information
################################################################################

# The current directory when this script started.
# ORIGINAL_PWD=$(pwd)
# readonly ORIGINAL_PWD
# The directory path of this script file
SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
readonly SCRIPT_DIR
# The path of this script file
SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_NAME


################################################################################
# Functions
################################################################################

function usage_exit () {
    echo "Usage:" "$(basename "$0")" 1>&2
    exit "$1"
}

# Output an information
#
# Because stdout is used as output of gradlew in this script,
# any messages should be output to stderr.
function echo_info () {
    echo "$SCRIPT_NAME: $*" >&2
}

# Output an error
#
# Because stdout is used as output of gradlew in this script,
# any messages should be output to stderr.
function echo_err() {
    echo "$SCRIPT_NAME: $*" >&2
}


################################################################################
# Constant values
################################################################################

readonly PROJECT_DIR="$SCRIPT_DIR"

readonly SRC_DIR="$PROJECT_DIR/src"

readonly DEST_DIR="$PROJECT_DIR/build/dest"

readonly RELEASE_DIR="$PROJECT_DIR/build/release"

# The version number of this application
GRADLE_DEPENDENCE_VIEWER_VERSION=$(cat "$PROJECT_DIR/.version")
readonly GRADLE_DEPENDENCE_VIEWER_VERSION


################################################################################
# Analyze arguments
################################################################################

if [ $# -ne 0 ]; then
    usage_exit 1
fi


################################################################################
# Temporally files
################################################################################


################################################################################
# main
################################################################################

cd "$SCRIPT_DIR"

#
# initialize destination
#

rm -Rf "$DEST_DIR"
rm -Rf "$RELEASE_DIR"


#
# collect files
#

mkdir -p "$DEST_DIR"
cp -r "$SRC_DIR"/* "$DEST_DIR"
cp "$PROJECT_DIR/.version" "$DEST_DIR"

#
# archive
#

mkdir -p "$RELEASE_DIR"
tar -C "$DEST_DIR" -czf "$RELEASE_DIR/gradle-dependence-viewer.${GRADLE_DEPENDENCE_VIEWER_VERSION}.tgz" .
