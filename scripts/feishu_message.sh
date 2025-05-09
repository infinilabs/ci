#!/bin/bash

# --- Script to send a failure notification to Feishu ---

# Check if Webhook URL is provided
if [[ -z "${FEISHU_BOT_URL}" ]]; then
  echo "Error: FEISHU_BOT_URL environment variable is not set."
  exit 1
fi

# --- Gather information from environment variables (passed by GitHub Action) ---
REPO_NAME="${REPO_NAME:-unknown repo}"
WORKFLOW_NAME="${WORKFLOW_NAME:-unknown workflow}"
RUN_ID="${RUN_ID:-unknown run}"
ACTOR="${ACTOR:-unknown actor}"
RUN_URL="${SERVER_URL:-https://github.com}/${REPO_NAME}/actions/runs/${RUN_ID}"

# --- Customize Markdown Content ---
# Remember to include any keywords your Feishu bot requires! e.g., "Failure Alert"
# Using printf for better handling of potential special characters in variables
MESSAGE_MARKDOWN=$(printf "**Triggered by:** *%s*, Please investigate the failed job(s)." "${ACTOR}")

# --- Create a temporary file for the JSON payload ---
# Using mktemp for safer temporary file handling
TMP_JSON_FILE=$(mktemp)
# Ensure cleanup on exit
trap 'rm -f "$TMP_JSON_FILE"' EXIT

# --- Construct Feishu Interactive Card JSON ---
# Using heredoc to write to the temporary file
cat <<EOF > "$TMP_JSON_FILE"
{
  "msg_type": "interactive",
  "card": {
    "config": {
      "wide_screen_mode": true
    },
    "header": {
      "template": "red",
      "title": {
        "tag": "plain_text",
        "content": "🚨 Workflow Failure: ${WORKFLOW_NAME}"
      }
    },
    "elements": [
      {
        "tag": "markdown",
        "content": "${MESSAGE_MARKDOWN}"
      },
      {
        "tag": "action",
        "actions": [
          {
            "tag": "button",
            "text": {
              "tag": "plain_text",
              "content": "🔗 View Run Details"
            },
            "url": "${RUN_URL}",
            "type": "default"
          }
        ]
      }
    ]
  }
}
EOF

# --- Send the notification ---
echo "Sending Feishu notification..."
curl -sL -X POST -H 'Content-Type: application/json' \
     --data "@${TMP_JSON_FILE}" \
     "${FEISHU_BOT_URL}"

# --- Check curl exit status ---
CURL_EXIT_CODE=$?
if [ ${CURL_EXIT_CODE} -ne 0 ]; then
  echo "Error: curl command failed with exit code ${CURL_EXIT_CODE}"
else
  echo "Feishu notification sent successfully."
fi

exit 0