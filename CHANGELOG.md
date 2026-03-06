# Changelog

## 1.2.0

- New interactive settings menu with arrow-key navigation and colors — replaces number-based bash menu
- Settings launcher auto-installed at `~/.config/claude-needs-you/settings` on first notification
- All hooks now async — no more blocking Claude Code during delay
- Node.js syntax check added to `check.sh`

## 1.1.0

- Add `delay` setting (default 5s) — waits then re-checks focus before notifying, so you have time to switch over
- Fix `/claude-needs-you` skill to use `disable-model-invocation: true` — settings menu no longer burns tokens
- Fix settings script path for marketplace installs

## 1.0.0

Initial release.

- Native OS notifications for macOS, Linux, and Windows
- Focus detection: per-tab for iTerm2 and Terminal.app, per-app/window for others
- Click-to-focus via `terminal-notifier` on macOS
- Interactive settings menu (`/claude-needs-you`) — no tokens used
- Configurable mode, sound, and debug logging
- Input sanitization for osascript and PowerShell
