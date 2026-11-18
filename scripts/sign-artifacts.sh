#!/usr/bin/env bash
# Sign the built artifacts with a GPG key.
#
# What this gives you:
#   dist/SHA256SUMS       checksums of every .deb
#   dist/SHA256SUMS.asc   detached GPG signature over the checksum file
#
# Users verify the signature once against your public key, then verify the
# artifacts against the signed checksum file. This proves the package came from
# the holder of the signing key; it does NOT make the app "official DeepSeek".
#
# Optional: --debsigs also embeds an OpenPGP signature inside each .deb
# (`_gpgorigin` member). dpkg does not verify it; it is for inspection and for
# environments that run debsig-verify.
#
# Usage:
#   SIGN_KEY=<key-id-or-email> bash scripts/sign-artifacts.sh [--debsigs]
#
# Key selection:
#   SIGN_KEY unset -> first secret key in the keyring (gpg default)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

KEY="${SIGN_KEY:-}"
USE_DEBSIGS=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --key=*) KEY="${1#--key=}"; shift ;;
    --key)
      [ "$#" -ge 2 ] || die "--key requires a value"
      KEY="$2"; shift 2 ;;
    --debsigs) USE_DEBSIGS=1; shift ;;
    -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v gpg >/dev/null || die "gpg not found (apt install gnupg)"
DIST="$REPO_ROOT/dist"
[ -d "$DIST" ] || die "no dist/ directory; run scripts/build-deb.sh first"

shopt -s nullglob
DEBS=("$DIST"/*.deb)
[ "${#DEBS[@]}" -gt 0 ] || die "no .deb files in $DIST"
shopt -u nullglob

GPG_ARGS=(--batch --yes)
if [ -n "$KEY" ]; then
  GPG_ARGS+=(--local-user "$KEY")
fi

info "writing $DIST/SHA256SUMS"
(cd "$DIST" && sha256sum ./*.deb >SHA256SUMS)

info "signing SHA256SUMS"
gpg "${GPG_ARGS[@]}" --armor --detach-sign \
  --output "$DIST/SHA256SUMS.asc" "$DIST/SHA256SUMS"

info "verify signature"
gpg --verify "$DIST/SHA256SUMS.asc" "$DIST/SHA256SUMS"

if [ "$USE_DEBSIGS" = "1" ]; then
  command -v debsigs >/dev/null || die "debsigs not found (apt install debsigs)"
  for deb in "${DEBS[@]}"; do
    info "debsigs: $(basename "$deb")"
    debsigs --sign=origin ${KEY:+--default-key "$KEY"} "$deb"
  done
fi

info "signed artifacts"
ls -l "$DIST"/SHA256SUMS*
