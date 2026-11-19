#!/usr/bin/env bash
# Re-point two community plugins at the DSH 0.2.2-rc.2+ admission API.
#
# Why: DSH 0.2.2-rc.2 removed Connection.requestRejection and made every
# WebServer route/upgrade require authentication by default. Plugins that still
# call `connection.requestRejection()` now throw inside the route handler; the
# host catches the exception and answers every request with an empty 400
# (WebSocket upgrades fail their handshake the same way).
#
# Symptoms on an affected profile:
#   /sidebar/api/settings.get              -> 400, empty body
#   /sidebar/ws/agent-opens                -> handshake failed
#   /plugins/dsh-agent-teams/state         -> 400, empty body
#
# What this script changes (installed copies only, idempotent):
#   dsh-better-sidebar/lib/index.js        fence() -> always true
#   @nanmicoder/dsh-agent-teams/lib/web-routes.js
#                                          pass routes straight through
#
# Both plugins' own fences are redundant on 0.2.2-rc.2+: the host admits the
# request before the handler runs, and a route without an `auth` field defaults
# to `required`. Removing the stale fence therefore does not weaken access
# control. It only stops the TypeError.
#
# Usage:
#   bash plugin-patch/patch-plugin-auth.sh            # patch
#   bash plugin-patch/patch-plugin-auth.sh --check    # report only
#   bash plugin-patch/patch-plugin-auth.sh --revert   # restore backups
#   bash plugin-patch/patch-plugin-auth.sh --profile=/path/to/profiles/desktop
#
# Backups: <file>.pre-0.2.2-rc.4.bak (created once, never overwritten)
# npm/pnpm reinstalling either plugin restores the upstream file; re-run this.
set -euo pipefail

PROFILE="${DSH_HOME:-$HOME/.dsh}/profiles/desktop"
MODE="patch"
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --revert) MODE="revert" ;;
    --profile=*) PROFILE="${arg#--profile=}" ;;
    -h|--help) sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

SIDEBAR="$PROFILE/node_modules/dsh-better-sidebar/lib/index.js"
TEAMS="$PROFILE/node_modules/@nanmicoder/dsh-agent-teams/lib/web-routes.js"
SIDEBAR_MARK="0.2.2-rc.2+ removed connection.requestRejection"
TEAMS_MARK="performs the admission check before this handler runs"

[ -d "$PROFILE" ] || { echo "profile not found: $PROFILE" >&2; exit 1; }

found=0
for f in "$SIDEBAR" "$TEAMS"; do
  [ -f "$f" ] && found=1
done
if [ "$found" = "0" ]; then
  echo "neither plugin is installed under $PROFILE; nothing to do"
  exit 0
fi

backup() {
  local f="$1"
  [ -f "$f.pre-0.2.2-rc.4.bak" ] || cp -f "$f" "$f.pre-0.2.2-rc.4.bak"
}

check_syntax() {
  command -v node >/dev/null || return 0
  node --check "$1"
}

patch_sidebar() {
  local f="$1"
  if grep -qF "$SIDEBAR_MARK" "$f"; then
    echo "already patched: dsh-better-sidebar"
    return
  fi
  if ! grep -qF 'ctx.connection.requestRejection(req)' "$f"; then
    echo "skip: dsh-better-sidebar has no stale fence (already updated upstream?)"
    return
  fi
  if [ "$MODE" = "check" ]; then
    echo "would patch: dsh-better-sidebar"
    return
  fi
  backup "$f"
  python3 - "$f" "$SIDEBAR_MARK" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
mark = sys.argv[2]
old = "\tconst fence = (req) => ctx.connection.requestRejection(req) === void 0;"
new = "\tconst fence = () => true; /* " + mark + "; webServer enforces auth by default */"
s = p.read_text()
if s.count(old) != 1:
    raise SystemExit("anchor found %d times (expected 1); upstream changed, re-anchor" % s.count(old))
p.write_text(s.replace(old, new))
PY
  check_syntax "$f"
  echo "patched: dsh-better-sidebar"
}

patch_teams() {
  local f="$1"
  if grep -qF "$TEAMS_MARK" "$f"; then
    echo "already patched: dsh-agent-teams"
    return
  fi
  if ! grep -qF 'gate.requestRejection(req)' "$f"; then
    echo "skip: dsh-agent-teams has no stale fence (already updated upstream?)"
    return
  fi
  if [ "$MODE" = "check" ]; then
    echo "would patch: dsh-agent-teams"
    return
  fi
  backup "$f"
  python3 - "$f" "$TEAMS_MARK" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
mark = sys.argv[2]
t = p.read_text()
start = t.index("export function authenticatedWebRoutes(server, connection) {")
end = t.index("\n}", t.index("            });", start)) + 2
new = '''export function authenticatedWebRoutes(server, connection) {
    return {
        register(route) {
            // DSH 0.2.2-rc.2+ removed Connection.requestRejection and makes
            // WebServer routes require authentication by default, so the host
            // ''' + mark + '''
            void connection;
            return server.register(route);
        },
    };
}'''
p.write_text(t[:start] + new + t[end:])
PY
  check_syntax "$f"
  echo "patched: dsh-agent-teams"
}

revert_one() {
  local f="$1" name="$2"
  [ -f "$f" ] || return 0
  if [ -f "$f.pre-0.2.2-rc.4.bak" ]; then
    cp -f "$f.pre-0.2.2-rc.4.bak" "$f"
    echo "reverted: $name"
  else
    echo "no backup for $name"
  fi
}

if [ "$MODE" = "revert" ]; then
  revert_one "$SIDEBAR" "dsh-better-sidebar"
  revert_one "$TEAMS" "dsh-agent-teams"
else
  [ -f "$SIDEBAR" ] && patch_sidebar "$SIDEBAR"
  [ -f "$TEAMS" ] && patch_teams "$TEAMS"
fi

if [ "$MODE" != "check" ]; then
  echo
  echo "Restart the app so the patched server halves load:"
  echo "  bash scripts/restart-dsh.sh"
fi
