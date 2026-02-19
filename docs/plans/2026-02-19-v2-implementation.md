# claude_tmux_powerline v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add color-coded output, expiration detection with helper script, credential caching, install script, and clean up TODO.

**Architecture:** The segment (`claude_usage.sh`) emits inline tmux `#[fg=colourN]` codes to dynamically color output based on usage thresholds. A new `refresh-key.sh` handles interactive credential setup/refresh. An `install.sh` automates first-time setup. The cache file is extended to store credentials alongside API data.

**Tech Stack:** Bash, tmux formatting codes, curl, jq

---

### Task 1: Add colon to display format and color-coded output

**Files:**
- Modify: `claude_usage.sh:33-46` (`_build_bar`)
- Modify: `claude_usage.sh:76-155` (`run_segment`)

**Step 1: Add `_get_color` helper function after `_format_countdown`**

Add this function at line 74 (after `_format_countdown` closes):

```bash
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
```

**Step 2: Update all output lines in `run_segment` to use `Claude:` with color**

Replace all `echo` output lines in `run_segment` to use the new format. There are 7 echo statements to update:

1. Line 78 (no creds file): `echo "Claude: --% ░░░░░ ↻?"`
2. Line 87 (empty creds): `echo "Claude: --% ░░░░░ ↻?"`
3. Line 106 (cached hit): Use color — `echo "#[fg=${color}]Claude: ${cached_pct}% ${cached_bar} ↻${countdown}"`
4. Line 128 (network fail, cached): Same color pattern
5. Line 130 (network fail, no cache): `echo "Claude: --% ░░░░░ ↻?"`
6. Line 141 (API error): `echo "#[fg=colour196]Claude: EXPIRED ░░░░░"`
7. Line 153 (success): Use color — `echo "#[fg=${color}]Claude: ${session_pct}% ${bar} ↻${countdown}"`

For the cached and success paths, compute color with:
```bash
local color
color=$(_get_color "$cached_pct")
```

**Step 3: Test the segment**

Run:
```bash
rm -f /tmp/tmux-powerline-claude-usage-danny.cache
source ~/projects/claude_tmux_powerline/claude_usage.sh && run_segment
```

Expected: Output starts with `#[fg=colour173]Claude: XX% ...` (or 178/196 depending on current usage)

**Step 4: Copy to live segments directory**

```bash
cp ~/projects/claude_tmux_powerline/claude_usage.sh ~/.config/tmux-powerline/segments/claude_usage.sh
```

**Step 5: Commit**

```bash
git add claude_usage.sh
git commit -m "feat: add color-coded output and colon to display format"
```

---

### Task 2: Improve expiration detection

**Files:**
- Modify: `claude_usage.sh:135-143` (API error handling in `run_segment`)

**Step 1: Replace the empty `session_pct` check with proper error detection**

Currently line 140-143 checks if `session_pct` is empty. Replace with logic that distinguishes:
- Empty response (network failure) — already handled above
- JSON error with `"type":"error"` — expired key or permission error
- Missing `utilization` field — unexpected API change

Replace the error check block:

```bash
	# Check for API error responses (expired key, permission error)
	local api_error
	api_error=$(echo "$response" | jq -r '.type // empty' 2>/dev/null)
	if [ "$api_error" = "error" ]; then
		local error_type
		error_type=$(echo "$response" | jq -r '.error.type // empty' 2>/dev/null)
		if [ "$error_type" = "authentication_error" ] || [ "$error_type" = "permission_error" ]; then
			# Cache the expired status so we don't keep hitting the API
			printf '%s\n%s\n%s\n%s\n' "$now" "expired" "" "expired" > "$CLAUDE_USAGE_CACHE_FILE"
			echo "#[fg=colour196]Claude: EXPIRED ░░░░░"
		else
			echo "#[fg=colour196]Claude: ERR ░░░░░"
		fi
		return 0
	fi

	# Parse usage
	local session_pct reset_ts
	session_pct=$(echo "$response" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
	reset_ts=$(echo "$response" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)

	if [ -z "$session_pct" ]; then
		echo "#[fg=colour178]Claude: ERR ░░░░░"
		return 0
	fi
```

**Step 2: Update cached path to handle expired status**

In the cache-read section, after reading `cached_pct`, add a check:

```bash
			if [ "$cached_pct" = "expired" ]; then
				echo "#[fg=colour196]Claude: EXPIRED ░░░░░"
				return 0
			fi
```

**Step 3: Test with current key**

```bash
rm -f /tmp/tmux-powerline-claude-usage-danny.cache
source ~/projects/claude_tmux_powerline/claude_usage.sh && run_segment
```

Expected: Normal output (key is valid)

**Step 4: Commit**

```bash
git add claude_usage.sh
git commit -m "feat: detect expired keys and show EXPIRED status"
```

---

### Task 3: Add credential caching

**Files:**
- Modify: `claude_usage.sh` (`run_segment` — cache read/write sections)

**Step 1: Extend cache format to include credentials**

Update the cache write (currently 3 lines) to 5 lines:

```bash
	# Cache: line1=timestamp, line2=pct, line3=reset_ts, line4=session_key, line5=org_id
	printf '%s\n%s\n%s\n%s\n%s\n' "$now" "$session_pct" "$reset_ts" "$session_key" "$org_id" > "$CLAUDE_USAGE_CACHE_FILE"
```

Also update the expired cache write to include credentials:
```bash
	printf '%s\n%s\n%s\n%s\n%s\n' "$now" "expired" "" "$session_key" "$org_id" > "$CLAUDE_USAGE_CACHE_FILE"
```

**Step 2: Read credentials from cache when cache is valid**

Restructure the top of `run_segment` so that:
1. If cache exists and is fresh, read credentials from cache (lines 4-5)
2. Only fall back to reading credential files when cache is stale or missing

```bash
run_segment() {
	local now session_key org_id
	now=$(date +%s)

	# Try cache first (includes credentials)
	if [ -f "$CLAUDE_USAGE_CACHE_FILE" ]; then
		local cache_time cache_age
		cache_time=$(sed -n '1p' "$CLAUDE_USAGE_CACHE_FILE")
		cache_age=$((now - cache_time))
		if [ "$cache_age" -lt "$CLAUDE_USAGE_UPDATE_PERIOD" ]; then
			local cached_pct cached_reset_ts
			cached_pct=$(sed -n '2p' "$CLAUDE_USAGE_CACHE_FILE")
			cached_reset_ts=$(sed -n '3p' "$CLAUDE_USAGE_CACHE_FILE")

			if [ "$cached_pct" = "expired" ]; then
				echo "#[fg=colour196]Claude: EXPIRED ░░░░░"
				return 0
			fi

			local cached_bar countdown color
			cached_bar=$(_build_bar "$cached_pct")
			countdown=$(_format_countdown "$cached_reset_ts")
			color=$(_get_color "$cached_pct")
			echo "#[fg=${color}]Claude: ${cached_pct}% ${cached_bar} ↻${countdown}"
			return 0
		fi

		# Cache stale — read credentials from cache to avoid file reads
		session_key=$(sed -n '4p' "$CLAUDE_USAGE_CACHE_FILE")
		org_id=$(sed -n '5p' "$CLAUDE_USAGE_CACHE_FILE")
	fi

	# Fall back to credential files if not in cache
	if [ -z "$session_key" ] || [ -z "$org_id" ]; then
		if [ ! -f "$CLAUDE_USAGE_SESSION_KEY_FILE" ] || [ ! -f "$CLAUDE_USAGE_ORG_ID_FILE" ]; then
			echo "Claude: --% ░░░░░ ↻?"
			return 0
		fi
		session_key=$(cat "$CLAUDE_USAGE_SESSION_KEY_FILE" 2>/dev/null)
		org_id=$(cat "$CLAUDE_USAGE_ORG_ID_FILE" 2>/dev/null)
		if [ -z "$session_key" ] || [ -z "$org_id" ]; then
			echo "Claude: --% ░░░░░ ↻?"
			return 0
		fi
	fi

	# ... rest of API call and response handling ...
```

**Step 3: Test**

```bash
rm -f /tmp/tmux-powerline-claude-usage-danny.cache
source ~/projects/claude_tmux_powerline/claude_usage.sh && run_segment
# First call reads files, writes cache
source ~/projects/claude_tmux_powerline/claude_usage.sh && run_segment
# Second call reads from cache only
```

Expected: Both produce same output

**Step 4: Commit**

```bash
git add claude_usage.sh
git commit -m "perf: cache credentials in cache file to reduce disk reads"
```

---

### Task 4: Create refresh-key.sh

**Files:**
- Create: `refresh-key.sh`

**Step 1: Write the script**

```bash
#!/bin/bash
# Interactive helper to set up or refresh Claude AI credentials.
# Usage: ./refresh-key.sh

set -euo pipefail

SESSION_KEY_FILE="${HOME}/.claude-session-key"
ORG_ID_FILE="${HOME}/.claude-org-id"
CACHE_FILE="/tmp/tmux-powerline-claude-usage-${USER}.cache"

echo "=== Claude tmux-powerline: Credential Setup ==="
echo ""

# Step 1: Session key
echo "Step 1: Session Key"
echo "  1. Go to https://claude.ai in your browser"
echo "  2. Open DevTools (F12) > Application > Cookies > https://claude.ai"
echo "  3. Copy the 'sessionKey' value (starts with sk-ant-sid...)"
echo ""
read -rp "Paste your session key: " session_key

if [ -z "$session_key" ]; then
	echo "Error: No session key provided." >&2
	exit 1
fi

# Validate key format
if [[ ! "$session_key" =~ ^sk-ant-sid ]]; then
	echo "Warning: Key doesn't start with 'sk-ant-sid'. Are you sure this is correct?"
	read -rp "Continue anyway? [y/N]: " confirm
	if [[ ! "$confirm" =~ ^[yY] ]]; then
		exit 1
	fi
fi

# Step 2: Fetch orgs
echo ""
echo "Step 2: Fetching your organizations..."
orgs=$(curl -s --max-time 10 \
	-H "Cookie: sessionKey=${session_key}" \
	-H "Accept: application/json" \
	-H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
	-H "Referer: https://claude.ai/" \
	-H "Origin: https://claude.ai" \
	"https://claude.ai/api/organizations" 2>/dev/null)

if [ -z "$orgs" ] || echo "$orgs" | jq -e '.type == "error"' >/dev/null 2>&1; then
	echo "Error: Failed to fetch organizations. Is your session key valid?" >&2
	echo "Response: $orgs" >&2
	exit 1
fi

org_count=$(echo "$orgs" | jq 'length')
echo ""
echo "Found $org_count organization(s):"
echo ""

for i in $(seq 0 $((org_count - 1))); do
	name=$(echo "$orgs" | jq -r ".[$i].name")
	uuid=$(echo "$orgs" | jq -r ".[$i].uuid")
	echo "  [$((i + 1))] $name ($uuid)"
done

echo ""
if [ "$org_count" -eq 1 ]; then
	org_id=$(echo "$orgs" | jq -r '.[0].uuid')
	echo "Auto-selected the only organization."
else
	read -rp "Select organization [1-${org_count}]: " selection
	selection=$((selection - 1))
	org_id=$(echo "$orgs" | jq -r ".[$selection].uuid")
fi

# Step 3: Validate by fetching usage
echo ""
echo "Step 3: Validating credentials..."
usage=$(curl -s --max-time 10 \
	-H "Cookie: sessionKey=${session_key}" \
	-H "Accept: application/json" \
	-H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
	-H "Referer: https://claude.ai/" \
	-H "Origin: https://claude.ai" \
	"https://claude.ai/api/organizations/${org_id}/usage" 2>/dev/null)

pct=$(echo "$usage" | jq -r '.five_hour.utilization // empty' 2>/dev/null)

if [ -z "$pct" ]; then
	echo "Error: Could not fetch usage data. Credentials may be invalid." >&2
	echo "Response: $usage" >&2
	exit 1
fi

pct_display=$(printf "%.0f" "$pct")
echo "Success! Current usage: ${pct_display}%"

# Step 4: Save credentials
echo ""
echo "Saving credentials..."
echo "$session_key" > "$SESSION_KEY_FILE"
chmod 600 "$SESSION_KEY_FILE"
echo "  Wrote $SESSION_KEY_FILE"

echo "$org_id" > "$ORG_ID_FILE"
chmod 600 "$ORG_ID_FILE"
echo "  Wrote $ORG_ID_FILE"

# Clear cache to force refresh
rm -f "$CACHE_FILE"
echo "  Cleared cache"

echo ""
echo "Done! Your tmux status bar will update on next refresh."
```

**Step 2: Make executable**

```bash
chmod +x refresh-key.sh
```

**Step 3: Test (dry run — just verify it starts)**

```bash
echo "" | timeout 2 ./refresh-key.sh 2>&1 || true
```

Expected: Shows the intro text and prompts for session key

**Step 4: Commit**

```bash
git add refresh-key.sh
git commit -m "feat: add interactive credential setup/refresh helper"
```

---

### Task 5: Create install.sh

**Files:**
- Create: `install.sh`

**Step 1: Write the install script**

```bash
#!/bin/bash
# Installer for claude_tmux_powerline
# Usage: ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEGMENTS_DIR="${HOME}/.config/tmux-powerline/segments"
THEME_DIR="${HOME}/.config/tmux-powerline/themes"
SEGMENT_LINE='"claude_usage 238 173"'

echo "=== claude_tmux_powerline installer ==="
echo ""

# Check dependencies
echo "Checking dependencies..."
missing=()
command -v curl >/dev/null 2>&1 || missing+=("curl")
command -v jq >/dev/null 2>&1 || missing+=("jq")

if [ ! -d "${HOME}/.tmux/plugins/tmux-powerline" ] && [ ! -d "/usr/share/tmux-powerline" ]; then
	missing+=("tmux-powerline")
fi

if [ ${#missing[@]} -gt 0 ]; then
	echo "Error: Missing dependencies: ${missing[*]}" >&2
	exit 1
fi
echo "  All dependencies found."

# Copy segment
echo ""
echo "Installing segment..."
mkdir -p "$SEGMENTS_DIR"
cp "${SCRIPT_DIR}/claude_usage.sh" "${SEGMENTS_DIR}/claude_usage.sh"
echo "  Copied to ${SEGMENTS_DIR}/claude_usage.sh"

# Check theme
echo ""
echo "Checking theme configuration..."
theme_file="${THEME_DIR}/default.sh"

if [ -f "$theme_file" ]; then
	if grep -q "claude_usage" "$theme_file"; then
		echo "  Segment already in theme file."
	else
		echo "  Adding segment to theme..."
		# Insert before the closing paren of RIGHT_STATUS_SEGMENTS
		sed -i '/TMUX_POWERLINE_RIGHT_STATUS_SEGMENTS=(/{
			n
			s/^/\t\t"claude_usage 238 173"\n/
		}' "$theme_file"
		echo "  Added to ${theme_file}"
	fi
else
	echo "  No theme file found at ${theme_file}."
	echo "  You'll need to manually add ${SEGMENT_LINE} to your theme."
fi

# Credential setup
echo ""
read -rp "Set up credentials now? [Y/n]: " setup_creds
if [[ ! "$setup_creds" =~ ^[nN] ]]; then
	"${SCRIPT_DIR}/refresh-key.sh"
else
	echo "Skipping credential setup. Run ./refresh-key.sh later."
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Reload tmux to see the segment:"
echo "  tmux kill-server && tmux"
```

**Step 2: Make executable**

```bash
chmod +x install.sh
```

**Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add install script with dependency check and theme injection"
```

---

### Task 6: Update TODO.md

**Files:**
- Modify: `TODO.md`

**Step 1: Rewrite TODO.md removing macOS items and marking completed work**

```markdown
# TODO

## Planned Features

- **[medium]** Configurable display format — let users choose which components to show (label, bar, percentage, countdown)
  - `claude_usage.sh` (`run_segment`)

- **[low]** Weekly usage display — optional toggle to also show 7-day utilization
  - `claude_usage.sh` (`run_segment`)

- **[low]** Configurable bar length — let users set segment count (default 5)
  - `claude_usage.sh` (`_build_bar`)

## AI-Suggested Improvements

- **[medium]** Notification hook — optional script/command to run when usage crosses a threshold (e.g. 85%), useful for desktop notifications via `notify-send`
- **[medium]** Multi-org support — allow tracking multiple organizations and showing the active one
- **[low]** Sparkle chart — show usage trend over time using a tiny spark line (e.g. `▁▂▃▅▇`)
```

**Step 2: Commit**

```bash
git add TODO.md
git commit -m "docs: clean up TODO, remove completed and macOS items"
```

---

### Task 7: Update README.md

**Files:**
- Modify: `README.md`

**Step 1: Update README to reflect new features**

Key changes:
- Update display format examples to show `Claude:` with colon
- Add color-coded section explaining thresholds
- Update Setup section to mention `install.sh` and `refresh-key.sh`
- Remove macOS limitation
- Remove credential-reading limitation (now cached)
- Update architecture diagram to show credential caching

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for v2 features"
```

---

### Task 8: Copy to live and push

**Step 1: Copy updated segment to live location**

```bash
cp ~/projects/claude_tmux_powerline/claude_usage.sh ~/.config/tmux-powerline/segments/claude_usage.sh
```

**Step 2: Push to GitHub**

```bash
git push origin main
```
