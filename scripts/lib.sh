#!/usr/bin/env bash
# Shared helpers for the DeepSeek Harness Ubuntu build toolkit.
# Sourced by the scripts in this directory; not meant to be executed directly.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_APP_DIR="/opt/DeepSeek Harness"
DEFAULT_APP_EXE="$DEFAULT_APP_DIR/deepseek-harness"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "== $*"; }

# Resolve the DeepSeek Harness source checkout.
# Order: $DSH_SRC, ../deepseek-harness, ./deepseek-harness, ../../deepseek-harness
resolve_dsh_src() {
  local cand
  if [ -n "${DSH_SRC:-}" ]; then
    cand="$DSH_SRC"
  else
    for cand in \
      "$REPO_ROOT/../deepseek-harness" \
      "$REPO_ROOT/deepseek-harness" \
      "$REPO_ROOT/.."; do
      [ -f "$cand/package.json" ] && [ -d "$cand/apps/desktop" ] && break
      cand=""
    done
  fi
  [ -n "${cand:-}" ] || die "DeepSeek Harness source not found. Clone it and set DSH_SRC, e.g.:
  git clone --depth 1 https://github.com/deepseek-ai/deepseek-harness.git ../deepseek-harness
  DSH_SRC=\$PWD/../deepseek-harness bash scripts/build-deb.sh"
  [ -f "$cand/package.json" ] || die "not a source checkout (no package.json): $cand"
  [ -d "$cand/apps/desktop" ] || die "not a DeepSeek Harness checkout (no apps/desktop): $cand"
  (cd "$cand" && pwd -P)
}

# Verify the checkout is the upstream workspace, not an arbitrary Node project.
assert_upstream_src() {
  local src="$1" name
  name="$(node -e 'const fs=require("fs");process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).name||"")' "$src/package.json" 2>/dev/null || true)"
  if [ "$name" != "@deepseek-ai/dsh-root" ]; then
    die "unexpected package name '$name' in $src/package.json (expected @deepseek-ai/dsh-root)"
  fi
}

# Newest .deb in a directory, or empty.
latest_deb() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name '*.deb' -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n1 | cut -d' ' -f2-
}

# Escape a literal string for use as an anchored extended regex (pkill/pgrep -f).
regex_escape() {
  printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}
