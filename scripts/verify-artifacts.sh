#!/usr/bin/env bash
# Verify signed build artifacts before installing.
#
# Usage:
#   bash scripts/verify-artifacts.sh [--debsigs]
#
# Expects dist/SHA256SUMS and dist/SHA256SUMS.asc from sign-artifacts.sh.
# Import the packager's public key first:
#   gpg --import packager-public-key.asc
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

USE_DEBSIGS=0
for arg in "$@"; do
  case "$arg" in
    --debsigs) USE_DEBSIGS=1 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

DIST="$REPO_ROOT/dist"
[ -f "$DIST/SHA256SUMS" ] || die "missing $DIST/SHA256SUMS"
[ -f "$DIST/SHA256SUMS.asc" ] || die "missing $DIST/SHA256SUMS.asc (unsigned build?)"

info "checking signature"
if ! gpg --verify "$DIST/SHA256SUMS.asc" "$DIST/SHA256SUMS"; then
  die "signature verification failed (or the packager's public key is not imported)"
fi

info "checking checksums"
(cd "$DIST" && sha256sum -c SHA256SUMS)

if [ "$USE_DEBSIGS" = "1" ]; then
  command -v debsigs >/dev/null || die "debsigs not found (apt install debsigs)"
  shopt -s nullglob
  for deb in "$DIST"/*.deb; do
    info "debsigs verify: $(basename "$deb")"
    debsigs --verify "$deb"
  done
fi

info "artifacts verified"
