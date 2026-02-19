# shellcheck shell=bash
# Displays Claude AI session usage with progress bar and reset countdown.
# A tmux-powerline segment for monitoring Claude AI rate limits.
#
# Requirements: curl, jq
#
# Setup:
#   1. Store your claude.ai session key:
#      echo "sk-ant-sid01-..." > ~/.claude-session-key && chmod 600 ~/.claude-session-key
#
#   2. Store your organization ID:
#      echo "your-org-uuid" > ~/.claude-org-id && chmod 600 ~/.claude-org-id
#
#   To find your org ID, extract your session key first, then run:
#      curl -s -H "Cookie: sessionKey=$(cat ~/.claude-session-key)" \
#        -H "User-Agent: Mozilla/5.0" -H "Origin: https://claude.ai" \
#        "https://claude.ai/api/organizations" | jq '.[].uuid, .[].name'
#
#   3. Copy this file to your tmux-powerline user segments directory:
#      cp claude_usage.sh ~/.config/tmux-powerline/segments/
#
#   4. Add to your theme file (e.g. ~/.config/tmux-powerline/themes/default.sh):
#      "claude_usage 238 173"
#
# Configuration (optional, set in tmux-powerline config.sh):
#   TMUX_POWERLINE_SEG_CLAUDE_USAGE_UPDATE_PERIOD - API poll interval in seconds (default: 120)

CLAUDE_USAGE_SESSION_KEY_FILE="${HOME}/.claude-session-key"
CLAUDE_USAGE_ORG_ID_FILE="${HOME}/.claude-org-id"
CLAUDE_USAGE_CACHE_FILE="/tmp/tmux-powerline-claude-usage-${USER}.cache"
CLAUDE_USAGE_UPDATE_PERIOD="${TMUX_POWERLINE_SEG_CLAUDE_USAGE_UPDATE_PERIOD:-120}"

_build_bar() {
	local pct=$1 segments=5 filled
	filled=$(( (pct * segments + 99) / 100 ))
	[ "$filled" -gt "$segments" ] && filled=$segments
	local bar=""
	for ((i=0; i<segments; i++)); do
		if [ "$i" -lt "$filled" ]; then
			bar="${bar}▓"
		else
			bar="${bar}░"
		fi
	done
	echo "$bar"
}

_format_countdown() {
	local reset_ts=$1
	local now reset_epoch diff hours mins

	now=$(date +%s)
	reset_epoch=$(date -d "$reset_ts" +%s 2>/dev/null)

	if [ -z "$reset_epoch" ]; then
		echo "?"
		return
	fi

	diff=$((reset_epoch - now))
	if [ "$diff" -le 0 ]; then
		echo "now"
		return
	fi

	hours=$((diff / 3600))
	mins=$(( (diff % 3600) / 60 ))

	if [ "$hours" -gt 0 ]; then
		echo "${hours}h${mins}m"
	else
		echo "${mins}m"
	fi
}

run_segment() {
	if [ ! -f "$CLAUDE_USAGE_SESSION_KEY_FILE" ] || [ ! -f "$CLAUDE_USAGE_ORG_ID_FILE" ]; then
		echo "Claude --% ░░░░░ ↻?"
		return 0
	fi

	local session_key org_id
	session_key=$(cat "$CLAUDE_USAGE_SESSION_KEY_FILE" 2>/dev/null)
	org_id=$(cat "$CLAUDE_USAGE_ORG_ID_FILE" 2>/dev/null)

	if [ -z "$session_key" ] || [ -z "$org_id" ]; then
		echo "Claude --% ░░░░░ ↻?"
		return 0
	fi

	# Check cache (cache stores: line1=timestamp, line2=pct, line3=reset_ts)
	local now
	now=$(date +%s)

	if [ -f "$CLAUDE_USAGE_CACHE_FILE" ]; then
		local cache_time cache_age
		cache_time=$(sed -n '1p' "$CLAUDE_USAGE_CACHE_FILE")
		cache_age=$((now - cache_time))
		if [ "$cache_age" -lt "$CLAUDE_USAGE_UPDATE_PERIOD" ]; then
			# Rebuild output with fresh countdown from cached reset time
			local cached_pct cached_bar cached_reset_ts countdown
			cached_pct=$(sed -n '2p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_reset_ts=$(sed -n '3p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_bar=$(_build_bar "$cached_pct")
			countdown=$(_format_countdown "$cached_reset_ts")
			echo "Claude ${cached_pct}% ${cached_bar} ↻${countdown}"
			return 0
		fi
	fi

	# Fetch from API
	local response
	response=$(curl -s --max-time 5 \
		-H "Cookie: sessionKey=${session_key}" \
		-H "Accept: application/json" \
		-H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
		-H "Referer: https://claude.ai/" \
		-H "Origin: https://claude.ai" \
		"https://claude.ai/api/organizations/${org_id}/usage" 2>/dev/null)

	if [ -z "$response" ]; then
		if [ -f "$CLAUDE_USAGE_CACHE_FILE" ]; then
			local cached_pct cached_bar cached_reset_ts countdown
			cached_pct=$(sed -n '2p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_reset_ts=$(sed -n '3p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_bar=$(_build_bar "$cached_pct")
			countdown=$(_format_countdown "$cached_reset_ts")
			echo "Claude ${cached_pct}% ${cached_bar} ↻${countdown}"
		else
			echo "Claude --% ░░░░░ ↻?"
		fi
		return 0
	fi

	# Parse usage
	local session_pct reset_ts
	session_pct=$(echo "$response" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
	reset_ts=$(echo "$response" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)

	if [ -z "$session_pct" ]; then
		echo "Claude err ░░░░░"
		return 0
	fi

	session_pct=$(printf "%.0f" "$session_pct")
	local bar countdown
	bar=$(_build_bar "$session_pct")
	countdown=$(_format_countdown "$reset_ts")

	# Cache: line1=timestamp, line2=pct, line3=reset_ts
	printf '%s\n%s\n%s\n' "$now" "$session_pct" "$reset_ts" > "$CLAUDE_USAGE_CACHE_FILE"

	echo "Claude ${session_pct}% ${bar} ↻${countdown}"
	return 0
}
