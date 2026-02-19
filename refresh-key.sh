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
