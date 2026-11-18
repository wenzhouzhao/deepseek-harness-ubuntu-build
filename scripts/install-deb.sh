#!/usr/bin/env bash
# Install a built DeepSeek Harness .deb and give the current user write access to
# /opt/DeepSeek Harness (required for dsh-purge to unpack the host).
#
# Run as a normal user: the script calls sudo itself. A NoNewPrivs session
# (containers, some IDE sandboxes) cannot elevate; run it in a normal terminal.
#
# Usage:
#   bash scripts/install-deb.sh [path/to/deepseek-harness-*.deb]
#
# Environment:
#   DSH_APP_DIR   install directory (default: /opt/DeepSeek Harness)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

APP_DIR="${DSH_APP_DIR:-$DEFAULT_APP_DIR}"
DEB=""
for arg in "$@"; do
  case "$arg" in
    --app-dir=*) APP_DIR="${arg#--app-dir=}" ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown argument: $arg" ;;
    *) DEB="$arg" ;;
  esac
done

if [ -z "$DEB" ]; then
  DEB="$(latest_deb "$REPO_ROOT/dist")"
fi
# Fall back to the source checkout's build output when dist/ is empty.
if [ -z "$DEB" ] && [ -n "${DSH_SRC:-}" ] && [ -d "$DSH_SRC/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts" ]; then
  DEB="$(latest_deb "$DSH_SRC/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts")"
fi
[ -n "$DEB" ] && [ -f "$DEB" ] || die "no .deb found; build one first (scripts/build-deb.sh)"

[ -d "$APP_DIR" ] || die "install directory not found: $APP_DIR"

if grep -qE '^NoNewPrivs:[[:space:]]+1' /proc/self/status; then
  echo "error: this session cannot elevate (NoNewPrivs=1 blocks sudo/su)." >&2
  echo "Run the same command in a normal desktop terminal:" >&2
  echo "  bash \"$SCRIPT_DIR/install-deb.sh\" \"$DEB\"" >&2
  exit 4
fi

sudo_run() { sudo "$@"; }

info "installing $(basename "$DEB")"
sudo_run dpkg -i "$DEB"

# Hand the app tree to the invoking user so dsh-purge can create resources/app.
OWNER="$(id -u):$(id -g)"
if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ]; then
  OWNER="$(id -u "$SUDO_USER"):$(id -g "$SUDO_USER")"
fi
info "chown -R $OWNER $APP_DIR"
sudo_run chown -R "$OWNER" "$APP_DIR"

info "result"
dpkg-query -W -f='package=${Version}\n' deepseek-harness
if [ -w "$APP_DIR/resources" ]; then
  echo "resources writable: yes"
else
  echo "resources writable: NO (dsh-purge apply will fail)" >&2
  exit 5
fi
