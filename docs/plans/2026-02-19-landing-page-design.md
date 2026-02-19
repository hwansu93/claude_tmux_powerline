# claude_tmux_powerline Landing Page — Design

## Style: Retro CRT Terminal

Polished retro terminal aesthetic — warm amber phosphor on dark CRT, nostalgic but refined. Distinct from AI Prism (ambient dark + colorful orbs) and Bookmark Sync (light editorial serif).

## Color Palette

- `--bg: #0a0a0a` — near black
- `--text: #e8a94a` — warm amber (primary)
- `--text-dim: #7a6f5a` — dim amber
- `--text-muted: #4a4235` — faint amber
- `--glow: rgba(232, 169, 74, 0.15)` — soft amber halo
- `--green: #4ade80` — green for success/install
- `--red: #ef4444` — red for high usage demo
- `--yellow: #facc15` — yellow for caution demo
- CRT vignette: radial gradient darkening edges

## Typography

- Font: `Space Mono` (monospace, already used in AI Prism)
- All monospace, no serif/sans mixing
- Hero title: 2.5rem, 700 weight
- Body: 0.95rem, 400 weight

## Layout (single HTML file, all CSS embedded)

### 1. CRT Container
- Full viewport wrapper with vignette overlay
- Subtle scan lines (repeating-linear-gradient, ~2px, opacity 0.04)
- SVG noise texture overlay (opacity 0.02) matching AI Prism pattern
- CRT power-on effect on load (brief brightness flash + scale)

### 2. Hero Section
- Terminal prompt: `$ claude_tmux_powerline` typewriter animation
- Tagline types below: `monitor your claude usage. directly in tmux.`
- Blinking cursor (`_`) at end of typing
- Live progress bar demo below: `Claude: 38% ▓▓░░░ ↻2h31m`
  - Animates through color thresholds (amber → yellow → red → back)
  - Bar fills/empties in sync

### 3. Features Section
- 3 feature cards styled as mini terminal windows
- Each has a title bar with `● ● ●` colored dots
- Content in monospace showing the feature:
  1. **Color-coded** — shows the three threshold states
  2. **Live countdown** — shows reset timer ticking
  3. **Auto-detect expired** — shows EXPIRED → refresh-key.sh flow

### 4. Install Section
- Single dark code block
- `$ git clone ... && cd ... && ./install.sh`
- Copy button (amber border) with "Copied!" state change
- Below: `$ ./refresh-key.sh` for credential setup

### 5. Footer
- GitHub link
- Back to dashboard link (matching bonsai_garden_dashboard pattern)
- `built with bash. no dependencies beyond curl and jq.`

## Animations

- **Typewriter**: hero text, ~50ms/char, cursor blinks 0.8s
- **CRT power-on**: 0.4s page load — brightness flash + subtle scaleY(0.98→1)
- **Scan lines**: static CSS overlay, no animation needed
- **Progress bar glow**: 2s breathing pulse (box-shadow amber)
- **Threshold cycle**: 6s loop cycling through orange/yellow/red states
- **Feature cards**: fade-in on scroll (IntersectionObserver)

## Responsive

- Max-width container: 720px centered
- Feature cards stack vertically below 600px
- Install block wraps gracefully
