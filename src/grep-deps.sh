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
ORIGINAL_PWD=$(pwd)
readonly ORIGINAL_PWD
# The directory path of this script file
SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
readonly SCRIPT_DIR
# The path of this script file
SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_NAME

# The version number of this application
GRADLE_DEPENDENCE_VIEWER_VERSION=$(cat "$SCRIPT_DIR/.version")
export GRADLE_DEPENDENCE_VIEWER_VERSION
readonly GRADLE_DEPENDENCE_VIEWER_VERSION
# Application name
GRADLE_DEPENDENCE_VIEWER_APP_NAME="Gradle Dependence Viewer"
export GRADLE_DEPENDENCE_VIEWER_APP_NAME
readonly GRADLE_DEPENDENCE_VIEWER_APP_NAME


################################################################################
# Include
################################################################################

# shellcheck source=libs/ana-gradle.sh
source "$SCRIPT_DIR/libs/ana-gradle.sh"


################################################################################
# Functions
################################################################################

function usage_exit () {
    echo "Usage:" "$(basename "$0") -d <dependencies_directory> <keyword>" 1>&2
    exit "$1"
}

function echo_help () {
    echo "$GRADLE_DEPENDENCE_VIEWER_APP_NAME $GRADLE_DEPENDENCE_VIEWER_VERSION"
    echo ""
    echo "Usage:" "$(basename "$0") -d <dependencies_directory> <keyword>"
    echo ""
    echo "Options"
    echo "    -d <dependencies_directory> :"
    echo "         (Required) Path of the directory where the dependence trees have been output."
    echo ""
    echo "Arguments"
    echo "    <keyword> :"
    echo "         (Required) The keyword which you are looking for."
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
# Analyze arguments
################################################################################
declare -i argc=0
declare -a argv=()
dependencies_dir=
help_flg=1
invalid_option_flg=1
while (( $# > 0 )); do
    case $1 in
        -)
            ((++argc))
            argv+=( "$1" )
            shift
            ;;
        -*)
            if [[ "$1" == '-d' ]]; then
                dependencies_dir="$2"
                shift
            elif [[ "$1" == "--help" ]]; then
                help_flg=0
                # Ignore other arguments when displaying help
                break
            else
                # The option is illegal.
                # In some cases, such as when --help is specified, illegal options may be ignored,
                # so do not exit immediately, but only flag them.
                invalid_option_flg=0
            fi
            shift
            ;;
        *)
            ((++argc))
            argv+=( "$1" )
            keywords+=( "-e" "$1" )
            shift
            ;;
    esac
done
exit_code=$?
if [ $exit_code -ne 0 ]; then
    exit $exit_code
fi

if [ "$help_flg" -eq 0 ]; then
    echo_help
    exit 0
fi

if [ "$invalid_option_flg" -eq 0 ]; then
    usage_exit 1
fi

if [ "$argc" -ne 1 ]; then
    usage_exit 1
fi

# Make output_dir absolute path in order to not depend on the current directory
# (Assume that the current directory will change.)
if [ -n "${dependencies_dir:-""}" ]
then
    dependencies_dir=$(cd "$ORIGINAL_PWD"; cd "$(dirname "$dependencies_dir")"; pwd)"/"$(basename "$dependencies_dir")
    readonly dependencies_dir
else
    usage_exit 1
fi


################################################################################
# main
################################################################################

# Validation
if [ ! -d "$dependencies_dir" ]; then
    echo_err "Not directory: $dependencies_dir"
    exit 1
fi

grep "${keywords[@]}" -r "$dependencies_dir" | grep -v '(*)' | sed -e 's@^.*- @@g'  | sort -u
