# claude-display

A Claude Code plugin that shows a **live conversation summary** in your statusline.

Instead of guessing what a long session is about, glance at the status bar and see: `Opus $0.42 ctx:15% | Building IVR risk-tier routing logic`

## How it works

1. A **Stop hook** fires after each Claude turn
2. Every 10 user messages, it extracts the conversation from the JSONL transcript
3. Calls `claude -p --model haiku` to generate a one-line summary (no API key needed)
4. Writes the summary to `~/.claude/display/summary.txt`
5. Your **statusline** reads that file

## Install

```bash
# Add the marketplace
/plugin marketplace add khandy-lively/claude-display

# Install the plugin
/plugin install claude-display@claude-display
```

Then configure the statusline in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "cat ~/.claude/display/summary.txt 2>/dev/null || echo ''"
  }
}
```

Or use the included statusline script that also shows model, cost, and context usage (replace `<path>` with your plugin install path from `/plugin` output):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <path>/hooks/statusline.sh"
  }
}
```

## Configuration

Set environment variables in your shell profile:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_DISPLAY_INTERVAL` | `10` | Summarize every N user messages |
| `CLAUDE_DISPLAY_MAX_CHARS` | `4000` | Max conversation chars sent for summarization |

## Requirements

- `claude` CLI (used to call Haiku for summarization)
- `python3` (transcript parsing)
- `jq` (hook input parsing)

## Files written

```
~/.claude/display/summary.txt   # Current one-line summary
~/.claude/display/state.json    # Message counter per session
~/.claude/display/hook.log      # Debug log
```

## Cost

Uses Haiku via `claude -p` (counts against your normal Claude usage, not a separate API key). Each summary call processes ~4KB of conversation text. With the default interval of every 10 messages, a 100-message session triggers ~10 summaries.

## License

MIT
