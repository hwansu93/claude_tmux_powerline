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
