#!/bin/bash
# claude-display statusline script
#
# Reads the summary file and session metadata to build a compact statusline.
# Configure in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "~/.claude/display/statusline.sh" }
#
# Or reference from the plugin install path:
#   "statusLine": { "type": "command", "command": "<plugin-path>/hooks/statusline.sh" }

set -euo pipefail

SUMMARY_FILE="$HOME/.claude/display/summary.txt"

INPUT=$(cat)
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // empty' 2>/dev/null)
COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
CTX=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)

PARTS=()

[[ -n "$MODEL" ]] && PARTS+=("$MODEL")
[[ -n "$COST" && "$COST" != "0" ]] && PARTS+=("\$${COST}")
[[ -n "$CTX" && "$CTX" != "null" ]] && PARTS+=("ctx:${CTX}%")

if [[ -f "$SUMMARY_FILE" ]]; then
  SUMMARY=$(cat "$SUMMARY_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g;s/^ //;s/ $//')
  [[ -n "$SUMMARY" ]] && PARTS+=("| $SUMMARY")
fi

echo "${PARTS[*]}"
