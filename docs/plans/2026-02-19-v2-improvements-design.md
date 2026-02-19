# claude_tmux_powerline v2 — Design

## Features

### 1. Session key expiration detection + helper script

**Problem:** Session keys expire without warning. The segment shows `err` which is unclear.

**Solution:**
- Detect error responses from the API (distinguish expired key from network failure)
- Show `Claude: EXPIRED ░░░░░` in the status bar when key is invalid
- New `refresh-key.sh` script: interactive helper that walks through re-extraction steps, fetches org list, validates the new key, and writes credential files

### 2. Color-coded output

**Thresholds:**
- 0-74%: Claude orange (color 173) — normal
- 75-84%: Warm yellow (color 178) — caution
- 85%+: Red (color 196) — approaching limit

**Mechanism:** Emit inline tmux `#[fg=colorN]` codes from the segment to override the theme foreground color dynamically.

**Display format:** `Claude: XX% ▓▓░░░ ↻Xh Xm` (colon added after Claude)

### 3. Credential caching

**Problem:** Credential files are read from disk on every tmux refresh (1/sec). Wasteful.

**Solution:** Store credential values in the cache file alongside the API data. Only re-read credential files when the cache expires (every 2 min).

Cache file format (6 lines):
```
<timestamp>
<pct>
<reset_ts>
<session_key>
<org_id>
<status>
```

### 4. Install script

**`install.sh`** — interactive installer:
1. Check dependencies: curl, jq, tmux-powerline installed
2. Copy `claude_usage.sh` to `~/.config/tmux-powerline/segments/`
3. Prompt for session key extraction (with browser instructions)
4. Fetch and list orgs, let user pick
5. Write credential files with `chmod 600`
6. Inject `"claude_usage 238 173"` into user's theme file if not present
7. Print success message with reload instructions

### 5. TODO.md cleanup

Remove all macOS-related items. Update remaining items to reflect completed work.
