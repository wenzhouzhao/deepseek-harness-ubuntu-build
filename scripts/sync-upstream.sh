#!/usr/bin/env bash
# Update the upstream checkout and rebuild the .deb.
#
# DESTRUCTIVE: this discards local changes in DSH_SRC with `git reset --hard`.
# Use a checkout dedicated to packaging. The linux-x64 patches live in this
# repository (patches/linux-x64-support.patch) and are re-applied by the build.
#
# Usage:
#   bash scripts/sync-upstream.sh --force [--ref=master] [--no-build]
#
# Environment:
#   DSH_SRC=/path/to/deepseek-harness   source checkout (else ../deepseek-harness)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

FORCE=0
BUILD=1
REF="${DSH_REF:-master}"
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --no-build) BUILD=0 ;;
    --ref=*) REF="${arg#--ref=}" ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

SRC="$(resolve_dsh_src)"
[ -d "$SRC/.git" ] || die "not a git checkout: $SRC"
assert_upstream_src "$SRC"

if [ "$FORCE" != "1" ]; then
  die "refusing to reset $SRC without --force (local changes would be lost)"
fi

if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
  echo "warning: discarding local changes in $SRC" >&2
  git -C "$SRC" checkout -- .
fi

info "fetching origin/$REF"
if ! git -C "$SRC" -c http.version=HTTP/1.1 fetch --depth=1 origin "$REF"; then
  echo "fetch failed; retrying once" >&2
  sleep 3
  git -C "$SRC" -c http.version=HTTP/1.1 fetch --depth=1 origin "$REF"
fi
git -C "$SRC" reset --hard FETCH_HEAD
info "upstream version: $(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).version)' "$SRC/package.json")"

if [ "$BUILD" = "1" ]; then
  exec bash "$SCRIPT_DIR/build-deb.sh"
fi
info "source updated; build skipped (--no-build)"
