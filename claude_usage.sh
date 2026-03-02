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
#   TMUX_POWERLINE_SEG_CLAUDE_USAGE_UPDATE_PERIOD - API poll interval in seconds (default: 60)

CLAUDE_USAGE_SESSION_KEY_FILE="${HOME}/.claude-session-key"
CLAUDE_USAGE_ORG_ID_FILE="${HOME}/.claude-org-id"
CLAUDE_USAGE_CACHE_FILE="/tmp/tmux-powerline-claude-usage-${USER}.cache"
CLAUDE_USAGE_UPDATE_PERIOD="${TMUX_POWERLINE_SEG_CLAUDE_USAGE_UPDATE_PERIOD:-60}"
CLAUDE_USAGE_MAX_BACKOFF=600

_build_bar() {
	local pct=$1 segments=10 filled
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

_get_color() {
	local pct=$1
	if [ "$pct" -ge 85 ]; then
		echo "colour196"
	elif [ "$pct" -ge 75 ]; then
		echo "colour178"
	else
		echo "colour173"
	fi
}

run_segment() {
	local now session_key org_id
	now=$(date +%s)

	# Try cache first (includes credentials)
	if [ -f "$CLAUDE_USAGE_CACHE_FILE" ]; then
		local cache_time cache_age cached_error_count cache_ttl
		cache_time=$(sed -n '1p' "$CLAUDE_USAGE_CACHE_FILE")
		cache_age=$((now - cache_time))
		cached_error_count=$(sed -n '6p' "$CLAUDE_USAGE_CACHE_FILE")
		cached_error_count=${cached_error_count:-0}

		# Calculate effective TTL: normal on success, exponential backoff on errors
		if [ "$cached_error_count" -gt 0 ] 2>/dev/null; then
			local backoff_exp
			backoff_exp=$cached_error_count
			[ "$backoff_exp" -gt 4 ] && backoff_exp=4
			cache_ttl=$((CLAUDE_USAGE_UPDATE_PERIOD * (1 << backoff_exp)))
			[ "$cache_ttl" -gt "$CLAUDE_USAGE_MAX_BACKOFF" ] && cache_ttl=$CLAUDE_USAGE_MAX_BACKOFF
		else
			cache_ttl=$CLAUDE_USAGE_UPDATE_PERIOD
		fi

		if [ "$cache_age" -lt "$cache_ttl" ]; then
			local cached_pct cached_reset_ts
			cached_pct=$(sed -n '2p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_reset_ts=$(sed -n '3p' "$CLAUDE_USAGE_CACHE_FILE")

			if [ "$cached_pct" = "expired" ]; then
				echo "#[fg=colour196]Claude: EXPIRED ░░░░░░░░░░"
				return 0
			fi

			# If resets_at has passed, cached percentage is stale — fall through to API call
			if [ -n "$cached_reset_ts" ]; then
				local reset_epoch
				reset_epoch=$(date -d "$cached_reset_ts" +%s 2>/dev/null)
				if [ -n "$reset_epoch" ] && [ "$now" -ge "$reset_epoch" ]; then
					# Window has reset — need fresh data
					session_key=$(sed -n '4p' "$CLAUDE_USAGE_CACHE_FILE")
					org_id=$(sed -n '5p' "$CLAUDE_USAGE_CACHE_FILE")
				else
					local cached_bar countdown color
					cached_bar=$(_build_bar "$cached_pct")
					countdown=$(_format_countdown "$cached_reset_ts")
					color=$(_get_color "$cached_pct")
					echo "#[fg=${color}]Claude: ${cached_pct}% ${cached_bar} ↻${countdown}"
					return 0
				fi
			else
				local cached_bar countdown color
				cached_bar=$(_build_bar "$cached_pct")
				countdown=$(_format_countdown "$cached_reset_ts")
				color=$(_get_color "$cached_pct")
				echo "#[fg=${color}]Claude: ${cached_pct}% ${cached_bar} ↻${countdown}"
				return 0
			fi
		else
			# Cache stale — read credentials from cache to avoid file reads
			session_key=$(sed -n '4p' "$CLAUDE_USAGE_CACHE_FILE")
			org_id=$(sed -n '5p' "$CLAUDE_USAGE_CACHE_FILE")
		fi
	fi

	# Fall back to credential files if not in cache
	if [ -z "$session_key" ] || [ -z "$org_id" ]; then
		if [ ! -f "$CLAUDE_USAGE_SESSION_KEY_FILE" ] || [ ! -f "$CLAUDE_USAGE_ORG_ID_FILE" ]; then
			echo "Claude: --% ░░░░░░░░░░ ↻?"
			return 0
		fi
		session_key=$(cat "$CLAUDE_USAGE_SESSION_KEY_FILE" 2>/dev/null)
		org_id=$(cat "$CLAUDE_USAGE_ORG_ID_FILE" 2>/dev/null)
		if [ -z "$session_key" ] || [ -z "$org_id" ]; then
			echo "Claude: --% ░░░░░░░░░░ ↻?"
			return 0
		fi
	fi

	# Acquire lock to prevent thundering herd — only one process calls the API
	local lock_file="/tmp/tmux-powerline-claude-usage-${USER}.lock"
	exec 9>"$lock_file"
	if ! flock -n 9; then
		# Another process is already calling the API; serve from cache
		exec 9>&-
		if [ -f "$CLAUDE_USAGE_CACHE_FILE" ]; then
			local cached_pct cached_bar cached_reset_ts countdown color
			cached_pct=$(sed -n '2p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_reset_ts=$(sed -n '3p' "$CLAUDE_USAGE_CACHE_FILE")
			if [ "$cached_pct" = "expired" ]; then
				echo "#[fg=colour196]Claude: EXPIRED ░░░░░░░░░░"
			elif [ -n "$cached_pct" ]; then
				cached_bar=$(_build_bar "$cached_pct")
				countdown=$(_format_countdown "$cached_reset_ts")
				color=$(_get_color "$cached_pct")
				echo "#[fg=${color}]Claude: ${cached_pct}% ${cached_bar} ↻${countdown}"
			else
				echo "Claude: --% ░░░░░░░░░░ ↻?"
			fi
		else
			echo "Claude: --% ░░░░░░░░░░ ↻?"
		fi
		return 0
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
			local cached_pct cached_bar cached_reset_ts countdown color prev_errors
			cached_pct=$(sed -n '2p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_reset_ts=$(sed -n '3p' "$CLAUDE_USAGE_CACHE_FILE")
			prev_errors=$(sed -n '6p' "$CLAUDE_USAGE_CACHE_FILE")
			prev_errors=${prev_errors:-0}
			local new_errors=$((prev_errors + 1))
			# If resets_at has passed, usage has reset — show 0%
			if [ -n "$cached_reset_ts" ]; then
				local reset_epoch
				reset_epoch=$(date -d "$cached_reset_ts" +%s 2>/dev/null)
				if [ -n "$reset_epoch" ] && [ "$now" -ge "$reset_epoch" ]; then
					cached_pct=0
				fi
			fi
			# Refresh cache timestamp with incremented error count
			printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$now" "$cached_pct" "$cached_reset_ts" "$session_key" "$org_id" "$new_errors" > "$CLAUDE_USAGE_CACHE_FILE"
			cached_bar=$(_build_bar "$cached_pct")
			countdown=$(_format_countdown "$cached_reset_ts")
			color=$(_get_color "$cached_pct")
			echo "#[fg=${color}]Claude: ${cached_pct}% ${cached_bar} ↻${countdown}"
		else
			echo "Claude: --% ░░░░░░░░░░ ↻?"
		fi
		exec 9>&-
		return 0
	fi

	# Check for API error responses (expired key, permission error, rate limit)
	local api_error error_type
	api_error=$(echo "$response" | jq -r '.type // empty' 2>/dev/null)
	error_type=$(echo "$response" | jq -r '.error.type // empty' 2>/dev/null)
	if [ "$api_error" = "error" ] || [ -n "$error_type" ]; then
		if [ "$error_type" = "authentication_error" ] || [ "$error_type" = "permission_error" ]; then
			printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$now" "expired" "" "$session_key" "$org_id" "0" > "$CLAUDE_USAGE_CACHE_FILE"
			echo "#[fg=colour196]Claude: EXPIRED ░░░░░░░░░░"
		else
			# Transient error (e.g. 500, rate_limit_error) — fall back to cache
			if [ -f "$CLAUDE_USAGE_CACHE_FILE" ]; then
				local cached_pct cached_reset_ts prev_errors
				cached_pct=$(sed -n '2p' "$CLAUDE_USAGE_CACHE_FILE")
				cached_reset_ts=$(sed -n '3p' "$CLAUDE_USAGE_CACHE_FILE")
				prev_errors=$(sed -n '6p' "$CLAUDE_USAGE_CACHE_FILE")
				prev_errors=${prev_errors:-0}
				local new_errors=$((prev_errors + 1))
				if [ "$cached_pct" = "expired" ]; then
					echo "#[fg=colour196]Claude: EXPIRED ░░░░░░░░░░"
				else
					# If resets_at has passed, usage has reset — show 0%
					if [ -n "$cached_reset_ts" ]; then
						local reset_epoch
						reset_epoch=$(date -d "$cached_reset_ts" +%s 2>/dev/null)
						if [ -n "$reset_epoch" ] && [ "$now" -ge "$reset_epoch" ]; then
							cached_pct=0
						fi
					fi
					# Refresh cache timestamp with incremented error count
					printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$now" "$cached_pct" "$cached_reset_ts" "$session_key" "$org_id" "$new_errors" > "$CLAUDE_USAGE_CACHE_FILE"
					local cached_bar countdown color
					cached_bar=$(_build_bar "$cached_pct")
					countdown=$(_format_countdown "$cached_reset_ts")
					color=$(_get_color "$cached_pct")
					echo "#[fg=${color}]Claude: ${cached_pct}% ${cached_bar} ↻${countdown}"
				fi
			else
				echo "#[fg=colour196]Claude: ERR ░░░░░░░░░░"
			fi
		fi
		exec 9>&-
		return 0
	fi

	# Parse usage
	local session_pct reset_ts
	session_pct=$(echo "$response" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
	reset_ts=$(echo "$response" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)

	if [ -z "$session_pct" ]; then
		# Unexpected response format — fall back to cache if available
		if [ -f "$CLAUDE_USAGE_CACHE_FILE" ]; then
			local cached_pct cached_reset_ts prev_errors
			cached_pct=$(sed -n '2p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_reset_ts=$(sed -n '3p' "$CLAUDE_USAGE_CACHE_FILE")
			prev_errors=$(sed -n '6p' "$CLAUDE_USAGE_CACHE_FILE")
			prev_errors=${prev_errors:-0}
			local new_errors=$((prev_errors + 1))
			if [ "$cached_pct" != "expired" ] && [ -n "$cached_pct" ]; then
				# If resets_at has passed, usage has reset — show 0%
				if [ -n "$cached_reset_ts" ]; then
					local reset_epoch
					reset_epoch=$(date -d "$cached_reset_ts" +%s 2>/dev/null)
					if [ -n "$reset_epoch" ] && [ "$now" -ge "$reset_epoch" ]; then
						cached_pct=0
					fi
				fi
				# Refresh cache timestamp with incremented error count
				printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$now" "$cached_pct" "$cached_reset_ts" "$session_key" "$org_id" "$new_errors" > "$CLAUDE_USAGE_CACHE_FILE"
				local cached_bar countdown color
				cached_bar=$(_build_bar "$cached_pct")
				countdown=$(_format_countdown "$cached_reset_ts")
				color=$(_get_color "$cached_pct")
				echo "#[fg=${color}]Claude: ${cached_pct}% ${cached_bar} ↻${countdown}"
				exec 9>&-
				return 0
			fi
		fi
		echo "#[fg=colour178]Claude: ERR ░░░░░░░░░░"
		exec 9>&-
		return 0
	fi

	session_pct=$(printf "%.0f" "$session_pct")
	local bar countdown color
	bar=$(_build_bar "$session_pct")
	countdown=$(_format_countdown "$reset_ts")
	color=$(_get_color "$session_pct")

	# Cache: line1=timestamp, line2=pct, line3=reset_ts, line4=session_key, line5=org_id, line6=error_count
	printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$now" "$session_pct" "$reset_ts" "$session_key" "$org_id" "0" > "$CLAUDE_USAGE_CACHE_FILE"

	echo "#[fg=${color}]Claude: ${session_pct}% ${bar} ↻${countdown}"
	exec 9>&-
	return 0
}
