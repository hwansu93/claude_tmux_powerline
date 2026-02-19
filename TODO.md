# TODO

## Known Issues

- **[high]** Session keys expire without warning — no automatic refresh mechanism
  - `claude_usage.sh`

- **[medium]** macOS incompatible — `date -d` is GNU-only, macOS needs `gdate` or `date -j -f`
  - `claude_usage.sh:29`

## Planned Features

- **[high]** macOS support — detect platform and use appropriate date command
  - `claude_usage.sh` (`_format_countdown`)

- **[medium]** Configurable display format — let users choose which components to show (label, bar, percentage, countdown)
  - `claude_usage.sh` (`run_segment`)

- **[medium]** Color-coded output — change bar/percentage color based on usage thresholds (green < 50%, orange < 80%, red >= 80%)
  - `claude_usage.sh` (`run_segment`, `_build_bar`)

- **[low]** Weekly usage display — optional toggle to also show 7-day utilization
  - `claude_usage.sh` (`run_segment`)

- **[low]** Configurable bar length — let users set segment count (default 5)
  - `claude_usage.sh` (`_build_bar`)

## Technical Debt

- **[medium]** Credential reading — reads files on every uncached invocation; could cache credentials in memory with a longer TTL
  - `claude_usage.sh` (`run_segment`)

- **[low]** No install script — manual copy-paste setup; could add a `make install` or shell installer
  - New file: `install.sh` or `Makefile`

## AI-Suggested Improvements

- **[medium]** Notification hook — optional script/command to run when usage crosses a threshold (e.g. 80%), useful for desktop notifications via `notify-send`
- **[medium]** Multi-org support — allow tracking multiple organizations and showing the active one
- **[low]** OAuth token support — use Claude Code's OAuth credentials instead of requiring a separate session key extraction
- **[low]** Sparkle chart — show usage trend over time using a tiny spark line (e.g. `▁▂▃▅▇`)
