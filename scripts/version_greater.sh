#!/bin/bash

version_greater() {
    # $1: version1 (e.g., x.y.z)
    # $2: version2 (e.g., a.b.c)
    # Returns 0 if version1 > version2, 1 otherwise.

    IFS='.' read -r -a v1_parts <<< "$1"
    IFS='.' read -r -a v2_parts <<< "$2"

    for i in "${!v1_parts[@]}"; do
        if [[ -z "${v2_parts[$i]}" ]]; then
            return 0 # version1 has more parts, so it's considered greater
        fi

        local part1_val=${v1_parts[$i]}
        local part2_val=${v2_parts[$i]}

        if [[ "$part1_val" -gt "$part2_val" ]]; then
            return 0 # version1 is greater
        fi
        if [[ "$part1_val" -lt "$part2_val" ]]; then
            return 1 # version1 is smaller
        fi
    done

    if [[ "${#v1_parts[@]}" -lt "${#v2_parts[@]}" ]]; then
        return 1 # version1 is smaller (e.g., 1.2 vs 1.2.3)
    fi

    return 1
}