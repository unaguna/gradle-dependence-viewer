#!/usr/bin/env bash


# Check task existence
#
# Arguments
#   $1 - A task name. It can start with ':', such as ":sub-project:test". 
#   $2 - the path of task list
#
# Returns
#   Returns 0 if specified task exists. Returns 1 otherwise.
function task_exists() {
    local -r task_name=${1#:}
    local -r task_list_path=$2

    set +e
    grep -e "^:$task_name$" "$task_list_path" &> /dev/null
    result=$?
    set -e

    if [ $result -ne 0 ] && [ $result -ne 1 ]; then
        echo_err "Failed to reference the temporary file created: $task_list_path"
        exit $result
    fi

    return $result
}

# Get build status from the stdout file
#
# Arguments
#   $1 - the path of output of gradle
#
# Returns
#   Returns 0 if the status is found. Returns 1 otherwise.
function build_status() {
    local -r stdout_path=$1
    
    set +e
    status=$(grep BUILD "$stdout_path" | tail -n 1 | awk '{print $2}')
    result=$?
    set -e

    if [ $result -ne 0 ] && [ $result -ne 1 ]; then
        echo_err "Failed to read the file: $task_list_path"
        exit $result
    fi

    echo "$status"
    return $result
}

# Get task status from the stdout file
#
# Arguments
#   $1 - A task name. It can start with ':', such as ":sub-project:test". 
#   $2 - the path of output of gradle
#
# Returns
#   Returns 0 if the status is found. Returns non-zero otherwise.
function task_status() {
    local -r task_name=${1#:}
    local -r stdout_path=$2
    
    set +e
    status=$(grep "> Task :$task_name " "$stdout_path" | head -n 1 | awk '{print $4}')
    result=$?
    set -e

    if [ $result -ne 0 ] && [ $result -ne 1 ]; then
        echo_err "Failed to read the file: $task_list_path"
        exit $result
    fi

    echo "$status"
    return 0
}
