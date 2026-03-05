#!/usr/bin/env bash
# Local code review — run before pushing
set -euo pipefail

FAIL=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== ShellCheck ==="
if command -v shellcheck &>/dev/null; then
  shellcheck "$ROOT/scripts/notify.sh" "$ROOT/scripts/check.sh" "$ROOT/scripts/settings.sh" && echo "PASS" || FAIL=1
else
  echo "SKIP (install: brew install shellcheck)"
fi

echo ""
echo "=== JSON validation ==="
for f in .claude-plugin/plugin.json hooks/hooks.json; do
  if jq empty "$ROOT/$f" 2>/dev/null; then
    echo "$f — PASS"
  else
    echo "$f — FAIL"
    FAIL=1
  fi
done

echo ""
echo "=== Smoke tests ==="
run_test() {
  local name="$1" input="$2" env_var="$3"
  if echo "$input" | CLAUDE_NOTIFY="$env_var" bash "$ROOT/scripts/notify.sh"; then
    echo "$name — PASS"
  else
    echo "$name — FAIL"
    FAIL=1
  fi
}

run_test "mode=off exits cleanly" '{"hook_event_name":"Stop"}' "off"
run_test "mode=notification skips Stop" '{"hook_event_name":"Stop"}' "notification"
run_test "mode=stop skips Notification" '{"hook_event_name":"Notification","notification_type":"idle_prompt"}' "stop"
run_test "handles empty input" '{}' "all"
run_test "dedupes permission_prompt" '{"hook_event_name":"Notification","notification_type":"permission_prompt"}' "all"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "All checks passed."
else
  echo "Some checks failed."
  exit 1
fi
