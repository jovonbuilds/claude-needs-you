#!/usr/bin/env bash
# Claude Needs You — native OS notifications for Claude Code
# https://github.com/jovonbuilds/claude-needs-you

set -uo pipefail

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
  echo "claude-needs-you: jq is required but not installed (brew install jq / apt install jq)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Configuration: config file with env var overrides
# ---------------------------------------------------------------------------
CONFIG_FILE="$HOME/.config/claude-needs-you/config.json"

# Read from config file (defaults if missing/unreadable)
cfg() { jq -r ".$1 // empty" "$CONFIG_FILE" 2>/dev/null; }

NOTIFY_MODE="${CLAUDE_NOTIFY:-$(cfg mode)}"
NOTIFY_MODE="${NOTIFY_MODE:-all}"

NOTIFY_SOUND="${CLAUDE_NOTIFY_SOUND:-$(cfg sound)}"
NOTIFY_SOUND="${NOTIFY_SOUND:-default}"

NOTIFY_DELAY="${CLAUDE_NOTIFY_DELAY:-$(cfg delay)}"
NOTIFY_DELAY="${NOTIFY_DELAY:-5}"

DEBUG_CFG=$(cfg debug)
DEBUG="${CLAUDE_NOTIFY_DEBUG:-${DEBUG_CFG:-0}}"
[[ "$DEBUG" == "true" ]] && DEBUG="1"

LOG="/tmp/claude-needs-you.log"
log() { [[ "$DEBUG" == "1" ]] && echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

# ---------------------------------------------------------------------------
# Terminal → app name / bundle ID mappings (macOS)
# ---------------------------------------------------------------------------
# TERM_PROGRAM env var → System Events process name
term_to_app_name() {
  case "${TERM_PROGRAM:-}" in
    Apple_Terminal) echo "Terminal" ;;
    iTerm.app)     echo "iTerm2" ;;
    vscode)        echo "Code" ;;
    WarpTerminal)  echo "Warp" ;;
    Ghostty)       echo "Ghostty" ;;
    alacritty)     echo "Alacritty" ;;
    kitty)         echo "kitty" ;;
    Hyper)         echo "Hyper" ;;
    *)             echo "" ;;
  esac
}

# TERM_PROGRAM env var → macOS bundle identifier (for click-to-focus)
term_to_bundle_id() {
  case "${TERM_PROGRAM:-}" in
    Apple_Terminal) echo "com.apple.Terminal" ;;
    iTerm.app)     echo "com.googlecode.iterm2" ;;
    vscode)        echo "com.microsoft.VSCode" ;;
    WarpTerminal)  echo "dev.warp.Warp-Stable" ;;
    Ghostty)       echo "com.mitchellh.ghostty" ;;
    alacritty)     echo "org.alacritty" ;;
    kitty)         echo "net.kovidgoyal.kitty" ;;
    Hyper)         echo "co.zeit.hyper" ;;
    *)             echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# Bootstrap: drop a short launcher at a fixed path so users can just run it
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="${CONFIG_FILE%/*}/settings"
if [[ ! -x "$LAUNCHER" ]] || ! grep -q "$SCRIPT_DIR" "$LAUNCHER" 2>/dev/null; then
  mkdir -p "${CONFIG_FILE%/*}"
  tmp_launcher=$(mktemp "${CONFIG_FILE%/*}/settings.XXXXXX")
  cat > "$tmp_launcher" <<LAUNCHER_EOF
#!/usr/bin/env bash
exec node "$SCRIPT_DIR/settings.mjs" "\$@"
LAUNCHER_EOF
  chmod +x "$tmp_launcher"
  mv "$tmp_launcher" "$LAUNCHER"
fi

# ---------------------------------------------------------------------------
# Read hook input
# ---------------------------------------------------------------------------
INPUT=$(cat)
OS="$(uname -s)"
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
log "=== $EVENT ==="

# ---------------------------------------------------------------------------
# Filter by CLAUDE_NOTIFY mode
# ---------------------------------------------------------------------------
case "$NOTIFY_MODE" in
  off)          exit 0 ;;
  notification) [[ "$EVENT" == "Notification" || "$EVENT" == "PermissionRequest" ]] || exit 0 ;;
  stop)         [[ "$EVENT" == "Stop" ]] || exit 0 ;;
  all)          ;;
  *)            ;;
esac

# ---------------------------------------------------------------------------
# Build title + message
# ---------------------------------------------------------------------------
TITLE=""
MESSAGE=""

case "$EVENT" in
  Notification)
    NOTIF_TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)
    # Dedupe: PermissionRequest hook handles permission_prompt
    [[ "$NOTIF_TYPE" == "permission_prompt" ]] && exit 0

    MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)
    TITLE=$(printf '%s' "$INPUT" | jq -r '.title // empty' 2>/dev/null)
    case "$NOTIF_TYPE" in
      idle_prompt)        TITLE="${TITLE:-Claude is Idle}" ;;
      elicitation_dialog) TITLE="${TITLE:-Input Required}" ;;
      auth_success)       TITLE="${TITLE:-Auth Success}" ;;
      *)                  TITLE="${TITLE:-Claude Needs You}" ;;
    esac
    ;;
  PermissionRequest)
    TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
    TITLE="Permission Needed"
    MESSAGE="Claude wants to use ${TOOL_NAME:-a tool}"
    ;;
  Stop)
    TITLE="Claude is Done"
    LAST_MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
    if [[ -n "$LAST_MSG" ]]; then
      MESSAGE=$(printf '%s' "$LAST_MSG" | tr '\n' ' ' | sed 's/  */ /g')
      [[ ${#MESSAGE} -gt 100 ]] && MESSAGE="${MESSAGE:0:97}..."
    else
      MESSAGE="Claude finished and is waiting for you."
    fi
    ;;
  *) exit 0 ;;
esac

MESSAGE="${MESSAGE:-Claude Code needs your attention.}"

# ---------------------------------------------------------------------------
# Sanitize strings for safe interpolation into osascript / PowerShell
# ---------------------------------------------------------------------------
sanitize_for_applescript() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
sanitize_for_powershell() { printf '%s' "$1" | sed "s/'/''/g"; }

TITLE_AS=$(sanitize_for_applescript "$TITLE")
MESSAGE_AS=$(sanitize_for_applescript "$MESSAGE")
TITLE_PS=$(sanitize_for_powershell "$TITLE")
MESSAGE_PS=$(sanitize_for_powershell "$MESSAGE")

# ---------------------------------------------------------------------------
# Focus detection — skip notification if the Claude tab is already visible
# ---------------------------------------------------------------------------
OUR_TTY=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ') || OUR_TTY=""

terminal_is_focused() {
  case "$OS" in
    Darwin)
      local app_name
      app_name=$(term_to_app_name)
      [[ -z "$app_name" ]] && return 1 # unknown terminal → always notify

      # Check 1: is our terminal app the frontmost app?
      local frontmost
      frontmost=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null) || return 1
      [[ "$frontmost" != "$app_name" ]] && return 1

      # Check 2: is the specific tab with our TTY the active one?
      [[ -z "$OUR_TTY" ]] && return 0 # can't check tab, app is focused = focused
      local active_tty
      case "$app_name" in
        iTerm2)
          active_tty=$(osascript -e 'tell application "iTerm2" to tell current session of current tab of current window to get tty' 2>/dev/null) || return 0
          active_tty=$(basename "$active_tty")
          ;;
        Terminal)
          active_tty=$(osascript -e 'tell application "Terminal" to get tty of selected tab of front window' 2>/dev/null) || return 0
          active_tty=$(basename "$active_tty")
          ;;
        *) return 0 ;; # no tab API — app-level is the best we can do
      esac
      log "TTY ours=$OUR_TTY active=$active_tty"
      [[ "$OUR_TTY" == "$active_tty" ]]
      ;;

    Linux)
      # X11: compare WINDOWID to the focused window
      [[ -z "${WINDOWID:-}" ]] && return 1
      command -v xdotool &>/dev/null || return 1
      local active
      active=$(xdotool getactivewindow 2>/dev/null) || return 1
      [[ "$WINDOWID" == "$active" ]]
      ;;

    MINGW*|MSYS*|CYGWIN*)
      local result
      result=$(powershell.exe -NoProfile -Command "
        Add-Type -Name Win -Namespace Native -MemberDefinition '[DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();[DllImport(\"kernel32.dll\")] public static extern IntPtr GetConsoleWindow();'
        if ([Native.Win]::GetForegroundWindow() -eq [Native.Win]::GetConsoleWindow()) { 'focused' }
      " 2>/dev/null) || return 1
      [[ "$result" == *"focused"* ]]
      ;;

    *) return 1 ;; # unknown OS → always notify
  esac
}

if terminal_is_focused; then
  log "Focused — skipping"
  exit 0
fi

# Grace period: wait, then re-check focus before notifying
if [[ "$NOTIFY_DELAY" -gt 0 ]] 2>/dev/null; then
  log "Waiting ${NOTIFY_DELAY}s before notifying..."
  sleep "$NOTIFY_DELAY"
  if terminal_is_focused; then
    log "Focused after delay — skipping"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Build click-to-focus command (macOS only, used by terminal-notifier)
# ---------------------------------------------------------------------------
build_click_cmd() {
  local safe_tty
  safe_tty=$(sanitize_for_applescript "$OUR_TTY")
  case "${TERM_PROGRAM:-}" in
    iTerm.app)
      echo "osascript -e 'tell application \"iTerm2\"' -e 'activate' -e 'repeat with w in windows' -e 'repeat with t in tabs of w' -e 'repeat with s in sessions of t' -e 'if tty of s ends with \"${safe_tty}\" then' -e 'select t' -e 'tell w to select' -e 'end if' -e 'end repeat' -e 'end repeat' -e 'end repeat' -e 'end tell'"
      ;;
    Apple_Terminal)
      echo "osascript -e 'tell application \"Terminal\"' -e 'activate' -e 'repeat with w in windows' -e 'repeat with t in tabs of w' -e 'if tty of t ends with \"${safe_tty}\" then' -e 'set selected of t to true' -e 'set index of w to 1' -e 'end if' -e 'end repeat' -e 'end repeat' -e 'end tell'"
      ;;
    *)
      # Generic: open by bundle ID or app name
      local bid
      bid=$(term_to_bundle_id)
      if [[ -n "$bid" ]]; then
        echo "open -b '$bid'"
      else
        echo ""
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Send notification
# ---------------------------------------------------------------------------
case "$OS" in
  Darwin)
    if command -v terminal-notifier &>/dev/null; then
      TN_ARGS=(-title "$TITLE" -message "$MESSAGE" -group "claude-needs-you")
      [[ "$NOTIFY_SOUND" != "none" ]] && TN_ARGS+=(-sound "$NOTIFY_SOUND")

      CLICK_CMD=$(build_click_cmd)
      [[ -n "$CLICK_CMD" ]] && TN_ARGS+=(-execute "$CLICK_CMD")

      terminal-notifier "${TN_ARGS[@]}" 2>/dev/null &
      log "Sent via terminal-notifier"
    else
      SOUND_AS=$(sanitize_for_applescript "$NOTIFY_SOUND")
      SOUND_FLAG=""
      [[ "$NOTIFY_SOUND" != "none" ]] && SOUND_FLAG="sound name \"$SOUND_AS\""
      osascript -e "display notification \"$MESSAGE_AS\" with title \"$TITLE_AS\" $SOUND_FLAG" 2>/dev/null &
      log "Sent via osascript"
    fi
    ;;

  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send "$TITLE" "$MESSAGE" 2>/dev/null &
    fi
    ;;

  MINGW*|MSYS*|CYGWIN*)
    powershell.exe -NoProfile -Command "
      [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
      \$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
      \$text = \$template.GetElementsByTagName('text')
      \$text.Item(0).AppendChild(\$template.CreateTextNode('$TITLE_PS')) > \$null
      \$text.Item(1).AppendChild(\$template.CreateTextNode('$MESSAGE_PS')) > \$null
      \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$template)
      [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show(\$toast)
    " 2>/dev/null &
    ;;
esac

exit 0
