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
