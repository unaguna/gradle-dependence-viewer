#!/usr/bin/env bash


# Get absolute path
#
# Arguments
#   $1 - base path
#   $2 - relative path
#
# Standard Output
#   the absolute path
function abspath() {
    local -r base_path=$1
    local -r relative_path=$2

    abs_dir=$(cd "$base_path" && cd "$(dirname "$relative_path")" && pwd)
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        return $exit_code
    fi

    filename=$(basename "$relative_path")

    echo "$abs_dir/$filename"
}
