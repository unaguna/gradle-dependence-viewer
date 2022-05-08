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
# Application name
GRADLE_DEPENDENCE_VIEWER_APP_NAME_SHORTAGE="gdv"
export GRADLE_DEPENDENCE_VIEWER_APP_NAME_SHORTAGE
readonly GRADLE_DEPENDENCE_VIEWER_APP_NAME_SHORTAGE


################################################################################
# Include
################################################################################

# shellcheck source=libs/files.sh
source "$SCRIPT_DIR/libs/files.sh"

# shellcheck source=libs/ana-gradle.sh
source "$SCRIPT_DIR/libs/ana-gradle.sh"


################################################################################
# Functions
################################################################################

function usage_exit () {
    echo "Usage:" "$(basename "$0") -d <output_directory> <main_project_directory>" 1>&2
    exit "$1"
}

function echo_version() {
    echo "$GRADLE_DEPENDENCE_VIEWER_APP_NAME $GRADLE_DEPENDENCE_VIEWER_VERSION"
}

function echo_help () {
    echo "$GRADLE_DEPENDENCE_VIEWER_APP_NAME $GRADLE_DEPENDENCE_VIEWER_VERSION"
    echo ""
    echo "Usage:" "$(basename "$0") -d <output_directory> <main_project_directory>"
    echo ""
    echo "Options"
    echo "    -d <output_directory> :"
    echo "         (Required) Path of the directory where the results will be output."
    echo ""
    echo "Arguments"
    echo "    <main_project_directory> :"
    echo "         (Required) Path of the root directory of the gradle project."
}

# Output an information
#
# Because stdout is used as output of gradle in this script,
# any messages should be output to stderr.
function echo_info () {
    echo "$SCRIPT_NAME: $*" >&2
}

# Output an error
#
# Because stdout is used as output of gradle in this script,
# any messages should be output to stderr.
function echo_err() {
    echo "$SCRIPT_NAME: $*" >&2
}

# Output the name of the file to be used as the output destination for stdout of gradle task.
#
# Arguments
#   $1 - sub-project name
#
# Standard Output
#   the filename, not filepath
function stdout_filename() {
    local -r project_name=$1

    local -r project_name_esc=${project_name//:/__}

    echo "${project_name_esc:-"root"}.txt"
}

# Check if the specified string is a name of sub-project
#
# Arguments
#   $1: a string
#   $2: the path of the project table
#
# Returns
#   Returns 0 if the specified string is a name of sub-project.
#   Returns 1 otherwise.
function is_sub_project () {
    local -r sub_project_name=${1#:}
    local -r project_list_path=$2

    # The root project is not sub-project
    if [ -z "$sub_project_name" ]; then
        return 1
    fi

    set +e
    awk '{print $1}' "$project_list_path" | grep -e "^:${sub_project_name}$" &> /dev/null
    result=$?
    set -e

    if [ $result -ne 0 ] && [ $result -ne 1 ]; then
        echo_err "Failed to reference the temporary file created: $project_list_path"
        exit $result
    fi

    return $result
}

################################################################################
# Constant values
################################################################################

readonly INIT_GRADLE="$SCRIPT_DIR/libs/init.gradle"


################################################################################
# Analyze arguments
################################################################################
declare -i argc=0
declare -a argv=()
output_dir_list=()
version_flg=1
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
                output_dir_list+=( "$2" )
                shift
            elif [[ "$1" == "--version" ]]; then
                version_flg=0
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

if [ "$version_flg" -eq 0 ]; then
    echo_version
    exit 0
fi

if [ "$invalid_option_flg" -eq 0 ]; then
    usage_exit 1
fi

if [ "$argc" -ne 1 ]; then
    usage_exit 1
fi

# (Required) The directory of main project, which contains build.gradle of root project.
readonly main_project_dir="${argv[0]}"

# (Required) Output destination directory path
# it must be given only once; no more once
if [ "${#output_dir_list[@]}" -ne 1 ] || [ -z "${output_dir_list[0]:-""}" ]; then
    usage_exit 1
else
    output_dir="${output_dir_list[0]}"
    output_dir=$(abspath "$ORIGINAL_PWD" "$output_dir")
    readonly output_dir
fi


################################################################################
# Validate arguments
################################################################################

# The given $main_project_dir must be a directory and must contain an executable gradlew.
if [ ! -e "$main_project_dir" ]; then
    echo_err "gradle project not found in '$main_project_dir': No such directory"
    exit 1
elif [ ! -d "$main_project_dir" ]; then
    echo_err "gradle project not found in '$main_project_dir': It is not directory"
    exit 1
elif [ ! -e "$main_project_dir/gradlew" ]; then
    echo_err "cannot find gradle wrapper '$main_project_dir/gradlew': No such file"
    exit 1
elif [ -d "$main_project_dir/gradlew" ]; then
    echo_err "cannot find gradle wrapper '$main_project_dir/gradlew': It is directory"
    exit 1
elif [ ! -x "$main_project_dir/gradlew" ] ; then
    echo_err "cannot find gradle wrapper '$main_project_dir/gradlew': Non-executable"
    exit 1
fi
readonly gradle_exe="./gradlew"

# The given $output_dir must be an empty directory or nonexistent.
if [ -e "$output_dir" ]; then
    if [ ! -d "$output_dir" ]; then
        echo_err "cannot create output directory '$output_dir': Non-directory file exists"
        exit 1
    elif [ -n "$(ls -A1 "$output_dir")" ]; then
        echo_err "cannot create output directory '$output_dir': Non-empty directory exists"
        exit 1
    fi
fi


################################################################################
# Temporally files
################################################################################

# All temporally files which should be deleted on exit
tmpfile_list=( )

function remove_tmpfile {
    set +e
    for tmpfile in "${tmpfile_list[@]}"
    do
        if [ -e "$tmpfile" ]; then
            rm -f "$tmpfile"
        fi
    done
    set -e
}
trap remove_tmpfile EXIT
trap 'trap - EXIT; remove_tmpfile; exit -1' INT PIPE TERM

# the output of `gradle projects`
tmp_project_list_path=$(mktemp)
readonly tmp_project_list_path
tmpfile_list+=( "$tmp_project_list_path" )

# the output of `gradle tasks`
tmp_tasks_path=$(mktemp)
readonly tmp_tasks_path
tmpfile_list+=( "$tmp_tasks_path" )


################################################################################
# main
################################################################################

cd "$main_project_dir"

readonly output_deps_dir="$output_dir/dependencies"
readonly app_version_path="$output_dir/$GRADLE_DEPENDENCE_VIEWER_APP_NAME_SHORTAGE-version.txt"
readonly gradle_version_path="$output_dir/gradle-version.txt"

# create the directory where output
if [ -n "$output_dir" ]; then
    # If output_dir already exists, it does not matter if it is empty, so use the -p option to avoid an error.
    mkdir -p "$output_dir"
fi
if [ -n "$output_deps_dir" ]; then
    mkdir "$output_deps_dir"
fi

# Output self version
echo_version > "$app_version_path"

# Get the gradle version
echo_info "Loading gradle"
"$gradle_exe" --version < /dev/null > "$gradle_version_path"

# Get sub-projects list
echo_info "Loading project list"
"$gradle_exe" projectlist --init-script "$INIT_GRADLE" "-Pjp.unaguna.prjoutput=$tmp_project_list_path" < /dev/null > /dev/null
sort "$tmp_project_list_path" -o "$tmp_project_list_path"

# get task list
echo_info "Loading task list"
"$gradle_exe" tasklist --init-script "$INIT_GRADLE" "-Pjp.unaguna.taskoutput=$tmp_tasks_path" < /dev/null > /dev/null

# get dependencies
echo_info "Loading dependencies"
"$gradle_exe" eachDependencies --init-script "$INIT_GRADLE" "-Pjp.unaguna.depsoutput=$output_deps_dir" < /dev/null > /dev/null
