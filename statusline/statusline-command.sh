#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code statusline — adapted from Downloads/claude-statusline.
# Segments:  📂 folder · ⎇ branch · ★ model · effort · 🧠 context bar · ⏳ limits
#
# Adaptations vs. the original drop-in:
#   • adds reasoning effort (.effort.level) next to the model
#   • rounds context % so a fractional used_percentage can't break the bar math
#   • uses `git --no-optional-locks` so it never touches a busy repo's index
#
# Reads Claude Code's statusline JSON on stdin; any missing field hides its
# segment (rate_limits are Pro/Max only and appear after the first response).
# Requires jq.
# ─────────────────────────────────────────────────────────────────────────────
input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
dir=$(basename "$cwd")
model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Colors
cyan="\033[36m"
magenta="\033[35m"
dim="\033[90m"
bright_yellow="\033[93m"
bright_blue="\033[94m"
reset="\033[0m"

# 📂 folder (cyan)
output="${cyan}📂 ${dir}${reset}"

# ⎇ git branch (bright yellow) — hidden outside a git repo
if [ -n "$cwd" ]; then
    branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
    [ -n "$branch" ] && output="${output}  ${bright_yellow}⎇ ${branch}${reset}"
fi

# ★ model (magenta), with reasoning effort appended when the model exposes it
if [ -n "$model" ]; then
    seg="★ ${model}"
    [ -n "$effort" ] && seg="${seg} ${dim}·${magenta} ${effort}"
    output="${output}  ${magenta}${seg}${reset}"
fi

# 🧠 context-window usage bar (green <50% / yellow 50-70% / red >70%)
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
    used=$(printf "%.0f" "$used" 2>/dev/null || echo 0)
    filled=$(( used / 10 ))
    [ "$filled" -gt 10 ] && filled=10
    [ "$filled" -lt 0 ] && filled=0
    empty=$(( 10 - filled ))
    bar=""; i=0
    while [ $i -lt $filled ]; do bar="${bar}█"; i=$(( i + 1 )); done
    i=0
    while [ $i -lt $empty ]; do bar="${bar}░"; i=$(( i + 1 )); done
    if   [ "$used" -gt 70 ]; then color="\033[31m"
    elif [ "$used" -ge 50 ]; then color="\033[33m"
    else color="\033[32m"; fi
    output="${output}  |  ${color}🧠 Context [${bar}] ${used}%${reset}"
fi

# ⏳ subscription rate limits (bright blue) — Claude.ai Pro/Max only
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_seg=""
[ -n "$five" ] && rate_seg="5H: $(printf "%.0f" "$five")%"
[ -n "$week" ] && rate_seg="${rate_seg:+$rate_seg, }7D: $(printf "%.0f" "$week")%"
[ -n "$rate_seg" ] && output="${output}  |  ${bright_blue}⏳ Claude Limits - ${rate_seg}${reset}"

printf "%b" "$output"
