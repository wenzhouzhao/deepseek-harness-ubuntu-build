#!/usr/bin/env bash
# Restart DeepSeek Harness cleanly.
#
# The desktop shell does not always exit when its window closes, and Electron's
# single-instance lock then keeps serving the stale process. This stops every
# matching process (TERM, then KILL after a grace period) and starts one fresh
# detached instance.
#
# Usage:
#   bash scripts/restart-dsh.sh              # stop lingering processes and launch
#   bash scripts/restart-dsh.sh --no-start   # only stop
#
# Environment:
#   DSH_APP   executable to run (default: /opt/DeepSeek Harness/deepseek-harness)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

APP="${DSH_APP:-$DEFAULT_APP_EXE}"
START=1
for arg in "$@"; do
  case "$arg" in
    --no-start) START=0 ;;
    --app=*) APP="${arg#--app=}" ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

[ -x "$APP" ] || die "missing executable: $APP"
PATTERN="^$(regex_escape "$APP")"
LOG="${DSH_LAUNCH_LOG:-/tmp/dsh-launch.log}"

info "stopping running instances"
pkill -TERM -f "$PATTERN" 2>/dev/null || true
for _ in $(seq 1 15); do
  pgrep -f "$PATTERN" >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -f "$PATTERN" >/dev/null 2>&1; then
  echo "still alive after 15s; sending SIGKILL" >&2
  pkill -KILL -f "$PATTERN" 2>/dev/null || true
  sleep 1
fi
if pgrep -f "$PATTERN" >/dev/null 2>&1; then
  die "failed to stop the app"
fi
echo "stopped"

if [ "$START" = "0" ]; then
  exit 0
fi

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "no DISPLAY/WAYLAND_DISPLAY; skipping launch (start it from the app menu)" >&2
  exit 0
fi

info "launching $APP"
rm -f "$LOG"
setsid nohup "$APP" >"$LOG" 2>&1 </dev/null &
for _ in $(seq 1 10); do
  sleep 1
  pgrep -f "$PATTERN" >/dev/null 2>&1 && break
done
if ! pgrep -f "$PATTERN" >/dev/null 2>&1; then
  echo "launch failed; log:" >&2
  tail -20 "$LOG" >&2 || true
  exit 5
fi
echo "started (pid $(pgrep -f "$PATTERN" | head -n1)); log: $LOG"
