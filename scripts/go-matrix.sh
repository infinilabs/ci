#!/bin/bash
# go-matrix.sh - Generate GitHub Actions matrix

matrix_includes=()

# default to false, only include products explicitly set to true if using workflow_dispatch
AGENT_PUBLISH=${AGENT_PUBLISH:-false}
CONSOLE_PUBLISH=${CONSOLE_PUBLISH:-false}
GATEWAY_PUBLISH=${GATEWAY_PUBLISH:-false}
LOADGEN_PUBLISH=${LOADGEN_PUBLISH:-false}
FRAMEWORK_PUBLISH=${FRAMEWORK_PUBLISH:-false}
EASYSEARCH_PUBLISH=${EASYSEARCH_PUBLISH:-false}
COCO_APP_PUBLISH=${COCO_APP_PUBLISH:-false}
COCO_SERVER_PUBLISH=${COCO_SERVER_PUBLISH:-false}

AGENT_PUBLISH_VERSION=${AGENT_PUBLISH_VERSION:-""}
CONSOLE_PUBLISH_VERSION=${CONSOLE_PUBLISH_VERSION:-""}
GATEWAY_PUBLISH_VERSION=${GATEWAY_PUBLISH_VERSION:-""}
LOADGEN_PUBLISH_VERSION=${LOADGEN_PUBLISH_VERSION:-""}
FRAMEWORK_PUBLISH_VERSION=${FRAMEWORK_PUBLISH_VERSION:-""}
EASYSEARCH_PUBLISH_VERSION=${EASYSEARCH_PUBLISH_VERSION:-""}
COCO_APP_PUBLISH_VERSION=${COCO_APP_PUBLISH_VERSION:-""}
COCO_SERVER_PUBLISH_VERSION=${COCO_SERVER_PUBLISH_VERSION:-""}

# if use workflow_dispatch, only include products explicitly set to true
if [[ "$GITHUB_EVENT_NAME" != "workflow_dispatch" ]]; then
    AGENT_PUBLISH=true
    CONSOLE_PUBLISH=true
    GATEWAY_PUBLISH=true
    LOADGEN_PUBLISH=true
fi

# generate matrix
[[ "$AGENT_PUBLISH" == "true" ]] && matrix_includes+=("{\"product\":\"agent\",\"publish_version\":\"${AGENT_PUBLISH_VERSION}\"}")
[[ "$CONSOLE_PUBLISH" == "true" ]] && matrix_includes+=("{\"product\":\"console\",\"publish_version\":\"${CONSOLE_PUBLISH_VERSION}\"}")
[[ "$GATEWAY_PUBLISH" == "true" ]] && matrix_includes+=("{\"product\":\"gateway\",\"publish_version\":\"${GATEWAY_PUBLISH_VERSION}\"}")
[[ "$LOADGEN_PUBLISH" == "true" ]] && matrix_includes+=("{\"product\":\"loadgen\",\"publish_version\":\"${LOADGEN_PUBLISH_VERSION}\"}")
[[ "$FRAMEWORK_PUBLISH" == "true" ]] && matrix_includes+=("{\"product\":\"framework\",\"publish_version\":\"${FRAMEWORK_PUBLISH_VERSION}\"}")
[[ "$EASYSEARCH_PUBLISH" == "true" ]] && matrix_includes+=("{\"product\":\"easysearch\",\"publish_version\":\"${EASYSEARCH_PUBLISH_VERSION}\"}")
[[ "$COCO_APP_PUBLISH" == "true" ]] && matrix_includes+=("{\"product\":\"coco-app\",\"publish_version\":\"${COCO_APP_PUBLISH_VERSION}\"}")
[[ "$COCO_SERVER_PUBLISH" == "true" ]] && matrix_includes+=("{\"product\":\"coco-server\",\"publish_version\":\"${COCO_SERVER_PUBLISH_VERSION}\"}")

# output JSON array, ensure commas are correct
# handle potential spaces between matrix_includes[*] causing invalid JSON
matrix_json="["
for i in "${!matrix_includes[@]}"; do
    matrix_json+="${matrix_includes[$i]}"
    if [[ $i -lt $((${#matrix_includes[@]} - 1)) ]]; then
        matrix_json+=","
    fi
done
matrix_json+="]"

echo "matrix=$matrix_json"