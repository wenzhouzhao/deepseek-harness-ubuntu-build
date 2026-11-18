#!/usr/bin/env bash
# Re-apply the local dsh-purge compatibility fix after a plugin update.
#
# Why: DSH 0.2.2-rc.4 moved the browser-session cookie name from
#   @deepseek-ai/dsh-client-connection/lib/index.js
# to the new package
#   @deepseek-ai/dsh-host-authentication-token/lib/index.js
# dsh-purge 1.7.20 still points patch #91 (BROWSER_COOKIE_NAME_IGNORE_PORT) at the
# old package, so it reports anchor_not_found and leaves 76/77 applied.
#
# This script only edits the installed plugin definition (not the host):
#   - patch #91: file key "client-connection" -> "host-auth-token"
#   - targetFiles(): add the "host-auth-token" mapping
#
# It is idempotent. After running it, click Purge "应用" (or run
# `purge-community apply` with the correct DSH_BASE) and restart DSH.
#
# Usage:
#   bash reapply-plugin-patch.sh [plugin-dir]
set -euo pipefail

PLUGIN="${1:-$HOME/.dsh/profiles/desktop/node_modules/dsh-purge-community}"
ENGINE="$PLUGIN/lib/patches/engine.mjs"
CORE="$PLUGIN/lib/core.js"
[ -f "$ENGINE" ] && [ -f "$CORE" ] || {
  echo "plugin files not found under: $PLUGIN" >&2
  exit 1
}

python3 -I - "$ENGINE" "$CORE" <<'PY'
import sys

engine, core = sys.argv[1], sys.argv[2]

s = open(engine, encoding="utf-8").read()
if 'file: "host-auth-token"' in s:
    print("engine.mjs: already patched")
elif s.count('file: "client-connection"') == 1:
    s = s.replace('file: "client-connection"', 'file: "host-auth-token"')
    open(engine, "w", encoding="utf-8").write(s)
    print("engine.mjs: patch #91 retargeted to host-auth-token")
else:
    raise SystemExit("engine.mjs: unexpected patch definition; inspect manually")

s = open(core, encoding="utf-8").read()
if '"host-auth-token": firstExisting' in s:
    print("core.js: already patched")
else:
    old = '''    "client-connection": firstExisting([
      ...nestedPkg(aiBase, "dsh-client-connection", "lib", "index.js"),
      ...(root ? [path.join(root, "packages", "connection", "client-connection", "lib", "index.js")] : []),
    ]),'''
    new = old + '''
    // 0.2.2-rc.4 moved the browser-session cookie name into this package.
    "host-auth-token": firstExisting([
      ...nestedPkg(aiBase, "dsh-host-authentication-token", "lib", "index.js"),
    ]),'''
    if s.count(old) != 1:
        raise SystemExit("core.js: client-connection mapping changed; inspect manually")
    open(core, "w", encoding="utf-8").write(s.replace(old, new))
    print("core.js: host-auth-token mapping added")
PY

cat <<EOF

Next steps:
  1. Purge -> 状态 -> 应用   (or: purge-community apply with DSH_BASE set)
  2. restart DSH
  3. verify: 77/77 patches, no drifted entries
EOF
