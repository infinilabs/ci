#!/bin/bash

# update_yaml_version
# Arguments:
#   $1: file name (e.g., publish-docker.yml)
#   $2: key name (e.g., PUBLISH_VERSION)
#   $3: new value
# Note: must be called from the directory containing the yml file
update_yaml_version() {
    local file="$1"
    local key="$2"
    local new_val="$3"

    if [ ! -f "$file" ]; then
        echo "Warning: File '$file' not found at $(pwd), skipping."
        return 0
    fi

    echo "Updating yaml: '$file' '$key' value to '$new_val'"

    local line_num
    line_num=$(awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
            match($0, /^[[:space:]]*/); key_indent = RLENGTH
            in_block = 1
            next
        }
        in_block && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/ {
            match($0, /^[[:space:]]*/); cur_indent = RLENGTH
            if (cur_indent <= key_indent) {
                in_block = 0
            }
        }
        in_block && /^[[:space:]]*default[[:space:]]*:/ {
            print NR
            exit
        }
    ' "$file")

    if [ -z "$line_num" ]; then
        echo "Warning: key '$key' or its default not found in '$file'"
        return 0
    fi

    echo "Found default at line $line_num, replacing..."
    sed -i "${line_num}s/default:.*/default: \"${new_val}\"/" "$file"
}

# update_json_version
# Arguments:
#   $1: file path (relative to current dir)
#   $2: key name (e.g., version)
#   $3: new value
update_json_version() {
    local file="$1"
    local key="$2"
    local new_val="$3"

    if [ ! -f "$file" ]; then
        echo "Warning: File '$file' not found at $(pwd), skipping."
        return 0
    fi

    echo "Updating JSON: '$file' '$key' value to '$new_val'"

    if command -v jq >/dev/null 2>&1; then
        jq --arg v "$new_val" ".${key} = \$v" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    else
        sed -i "s/\"${key}\": *\"[^\"]*\"/\"${key}\": \"${new_val}\"/" "$file"
    fi
}