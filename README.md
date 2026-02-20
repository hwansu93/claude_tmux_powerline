# claude_tmux_powerline

![Bash](https://img.shields.io/badge/Bash-Script-blue) ![License](https://img.shields.io/badge/License-MIT-green) ![Status](https://img.shields.io/badge/Status-Active-brightgreen)

A tmux-powerline segment for monitoring Claude AI session usage with progress bar and reset countdown.

## Tech Stack

- Bash
- curl
- jq
- [tmux-powerline](https://github.com/erikw/tmux-powerline)

## Why

If you use Claude Code inside tmux, you want to see your rate limit status without leaving your workflow. This segment polls the claude.ai usage API, caches the result, and renders a compact status with a live countdown to your next reset window.

## Display

```
Claude: 38% ▓▓░░░ ↻2h31m
        │   │     └── reset countdown (live, recalculated every refresh)
        │   └── 5-segment progress bar
        └── 5-hour session utilization
```

Color-coded by usage level:
- **Orange** (0-74%) -- normal usage
- **Yellow** (75-84%) -- approaching limit
- **Red** (85%+) -- near rate limit

## Architecture

```
claude.ai/api/organizations/{org}/usage
        │
        ▼
  curl (every 2 min) ──► cache file (/tmp/)
                              │  (stores: pct, reset_ts, credentials)
                              ▼
                     tmux-powerline calls run_segment()
                              │
                              ▼
                     rebuilds countdown from cached reset timestamp
                              │
                              ▼
                     "#[fg=colour173]Claude: 38% ▓▓░░░ ↻2h31m"
```

**Key design decisions:**

- **Cache-then-render**: API is polled every 120s (configurable). The reset countdown is recalculated from the cached timestamp on every tmux refresh, so it stays accurate without extra API calls.
- **Credential caching**: Session key and org ID are cached alongside API data. Credential files are only read when the cache expires (~every 2 min), not on every tmux refresh (every 1 sec).
- **Graceful degradation**: Network failures fall back to cached data. Missing credentials show `Claude: --% ░░░░░ ↻?`. Expired keys show `Claude: EXPIRED ░░░░░`.
- **Browser-like headers**: The claude.ai API sits behind Cloudflare. Plain curl gets blocked. The segment sends browser User-Agent/Origin/Referer headers to pass through.

## Requirements

- [tmux-powerline](https://github.com/erikw/tmux-powerline)
- `curl`
- `jq`
- A Claude AI Pro/Max subscription with an active session key

## Installation

### Quick Install

```bash
git clone https://github.com/hwansu93/claude_tmux_powerline.git
cd claude_tmux_powerline
./install.sh
```

The installer will:
1. Check dependencies
2. Copy the segment to `~/.config/tmux-powerline/segments/`
3. Add it to your theme file
4. Walk you through credential setup

### Manual Setup

#### 1. Get your credentials

Run the interactive helper:

```bash
./refresh-key.sh
```

Or manually:

**Session key** (from browser cookies):
1. Go to [claude.ai](https://claude.ai) and log in
2. Open DevTools (`F12`) > **Application** > **Cookies** > `https://claude.ai`
3. Copy the `sessionKey` value (starts with `sk-ant-sid...`)

**Organization ID**:
```bash
curl -s \
  -H "Cookie: sessionKey=$(cat ~/.claude-session-key)" \
  -H "User-Agent: Mozilla/5.0" \
  -H "Origin: https://claude.ai" \
  "https://claude.ai/api/organizations" | jq '.[].uuid, .[].name'
```

#### 2. Store credentials

```bash
echo "sk-ant-sid01-YOUR-KEY-HERE" > ~/.claude-session-key
chmod 600 ~/.claude-session-key

echo "your-org-uuid-here" > ~/.claude-org-id
chmod 600 ~/.claude-org-id
```

#### 3. Install the segment

```bash
mkdir -p ~/.config/tmux-powerline/segments
cp claude_usage.sh ~/.config/tmux-powerline/segments/
```

#### 4. Add to your theme

Edit your theme file (e.g. `~/.config/tmux-powerline/themes/default.sh`) and add the segment:

```bash
"claude_usage 238 173"
```

#### 5. Reload tmux

```bash
tmux kill-server && tmux
```

## Configuration

Set these in your tmux-powerline `config.sh` (optional):

| Variable | Default | Description |
|----------|---------|-------------|
| `TMUX_POWERLINE_SEG_CLAUDE_USAGE_UPDATE_PERIOD` | `120` | Seconds between API polls |

## Usage

### Display States

```
Claude: 38% ▓▓░░░ ↻2h31m    normal (orange)
Claude: 78% ▓▓▓▓░ ↻1h12m    caution (yellow)
Claude: 92% ▓▓▓▓▓ ↻47m      high usage (red)
Claude: 0%  ░░░░░ ↻4h59m    fresh session (orange)
Claude: EXPIRED ░░░░░        expired session key (red)
Claude: ERR ░░░░░             API error (red)
Claude: --% ░░░░░ ↻?         missing credentials
```

### Refreshing Expired Keys

Session keys expire periodically. When they do, the segment shows `EXPIRED`. To refresh:

```bash
cd /path/to/claude_tmux_powerline
./refresh-key.sh
```

## Known Limitations

- **Session keys expire** periodically. Run `./refresh-key.sh` to re-extract from claude.ai cookies.
- **Cloudflare**: If Cloudflare changes its bot detection, the browser-header workaround may break.

## License

MIT License - see [LICENSE](LICENSE).
