#!/bin/bash
# claude-conversation-summary: Stop + SessionEnd hook
#
# On Stop: every N assistant messages, summarizes the conversation via
# `claude -p --model haiku` and writes it to ~/.claude/display/summary.txt
# for your statusline to read.
#
# On SessionEnd (--final): writes final summary then exits.

set -euo pipefail

DISPLAY_DIR="$HOME/.claude/display"
SUMMARY_FILE="$DISPLAY_DIR/summary.txt"
STATE_FILE="$DISPLAY_DIR/state.json"
LOCK_FILE="$DISPLAY_DIR/.lock"
LOG_FILE="$DISPLAY_DIR/hook.log"

INTERVAL="${CLAUDE_DISPLAY_INTERVAL:-10}"
MAX_CHARS="${CLAUDE_DISPLAY_MAX_CHARS:-4000}"
MAX_BLOCK_CHARS=500

mkdir -p "$DISPLAY_DIR"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG_FILE"
}

# Read hook payload from stdin
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [[ -z "$SESSION_ID" || -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

IS_FINAL=false
if [[ "${1:-}" == "--final" ]]; then
  IS_FINAL=true
fi

# Count real user messages (not tool results or system messages)
count_user_messages() {
  python3 -c "
import json, sys
count = 0
with open(sys.argv[1], 'r') as f:
    for line in f:
        try:
            entry = json.loads(line)
            if entry.get('type') != 'user':
                continue
            content = entry.get('message', {}).get('content', '')
            if isinstance(content, str) and content.strip():
                count += 1
            elif isinstance(content, list):
                has_text = any(b.get('type') == 'text' and b.get('text', '').strip() for b in content)
                all_tool = all(b.get('type') == 'tool_result' for b in content)
                if has_text and not all_tool:
                    count += 1
        except:
            pass
print(count)
" "$1"
}

# Extract conversation text for summarization
build_conversation() {
  local transcript="$1"
  local skip="${2:-0}"
  local max_chars="$3"
  local block_chars="$4"

  python3 -c "
import json, sys

transcript = sys.argv[1]
skip = int(sys.argv[2])
max_chars = int(sys.argv[3])
block_chars = int(sys.argv[4])

parts = []
total = 0
user_seen = 0
capturing = (skip == 0)

with open(transcript, 'r') as f:
    for line in f:
        if total >= max_chars:
            break
        try:
            entry = json.loads(line)
        except:
            continue
        etype = entry.get('type')
        if etype not in ('user', 'assistant'):
            continue

        # Extract text content
        msg = entry.get('message', {})
        content = msg.get('content', '')
        if isinstance(content, str):
            text = content.strip()
        elif isinstance(content, list):
            text = ' '.join(b.get('text', '') for b in content if b.get('type') == 'text').strip()
        else:
            continue
        if not text:
            continue

        # Skip logic for delta analysis
        if etype == 'user':
            is_real = True
            raw = msg.get('content', '')
            if isinstance(raw, list) and all(b.get('type') == 'tool_result' for b in raw):
                is_real = False
            if is_real:
                user_seen += 1
                if not capturing and user_seen > skip:
                    capturing = True
        if not capturing:
            continue

        role = 'USER' if etype == 'user' else 'CLAUDE'
        if role == 'CLAUDE' and len(text) > block_chars:
            text = text[:block_chars] + '...'

        chunk = f'[{role}]: {text}\n'
        if total + len(chunk) > max_chars:
            chunk = chunk[:max_chars - total] + '...'
        parts.append(chunk)
        total += len(chunk)

print(''.join(parts))
" "$transcript" "$skip" "$max_chars" "$block_chars"
}

# Read saved state for this session
get_last_analyzed() {
  if [[ -f "$STATE_FILE" ]]; then
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        state = json.load(f)
    if state.get('session_id') == sys.argv[2]:
        print(state.get('last_analyzed', 0))
    else:
        print(0)
except:
    print(0)
" "$STATE_FILE" "$SESSION_ID"
  else
    echo "0"
  fi
}

save_state() {
  local analyzed="$1"
  python3 -c "
import json, sys
state = {'session_id': sys.argv[1], 'last_analyzed': int(sys.argv[2])}
with open(sys.argv[3], 'w') as f:
    json.dump(state, f)
" "$SESSION_ID" "$analyzed" "$STATE_FILE"
}

# Summarize via claude CLI (no API key needed)
call_claude() {
  local prompt="$1"
  echo "$prompt" | claude -p --model haiku --no-session-persistence 2>/dev/null
}

# --- Main logic ---

MSG_COUNT=$(count_user_messages "$TRANSCRIPT_PATH")
LAST_ANALYZED=$(get_last_analyzed)

# Detect transcript reset (/clear)
if (( LAST_ANALYZED > 0 && MSG_COUNT < LAST_ANALYZED )); then
  LAST_ANALYZED=0
  save_state 0
fi

# Decide whether to run
if [[ "$IS_FINAL" == "true" ]]; then
  # Always summarize on session end if there are messages
  if (( MSG_COUNT == 0 )); then
    exit 0
  fi
elif (( LAST_ANALYZED == 0 )); then
  # First analysis after 1 message
  if (( MSG_COUNT < 1 )); then
    exit 0
  fi
else
  # Subsequent: every INTERVAL messages
  if (( MSG_COUNT / INTERVAL <= LAST_ANALYZED / INTERVAL )); then
    exit 0
  fi
fi

# Prevent concurrent runs
if [[ -f "$LOCK_FILE" ]]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
  if (( LOCK_AGE < 90 )); then
    exit 0
  fi
  rm -f "$LOCK_FILE"
fi
trap 'rm -f "$LOCK_FILE"' EXIT
touch "$LOCK_FILE"

log "Summarizing session $SESSION_ID (msgs: $MSG_COUNT, last: $LAST_ANALYZED, final: $IS_FINAL)"

# Build conversation text (delta if not first analysis)
SKIP=0
if (( LAST_ANALYZED > 0 )); then
  SKIP=$LAST_ANALYZED
fi
CONVERSATION=$(build_conversation "$TRANSCRIPT_PATH" "$SKIP" "$MAX_CHARS" "$MAX_BLOCK_CHARS")

if [[ -z "$CONVERSATION" ]]; then
  log "No conversation content to summarize"
  exit 0
fi

PROMPT="Summarize this Claude Code conversation in ONE short line (under 100 characters). Focus on the current task or goal. No preamble — just the summary.

${CONVERSATION}"

SUMMARY=$(call_claude "$PROMPT" || true)

if [[ -n "$SUMMARY" ]]; then
  # Clean up: strip quotes, trim whitespace, truncate
  SUMMARY=$(echo "$SUMMARY" | tr '\n' ' ' | sed 's/^[[:space:]"]*//;s/[[:space:]"]*$//' | head -c 120)
  echo "$SUMMARY" > "$SUMMARY_FILE"
  save_state "$MSG_COUNT"
  log "Summary updated: $SUMMARY"
  >&2 echo "claude-conversation-summary: $SUMMARY"
else
  log "No summary returned from claude CLI"
fi
