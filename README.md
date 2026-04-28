# Claude Code Custom Statusline

A custom statusline script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays real-time session information including plan quota usage, context window consumption, and git branch -- all color-coded for quick visual feedback.

## Screenshot

```
Claude Opus 4.6 (Max) | 5h quota: 34% | Reset: 3h 12m | 7d quota: 8% | Context: [████░░░░░░░░░░░░░░░░] 22.1% | 44.2K/200K | main | my-project
```

## What It Shows

| Segment | Description |
|---------|-------------|
| **Model name** | Current Claude model (e.g. `Claude Opus 4.6`) with `(Max)` suffix when on a Claude Max subscription |
| **5h quota** | Percentage of your 5-hour rate limit consumed (from `rate_limits.five_hour.used_percentage`) |
| **Reset timer** | Time until your 5-hour quota resets, calculated from the `resets_at` epoch provided by the API |
| **7d quota** | Percentage of your 7-day rate limit consumed (from `rate_limits.seven_day.used_percentage`) |
| **Context bar** | Visual progress bar (20 chars wide) showing context window usage |
| **Context %** | Numeric percentage of context window used |
| **Tokens** | Token count (e.g. `44.2K/200K`) derived from usage percentage and context window size |
| **Git branch** | Current git branch name (if in a git repo) |
| **Project name** | Directory name of the current workspace |

## Color Coding

All percentage-based segments use a traffic-light color scheme:

- **Green** -- under 50%
- **Yellow** -- 50% to 80%
- **Red** -- over 80%

This applies to the 5-hour quota, 7-day quota, and context window bar.

## Installation

### 1. Copy the script

```bash
mkdir -p ~/.claude
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

### 2. Configure Claude Code

Add to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

Or if you already have a `settings.json`, add the `statusLine` key to it.

### 3. Dependencies

- **jq** -- used to parse the JSON input from Claude Code
- **bc** -- used for floating-point arithmetic
- **git** -- for branch detection (optional)

On macOS: `brew install jq` (bc and git are pre-installed).

On Ubuntu/Debian: `sudo apt install jq bc git`.

## How It Works

Claude Code pipes a JSON object to the statusline command on each render. The JSON includes:

- `model.display_name` -- the active model
- `context_window.used_percentage` / `context_window.context_window_size` -- context usage
- `rate_limits.five_hour.used_percentage` / `rate_limits.five_hour.resets_at` -- 5-hour quota
- `rate_limits.seven_day.used_percentage` / `rate_limits.seven_day.resets_at` -- 7-day quota
- `workspace.current_dir` -- working directory

The script reads this JSON via stdin, extracts the fields with `jq`, computes derived values (token counts, reset timers, progress bars), and outputs a single ANSI-colored line.

### Reset Timer

The reset timer prefers the exact `resets_at` epoch from the API when available. If rate limit data hasn't been sent yet (e.g. before the first API call in a session), it falls back to a clock-based estimate using 5-hour blocks.

### Plan Detection

When `rate_limits` data is present in the JSON, the script adds a `(Max)` label to the model name, indicating a Claude Max subscription. The API does not expose which tier (5x vs 20x) you are on, so the label is the same for both.

## Customization

The script is plain bash -- edit it to suit your needs. Common tweaks:

- Change the progress bar width by modifying `bar_width=20`
- Adjust color thresholds (the `50` / `80` checks)
- Reorder or remove segments
- Change the separator character in the `sep` variable

## License

MIT
