#!/bin/bash
# ABOUTME: Renders the Claude Code status line from JSON piped via stdin.
# ABOUTME: Line 1 holds the resource meters (5h/7d rate limits, context); line 2 holds model, effort, agent, project, git diff, thinking.

input=$(cat)

# ANSI colors. Filled meter cells use a severity color (green/yellow/red); labels,
# empty cells, separators and secondary fields are dimmed so the accented values pop.
RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'

# Model display name — strip parenthetical context size suffix e.g. " (1M context)"
model=$(echo "$input" | jq -r '.model.display_name // empty' | sed 's/ ([^)]*context)//')

# Effort level (only present when the model supports reasoning effort)
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Agent name (only present when running as a subagent via --agent flag)
agent_name=$(echo "$input" | jq -r '.agent.name // empty')
agent_out=""
[ -n "$agent_name" ] && agent_out="${DIM}agent:${RESET}$agent_name"

# Project directory basename
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
[ -n "$project_dir" ] && project_dir=$(basename "$project_dir")

# Lines of code changed — uncommitted diff (staged + unstaged) vs HEAD
cwd_path=$(echo "$input" | jq -r '.cwd // empty')
git_stat=""
if [ -n "$cwd_path" ]; then
    raw_stat=$(git --no-optional-locks -C "$cwd_path" diff --shortstat HEAD 2>/dev/null)
    if [ -n "$raw_stat" ]; then
        ins=$(echo "$raw_stat" | grep -oE '[0-9]+ insertion' | awk '{print $1}')
        del=$(echo "$raw_stat" | grep -oE '[0-9]+ deletion' | awk '{print $1}')
        [ -z "$ins" ] && ins=0
        [ -z "$del" ] && del=0
        git_stat="${GREEN}+${ins}${RESET}${DIM}/${RESET}${RED}-${del}${RESET} ${DIM}lines${RESET}"
    fi
fi

# Extended thinking — only shown when enabled
thinking=$(echo "$input" | jq -r '.thinking.enabled // false')

# Severity color for a usage percentage: green under 50%, yellow 50-79%, red 80%+.
sev_color() {
    if [ "$1" -ge 80 ]; then printf '%s' "$RED"
    elif [ "$1" -ge 50 ]; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"; fi
}

# Draws a 10-cell progress bar for a given percentage (0-100), e.g. "[▓▓▓░░░░░░░] 30%".
# Cells round to the nearest tenth, and any nonzero percentage fills at least one cell so a
# small usage still registers honestly; only a true 0% shows an all-empty bar. Fill (▓) and
# empty (░) are both shade glyphs so they share a cell box and stay vertically aligned. The
# filled run and the percentage take a severity color; brackets and empty cells are dimmed.
draw_bar() {
    local pct_int="$1"
    [ "$pct_int" -gt 100 ] && pct_int=100
    [ "$pct_int" -lt 0 ] && pct_int=0
    local filled=$(( (pct_int + 5) / 10 ))
    [ "$filled" -eq 0 ] && [ "$pct_int" -gt 0 ] && filled=1
    [ "$filled" -gt 10 ] && filled=10
    local color; color=$(sev_color "$pct_int")
    local fill="" empty="" i=0
    while [ "$i" -lt "$filled" ]; do fill="${fill}▓"; i=$(( i + 1 )); done
    while [ "$i" -lt 10 ]; do empty="${empty}░"; i=$(( i + 1 )); done
    printf '%s[%s%s%s%s%s]%s %s%d%%%s' \
        "$DIM" "$RESET" "$color$fill$RESET" "$DIM$empty" "$RESET" "$DIM" "$RESET" \
        "$color" "$pct_int" "$RESET"
}

# Formats a Unix epoch reset time the way Claude's own UI does: a relative
# countdown ("22m", "3h12m") inside a day, an absolute weekday+time beyond that.
format_reset() {
    local resets_at="$1"
    [ -z "$resets_at" ] && return
    local now diff
    now=$(date +%s)
    diff=$(( resets_at - now ))
    [ "$diff" -lt 0 ] && diff=0
    if [ "$diff" -lt 3600 ]; then
        printf '%dm' $(( (diff + 30) / 60 ))
    elif [ "$diff" -lt 86400 ]; then
        printf '%dh%dm' $(( diff / 3600 )) $(( (diff % 3600) / 60 ))
    else
        date -r "$resets_at" '+%a %-I:%M %p'
    fi
}

# Rate limits (5-hour and/or 7-day), each as its own bar + reset time
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
five_hour_out=""
if [ -n "$five_hour_pct" ]; then
    five_hour_out="${DIM}5h:${RESET}$(draw_bar "$(printf '%.0f' "$five_hour_pct")")"
    [ -n "$five_hour_reset" ] && five_hour_out="$five_hour_out ${DIM}($(format_reset "$five_hour_reset"))${RESET}"
fi

seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
seven_day_out=""
if [ -n "$seven_day_pct" ]; then
    seven_day_out="${DIM}7d:${RESET}$(draw_bar "$(printf '%.0f' "$seven_day_pct")")"
    [ -n "$seven_day_reset" ] && seven_day_out="$seven_day_out ${DIM}($(format_reset "$seven_day_reset"))${RESET}"
fi

# Context window progress bar (10 cells)
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_out=""
[ -n "$used_pct" ] && ctx_out="${DIM}ctx:${RESET}$(draw_bar "$(printf '%.0f' "$used_pct")")"

# Line 1 holds the resource meters; line 2 holds model/effort/agent/project/git/thinking.
# Each field is appended with " · " only when non-empty, so absent fields leave no gaps.
line1=""
line2=""
sep="${DIM} · ${RESET}"
add1() { [ -z "$1" ] && return; [ -n "$line1" ] && line1="$line1$sep"; line1="$line1$1"; }
add2() { [ -z "$1" ] && return; [ -n "$line2" ] && line2="$line2$sep"; line2="$line2$1"; }

add1 "$five_hour_out"
add1 "$seven_day_out"
add1 "$ctx_out"

[ -n "$model" ] && add2 "${BOLD}${model}${RESET}"
[ -n "$effort" ] && add2 "${DIM}effort:${RESET}$effort"
add2 "$agent_out"
[ -n "$project_dir" ] && add2 "${CYAN}${project_dir}${RESET}"
add2 "$git_stat"
[ "$thinking" = "true" ] && add2 "${MAGENTA}thinking${RESET}"

[ -n "$line1" ] && printf '%s\n' "$line1"
[ -n "$line2" ] && printf '%s\n' "$line2"
