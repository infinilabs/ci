#!/bin/bash

# update_yaml_version
# Arguments:
#   $1: file path (relative to current dir)
#   $2: key name (e.g., PUBLISH_VERSION)
#   $3: new value
update_yaml_version() {
    local file="$1"
    local key="$2"
    local new_val="$3"

    if [ ! -f "$file" ]; then
        echo "Warning: File '$file' not found at $(pwd), skipping."
        return 0
    fi

    echo "Updating yaml: '$file' '$key' value to '$new_val'"
    
    # Use sed to update the YAML file
    sed -i "/^\s*${key}:/,/default:/ s/default: .*/default: \"${new_val}\"/" "$file"
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
