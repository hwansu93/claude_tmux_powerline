# claude_tmux_powerline

A [tmux-powerline](https://github.com/erikw/tmux-powerline) segment that displays your Claude AI session usage directly in the tmux status bar.

```
Claude 38% ▓▓░░░ ↻2h31m
       │   │     └── reset countdown (live, recalculated every refresh)
       │   └── 5-segment progress bar
       └── 5-hour session utilization
```

## Why

If you use Claude Code inside tmux, you want to see your rate limit status without leaving your workflow. This segment polls the claude.ai usage API, caches the result, and renders a compact status with a live countdown to your next reset window.

## Architecture

```
claude.ai/api/organizations/{org}/usage
        │
        ▼
  curl (every 2 min) ──► cache file (/tmp/)
                              │
                              ▼
                     tmux-powerline calls run_segment()
                              │
                              ▼
                     rebuilds countdown from cached reset timestamp
                              │
                              ▼
                     "Claude 38% ▓▓░░░ ↻2h31m"
```

**Key design decisions:**

- **Cache-then-render**: API is polled every 120s (configurable). The reset countdown is recalculated from the cached timestamp on every tmux refresh, so it stays accurate without extra API calls.
- **Graceful degradation**: Network failures fall back to cached data. Missing credentials show `Claude --% ░░░░░ ↻?`. API errors show `Claude err ░░░░░`.
- **Browser-like headers**: The claude.ai API sits behind Cloudflare. Plain curl gets blocked. The segment sends browser User-Agent/Origin/Referer headers to pass through.

## Requirements

- [tmux-powerline](https://github.com/erikw/tmux-powerline)
- `curl`
- `jq`
- A Claude AI Pro/Max subscription with an active session key

## Setup

### 1. Get your credentials

**Session key** (from browser cookies):
1. Go to [claude.ai](https://claude.ai) and log in
2. Open DevTools (`F12`) > **Application** > **Cookies** > `https://claude.ai`
3. Copy the `sessionKey` value (starts with `sk-ant-sid...`)

**Organization ID**:
```bash
# After storing your session key (step 2), run:
curl -s \
  -H "Cookie: sessionKey=$(cat ~/.claude-session-key)" \
  -H "User-Agent: Mozilla/5.0" \
  -H "Origin: https://claude.ai" \
  "https://claude.ai/api/organizations" | jq '.[].uuid, .[].name'
```

Pick the UUID for your personal org.

### 2. Store credentials

```bash
echo "sk-ant-sid01-YOUR-KEY-HERE" > ~/.claude-session-key
chmod 600 ~/.claude-session-key

echo "your-org-uuid-here" > ~/.claude-org-id
chmod 600 ~/.claude-org-id
```

### 3. Install the segment

```bash
mkdir -p ~/.config/tmux-powerline/segments
cp claude_usage.sh ~/.config/tmux-powerline/segments/
```

### 4. Add to your theme

Edit your theme file (e.g. `~/.config/tmux-powerline/themes/default.sh`) and add the segment to either `TMUX_POWERLINE_LEFT_STATUS_SEGMENTS` or `TMUX_POWERLINE_RIGHT_STATUS_SEGMENTS`:

```bash
"claude_usage 238 173"
```

The two numbers are background and foreground colors (256-color palette). Adjust to match your theme.

### 5. Reload tmux

```bash
tmux kill-server && tmux
```

## Configuration

Set these in your tmux-powerline `config.sh` (optional):

| Variable | Default | Description |
|----------|---------|-------------|
| `TMUX_POWERLINE_SEG_CLAUDE_USAGE_UPDATE_PERIOD` | `120` | Seconds between API polls |

## Display format

```
Claude 38% ▓▓░░░ ↻2h31m   normal usage
Claude 85% ▓▓▓▓▓ ↻47m     high usage
Claude 0%  ░░░░░ ↻4h59m   fresh session
Claude --% ░░░░░ ↻?        missing credentials
Claude err ░░░░░            API error / expired key
```

## Known limitations

- **Session keys expire** periodically. When they do, the segment shows `err`. Re-extract from claude.ai cookies.
- **Cloudflare**: If Cloudflare changes its bot detection, the browser-header workaround may break.
- **Linux `date -d`**: The countdown uses GNU date's `-d` flag. macOS users would need `gdate` from coreutils (not yet handled).
- The segment reads credentials from disk on every uncached call. This is fast but not ideal for high-security environments.

## License

MIT
