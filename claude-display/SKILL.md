---
name: claude-display
description: Use when the user asks about the current conversation summary, statusline display, or wants to check/update what the statusline is showing. Also use when troubleshooting the summary hook or statusline configuration.
---

# Claude Display

## Overview

Claude Display is a plugin that shows a live conversation summary in the Claude Code statusline. It uses a Stop hook to periodically summarize the session via Haiku and writes the result to `~/.claude/display/summary.txt`.

## When to Use

When the user asks about:
- What their statusline is showing
- The current conversation summary
- Troubleshooting the summary hook or statusline
- Configuring the update interval or display

## How It Works

1. A **Stop hook** fires after each Claude turn
2. Every N user messages (default: 10), it extracts the conversation from the JSONL transcript
3. It calls `claude -p --model haiku` to generate a one-line summary
4. The summary is written to `~/.claude/display/summary.txt`
5. A **statusline script** reads that file and displays it alongside model/cost/context info

## Key Files

- `~/.claude/display/summary.txt` - Current conversation summary
- `~/.claude/display/state.json` - Tracks message count per session
- `~/.claude/display/hook.log` - Debug log for the hook

## Configuration

Environment variables:
- `CLAUDE_DISPLAY_INTERVAL` (default: 10) - Summarize every N user messages
- `CLAUDE_DISPLAY_MAX_CHARS` (default: 4000) - Max conversation chars sent to Haiku

## Statusline Setup

The plugin installs the hooks automatically. To display the summary in the statusline, the user must add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "cat ~/.claude/display/summary.txt 2>/dev/null || echo 'No summary yet'"
  }
}
```

Or for the full statusline with model/cost/context:
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <plugin-path>/hooks/statusline.sh"
  }
}
```

## Troubleshooting

- Check `~/.claude/display/hook.log` for errors
- Run `cat ~/.claude/display/summary.txt` to see the current summary
- The hook requires `claude` CLI, `python3`, and `jq` to be available
- First summary appears after the first user message
