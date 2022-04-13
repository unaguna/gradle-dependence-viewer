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
    echo "Usage:" "$(basename "$0") -d <output_directory> <main_project_directory>" 1>&2
    exit "$1"
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
output_dir=
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
                output_dir="$2"
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

# (Required) The directory of main project, which contains build.gradle of root project.
readonly main_project_dir="${argv[0]}"

# (Required) Output destination directory path
if [ -n "${output_dir:-""}" ]; then
    output_dir=$(cd "$ORIGINAL_PWD"; cd "$(dirname "$output_dir")"; pwd)"/"$(basename "$output_dir")
    readonly output_dir
else
    usage_exit 1
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

# create the directory where output
if [ -n "$output_dir" ]; then
    mkdir -p "$output_dir"
fi

# Get sub-projects list
echo_info "Loading project list"
./gradlew projectlist --init-script "$INIT_GRADLE" "-Pjp.unaguna.prjoutput=$tmp_project_list_path" < /dev/null > /dev/null
sort "$tmp_project_list_path" -o "$tmp_project_list_path"

# get task list
echo_info "Loading task list"
./gradlew tasks --all < /dev/null | awk -F ' ' '{print $1}' >> "$tmp_tasks_path"

# Read each build.gradle and run each :dependencies.
while read -r project_row; do
    project_name=$(awk '{print $1}' <<< "$project_row")
    if [ "$project_name" == ":" ]; then
        project_name=""
    fi
    task_name="${project_name}:dependencies"

    # Even if the build.gradle file exists, 
    # ignore it if the dependencies task of this module does not exists
    if ! task_exists "$task_name" "$tmp_tasks_path"; then
        if [ -z "$project_name" ]; then
            echo_info "'$task_name' is skipped; the root project doesn't have a task 'dependencies'."
        else
            echo_info "'$task_name' is skipped; the project '$project_name' doesn't have a task 'dependencies'."
        fi
        continue
    fi

    # Decide filepath where output.
    output_file="$output_dir/$(stdout_filename "$project_name")"

    echo_info "Running '$task_name'" 
    set +e
    # To solve the below problem, specify the redirect /dev/null to stdin:
    # https://ja.stackoverflow.com/questions/30942/シェルスクリプト内でgradleを呼ぶとそれ以降の処理がなされない
    ./gradlew "$task_name" < /dev/null &> "$output_file"
    set -e
done < "$tmp_project_list_path"
