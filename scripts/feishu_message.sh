#!/bin/bash

# --- Script to send success/failure notification to Feishu ---

set -euo pipefail

# Check required environment variables
if [[ -z "${FEISHU_BOT_URL:-}" ]]; then
  echo "Error: FEISHU_BOT_URL environment variable is not set."
  exit 1
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

# Get status from env (default to 'failure' for backward compatibility)
STATUS="${STATUS:-failure}"  # should be 'success' or 'failure'

# --- Gather info from GitHub Actions environment ---
REPO_NAME="${REPO_NAME:-unknown repo}"
WORKFLOW_NAME="${WORKFLOW_NAME:-unknown workflow}"
RUN_ID="${RUN_ID:-unknown run}"
ACTOR="${ACTOR:-unknown actor}"
SERVER_URL="${SERVER_URL:-https://github.com}"
RUN_URL="${SERVER_URL}/${REPO_NAME}/actions/runs/${RUN_ID}"

# --- Set message content based on status ---
if [[ "$STATUS" == "success" ]]; then
  COLOR="green"
  EMOJI="✅"
  TITLE="Workflow Succeeded: ${WORKFLOW_NAME}"
  MESSAGE_MARKDOWN=$(printf "**Triggered by:** *%s* \n\n The workflow completed successfully." "${ACTOR}")
else
  COLOR="red"
  EMOJI="🚨"
  TITLE="Workflow Failed: ${WORKFLOW_NAME}"
  MESSAGE_MARKDOWN=$(printf "**Triggered by:** *%s* \n\n Please investigate the failed job(s)." "${ACTOR}")
fi

# --- Create temp JSON file safely ---
TMP_JSON_FILE=$(mktemp)
trap 'rm -f "$TMP_JSON_FILE"' EXIT

# --- Build Feishu interactive card using jq ---
jq -n \
  --arg color "$COLOR" \
  --arg emoji "$EMOJI" \
  --arg title "$TITLE" \
  --arg message "$MESSAGE_MARKDOWN" \
  --arg url "$RUN_URL" \
  '{
    msg_type: "interactive",
    card: {
      config: {
        wide_screen_mode: true
      },
      header: {
        template: $color,
        title: {
          tag: "plain_text",
          content: ($emoji + " " + $title)
        }
      },
      elements: [
        {
          tag: "markdown",
          content: $message
        },
        {
          tag: "action",
          actions: [
            {
              tag: "button",
              text: {
                tag: "plain_text",
                content: "🔗 View Run Details"
              },
              url: $url,
              type: "default"
            }
          ]
        }
      ]
    }
  }' > "$TMP_JSON_FILE"

# --- Send notification ---
echo "Sending Feishu $STATUS notification..."
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H 'Content-Type: application/json' \
     --data "@${TMP_JSON_FILE}" \
     "${FEISHU_BOT_URL}")

# Check response code
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✅ Feishu $STATUS notification sent."
else
  echo "⚠️ Warning: Failed to send Feishu notification. HTTP Code: $HTTP_CODE"
fi

exit 0