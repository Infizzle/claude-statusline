#!/bin/bash
# Claude Code custom status line
input=$(cat)

# Extract data from JSON input
model=$(echo "$input" | jq -r '.model.display_name')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
project_name=$(basename "$cwd")
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

# Extract real plan quota usage from rate_limits (Claude.ai subscription data)
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_resets_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Determine plan tier from context window size: 200K = standard/Pro, 100K = legacy
# Claude Max 5x and 20x both use the same context window, so we label based on what's observable.
# If rate_limits are present, it means the user is on a Claude.ai subscription (Max plan).
# The 5-hour reset window distinguishes Max 5x (~5x usage cap) vs Max 20x (~20x usage cap).
# Since the exact multiplier isn't in the JSON, we show "Max" when rate_limits are present.
if [ -n "$five_hour_pct" ] || [ -n "$seven_day_pct" ]; then
    plan_label="Max"
else
    plan_label=""
fi

# Calculate time until 5-hour reset using the actual resets_at epoch from rate_limits
if [ -n "$five_hour_resets_at" ]; then
    now_epoch=$(date +%s)
    secs_until=$((five_hour_resets_at - now_epoch))
    if [ "$secs_until" -lt 0 ]; then secs_until=0; fi
    hours_until=$((secs_until / 3600))
    mins_until=$(((secs_until % 3600) / 60))
elif [ -n "$seven_day_resets_at" ]; then
    now_epoch=$(date +%s)
    secs_until=$((seven_day_resets_at - now_epoch))
    if [ "$secs_until" -lt 0 ]; then secs_until=0; fi
    hours_until=$((secs_until / 3600))
    mins_until=$(((secs_until % 3600) / 60))
else
    # Fallback: calculate from clock using 5-hour blocks
    current_hour=$(date +%H)
    current_min=$(date +%M)
    current_total_min=$((current_hour * 60 + current_min))
    block_start=$((current_hour / 5 * 5))
    next_reset_hour=$(((block_start + 5) % 24))
    reset_min=0
    if [ $next_reset_hour -gt $current_hour ] || ([ $next_reset_hour -eq $current_hour ] && [ $reset_min -gt $current_min ]); then
        next_reset_total_min=$((next_reset_hour * 60 + reset_min))
    else
        next_reset_total_min=$(((next_reset_hour + 24) * 60 + reset_min))
    fi
    min_until_reset=$((next_reset_total_min - current_total_min))
    if [ $min_until_reset -lt 0 ]; then min_until_reset=$((min_until_reset + 1440)); fi
    hours_until=$((min_until_reset / 60))
    mins_until=$((min_until_reset % 60))
fi

# Get git branch (skip locks for performance)
git_branch=""
if [ -d "$cwd/.git" ]; then
    git_branch=$(cd "$cwd" && git -c core.filemode=false branch --show-current 2>/dev/null || echo "")
fi

# Determine color based on context usage: green < 50%, yellow 50-80%, red > 80%
used_int=$(printf "%.0f" "$used_pct")
if [ "$used_int" -ge 80 ]; then
    bar_color="\033[31m"  # red
elif [ "$used_int" -ge 50 ]; then
    bar_color="\033[33m"  # yellow
else
    bar_color="\033[32m"  # green
fi

# Create progress bar (20 characters wide)
bar_width=20
filled=$(printf "%.0f" $(echo "$used_pct * $bar_width / 100" | bc -l 2>/dev/null || echo "0"))
[ "$filled" -gt "$bar_width" ] && filled=$bar_width
[ "$filled" -lt 0 ] && filled=0

bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=filled; i<bar_width; i++)); do bar+="░"; done

# Format percentage to 1 decimal place
used_pct_fmt=$(printf "%.1f" "$used_pct")

# Calculate used tokens from percentage and context window size
total_tokens=$(printf "%.0f" "$(echo "$used_pct * $context_size / 100" | bc -l 2>/dev/null || echo "0")")
if [ "$total_tokens" -ge 1000 ]; then
    tokens_fmt=$(printf "%.1fK" "$(echo "$total_tokens / 1000" | bc -l)")
else
    tokens_fmt="${total_tokens}"
fi
if [ "$context_size" -ge 1000 ]; then
    context_fmt=$(printf "%.0fK" "$(echo "$context_size / 1000" | bc -l)")
else
    context_fmt="${context_size}"
fi

sep="\033[90m | \033[0m"

# Build status line with pipe separators
output=""

# 1. Model name + plan label (bright white for readability on dark backgrounds)
if [ -n "$plan_label" ]; then
    output+=$(printf "\033[97m%s\033[0m \033[90m(%s)\033[0m" "$model" "$plan_label")
else
    output+=$(printf "\033[97m%s\033[0m" "$model")
fi

# 2. Plan quota usage from real rate_limits data (Claude.ai subscription)
if [ -n "$five_hour_pct" ]; then
    five_int=$(printf "%.0f" "$five_hour_pct")
    if [ "$five_int" -ge 80 ]; then
        quota_color="\033[31m"  # red
    elif [ "$five_int" -ge 50 ]; then
        quota_color="\033[33m"  # yellow
    else
        quota_color="\033[32m"  # green
    fi
    output+=$(printf "${sep}\033[90m5h quota:\033[0m ${quota_color}%.0f%%\033[0m" "$five_hour_pct")
    output+=$(printf "${sep}\033[36mReset: %dh %02dm\033[0m" "$hours_until" "$mins_until")
elif [ -n "$seven_day_pct" ]; then
    # No 5-hour data but have 7-day — still show reset time
    output+=$(printf "${sep}\033[36mReset: %dh %02dm\033[0m" "$hours_until" "$mins_until")
fi

if [ -n "$seven_day_pct" ]; then
    week_int=$(printf "%.0f" "$seven_day_pct")
    if [ "$week_int" -ge 80 ]; then
        week_color="\033[31m"  # red
    elif [ "$week_int" -ge 50 ]; then
        week_color="\033[33m"  # yellow
    else
        week_color="\033[32m"  # green
    fi
    output+=$(printf "${sep}\033[90m7d quota:\033[0m ${week_color}%.0f%%\033[0m" "$seven_day_pct")
fi

# 3. Progress bar (color based on usage)
output+=$(printf "${sep}\033[90mContext:\033[0m ${bar_color}[%s]" "$bar")

# 4. Percentage context used (same color as bar)
output+=$(printf " %s%%\033[0m" "$used_pct_fmt")

# 5. Tokens (white)
output+=$(printf "${sep}\033[37m%s/%s\033[0m" "$tokens_fmt" "$context_fmt")

# 6. Git branch (green, only if available)
if [ -n "$git_branch" ]; then
    output+=$(printf "${sep}\033[32m%s\033[0m" "$git_branch")
fi

# 7. Project name (bright cyan)
output+=$(printf "${sep}\033[96m%s\033[0m" "$project_name")

echo -n "$output"
