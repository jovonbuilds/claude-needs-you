#!/usr/bin/env bash
# Claude Needs You — interactive settings menu
set -euo pipefail

CONFIG_DIR="$HOME/.config/claude-needs-you"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Read current value from config (empty string if missing)
cfg() { jq -r ".$1 // empty" "$CONFIG_FILE" 2>/dev/null || true; }

# Current values (or defaults)
MODE=$(cfg mode); MODE="${MODE:-all}"
SOUND=$(cfg sound); SOUND="${SOUND:-default}"
DELAY=$(cfg delay); DELAY="${DELAY:-5}"
DEBUG=$(cfg debug); DEBUG="${DEBUG:-false}"

save() {
  mkdir -p "$CONFIG_DIR"
  local json="{}"
  [[ "$MODE" != "all" ]] && json=$(printf '%s' "$json" | jq --arg v "$MODE" '.mode = $v')
  [[ "$SOUND" != "default" ]] && json=$(printf '%s' "$json" | jq --arg v "$SOUND" '.sound = $v')
  [[ "$DELAY" != "5" ]] && json=$(printf '%s' "$json" | jq --argjson v "$DELAY" '.delay = $v')
  [[ "$DEBUG" != "false" ]] && json=$(printf '%s' "$json" | jq --argjson v "$DEBUG" '.debug = $v')
  if [[ "$json" == "{}" ]]; then
    rm -f "$CONFIG_FILE"
  else
    local tmp="$CONFIG_FILE.tmp"
    printf '%s\n' "$json" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
  fi
}

show_settings() {
  echo ""
  echo "  Claude Needs You — Settings"
  echo "  ─────────────────────────────"
  echo "  1) mode    $MODE"
  echo "  2) sound   $SOUND"
  echo "  3) delay   ${DELAY}s"
  echo "  4) debug   $DEBUG"
  echo ""
  echo "  s) Save and exit"
  echo "  q) Quit without saving"
  echo ""
}

pick_mode() {
  echo ""
  echo "  Notification mode:"
  echo "  1) all           — notify on everything (default)"
  echo "  2) notification  — only permission prompts, idle, dialogs"
  echo "  3) stop          — only when Claude finishes"
  echo "  4) off           — disable all notifications"
  echo ""
  printf "  Choice [1-4]: "
  read -r choice
  case "$choice" in
    1) MODE="all" ;;
    2) MODE="notification" ;;
    3) MODE="stop" ;;
    4) MODE="off" ;;
    *) echo "  Invalid choice" ;;
  esac
}

pick_sound() {
  echo ""
  echo "  macOS notification sound:"
  echo "  1) default    5) Funk       9) Ping      13) Submarine"
  echo "  2) Basso      6) Glass     10) Pop       14) Tink"
  echo "  3) Blow       7) Hero      11) Purr      15) none (silent)"
  echo "  4) Bottle     8) Morse     12) Sosumi"
  echo ""
  printf "  Choice [1-15]: "
  read -r choice
  case "$choice" in
    1) SOUND="default" ;; 2) SOUND="Basso" ;; 3) SOUND="Blow" ;;
    4) SOUND="Bottle" ;; 5) SOUND="Funk" ;; 6) SOUND="Glass" ;;
    7) SOUND="Hero" ;; 8) SOUND="Morse" ;; 9) SOUND="Ping" ;;
    10) SOUND="Pop" ;; 11) SOUND="Purr" ;; 12) SOUND="Sosumi" ;;
    13) SOUND="Submarine" ;; 14) SOUND="Tink" ;; 15) SOUND="none" ;;
    *) echo "  Invalid choice" ;;
  esac
}

pick_delay() {
  echo ""
  echo "  Seconds to wait before notifying (0 = instant):"
  printf "  Delay [0-30]: "
  read -r choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -le 30 ]]; then
    DELAY="$choice"
  else
    echo "  Invalid — enter a number 0-30"
  fi
}

pick_debug() {
  echo ""
  if [[ "$DEBUG" == "true" ]]; then
    DEBUG="false"
    echo "  Debug OFF"
  else
    DEBUG="true"
    echo "  Debug ON — log at /tmp/claude-needs-you.log"
  fi
}

# Main loop
while true; do
  show_settings
  printf "  Choice: "
  read -r choice
  case "$choice" in
    1) pick_mode ;;
    2) pick_sound ;;
    3) pick_delay ;;
    4) pick_debug ;;
    s|S)
      save
      echo "  Saved to $CONFIG_FILE"
      exit 0
      ;;
    q|Q)
      echo "  No changes saved."
      exit 0
      ;;
    *) echo "  Pick 1-4, s, or q" ;;
  esac
done
