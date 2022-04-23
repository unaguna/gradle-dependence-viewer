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

# Readlink recursively
# 
# This can be achieved with `readlink -f` in the GNU command environment,
# but we implement it independently for mac support.
#
# Arguments
#   $1 - target path
#
# Standard Output
#   the absolute real path
function itr_readlink() {
    local target_path=$1

    (
        cd "$(dirname "$target_path")"
        target_path=$(basename "$target_path")

        # Iterate down a (possible) chain of symlinks
        while [ -L "$target_path" ]
        do
            target_path=$(readlink "$target_path")
            cd "$(dirname "$target_path")"
            target_path=$(basename "$target_path")
        done

        echo "$(pwd -P)/$target_path"
    )
}

# The current directory when this script started.
ORIGINAL_PWD=$(pwd)
readonly ORIGINAL_PWD
# The path of this script file
SCRIPT_PATH=$(itr_readlink "$0")
readonly SCRIPT_PATH
# The directory path of this script file
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")"; pwd)
readonly SCRIPT_DIR
# The path of this script file
SCRIPT_NAME=$(basename "$SCRIPT_PATH")
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
    echo "Usage:" "$(basename "$0") -d <dependencies_directory> <keywords> [...]" 1>&2
    exit "$1"
}

function echo_help () {
    echo "$GRADLE_DEPENDENCE_VIEWER_APP_NAME $GRADLE_DEPENDENCE_VIEWER_VERSION"
    echo ""
    echo "Usage:" "$(basename "$0") -d <dependencies_directory> <keywords> [...]"
    echo ""
    echo "Options"
    echo "    -d <dependencies_directory> :"
    echo "         (Required) Path of the directory where the dependence trees have been output."
    echo ""
    echo "Arguments"
    echo "    <keywords> [...] :"
    echo "         (Required) The keywords which you are looking for. If more than one is"
    echo "         specified, dependencies containing one or more of them is extracted."
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
dependencies_dir_list=()
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
                dependencies_dir_list+=( "$2" )
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

if [ "$argc" -lt 1 ]; then
    usage_exit 1
fi

# (Required) destination directory path
# it must be given only once; no more once
if [ "${#dependencies_dir_list[@]}" -ne 1 ] || [ -z "${dependencies_dir_list[0]:-""}" ]; then
    usage_exit 1
else
    dependencies_dir="${dependencies_dir_list[0]}"
    dependencies_dir=$(cd "$ORIGINAL_PWD"; cd "$(dirname "$dependencies_dir")"; pwd)"/"$(basename "$dependencies_dir")
    readonly dependencies_dir
fi


################################################################################
# Validate arguments
################################################################################

if [ ! -d "$dependencies_dir" ]; then
    echo_err "Not directory: $dependencies_dir"
    exit 1
fi


################################################################################
# main
################################################################################

grep "${keywords[@]}" -r "$dependencies_dir" | grep -v '(*)' | sed -e 's@^.*- @@g'  | sort -u
