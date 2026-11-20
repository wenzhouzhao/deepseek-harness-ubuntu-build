# 已知问题与排障

命令默认在**本工具仓库根目录**执行；上游源码用 `$DSH_SRC` 表示
（默认 `../deepseek-harness`）。

---

## 1. `git fetch` 报 GnuTLS / unexpected disconnect

```
error: RPC 失败。curl 56 GnuTLS recv error (-9): Error decoding the received TLS packet.
fatal: 过早的文件结束符（EOF）
```

原因：完整 history 的 pack 较大，网络/代理下 TLS 连接容易中途断开。

`scripts/sync-upstream.sh` 已内置浅拉取 + HTTP/1.1：

```sh
git -C "$DSH_SRC" -c http.version=HTTP/1.1 fetch --depth=1 origin master
```

仍失败时重试一次；或改用源码 tarball：

```sh
curl -L -o /tmp/dsh.tar.gz \
  https://codeload.github.com/deepseek-ai/deepseek-harness/tar.gz/refs/heads/master
```

---

## 2. `prepare:dsh` 失败：`bundled pnpm plugin installation failed ... "restartReason":"no-hmr"`

```
Error: desktop runtime: bundled pnpm plugin installation failed:
{"stage":"enable",...,"application":"restart-required","restartReason":"no-hmr",...}
    at smokeDesktopRuntime (.../smoke-runtime.ts)
```

判定：**不是产物损坏**。上游的 prepared-runtime smoke 断言“新装插件通过 HMR
立即生效”；Linux profile 没有挂载 HMR 服务，`installBundle()` 合法返回
`restart-required / no-hmr`。该 smoke 面向 macOS/Windows 发布目标。

处理：`scripts/build-deb.sh` 默认带 `--defer-runtime-smoke` 跳过它，
改为安装后实际启动验证。设置 `DEFER_RUNTIME_SMOKE=0` 可运行原版 smoke
（会失败）。不要为了“修绿”去改 `smoke-runtime.ts` 的断言。

---

## 3. `sudo` 报 `The "no new privileges" flag is set`

```
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

原因：会话进程树 `NoNewPrivs: 1`（容器、部分 IDE 沙箱），setuid 提权被内核
拒绝，和密码无关。

处理：在普通桌面终端执行安装/回滚命令：

```sh
bash scripts/install-deb.sh dist/deepseek-harness-*.deb
```

检查当前环境：

```sh
grep NoNewPrivs /proc/self/status   # 1 = 该会话无法 sudo
```

---

## 4. `pnpm install` 出现 peer dependency 警告

```
[WARN] Issues with peer dependencies found. Run "pnpm peers check" to list them.
```

上游 workspace 的既有警告，`pnpm install` 退出码仍为 0，不影响构建。
不要为此修改 lockfile 或加 `--no-strict-peer-dependencies`。

---

## 5. 磁盘空间不足

源码 + `node_modules` 约 6 GB，构建目录约 3–4 GB。建议保留 ≥ 12 GB：

```sh
df -h /
du -sh "$DSH_SRC" "$DSH_SRC/apps/desktop/.desktop-build"
```

可清理旧产物目录（先确认新包已复制到 `dist/`）：

```sh
rm -rf "$DSH_SRC/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/linux-unpacked"
```

**不要**删除 `.desktop-build/downloads` 和 `.desktop-build/pnpm-store`：
它们是 Electron/依赖缓存。

---

## 6. 补丁无法应用（`--check` 或构建报 patch 错误）

上游改动了补丁涉及的 6 个文件。处理：

1. 打开 [`PATCHES.md`](PATCHES.md)，逐项对照新代码手工修改
2. 重新生成补丁：

   ```sh
   git -C "$DSH_SRC" diff > patches/linux-x64-support.patch
   ```

3. 再跑 `bash scripts/build-deb.sh --check`
4. 在 `PATCHES.md` 的版本记录里补一行

---

## 7. 图标空白或 `.desktop` 窗口不关联

检查：

```sh
ls "$DSH_SRC/apps/desktop/resources/icons"   # 应有 16/32/48/64/128/256/512
grep -E "StartupWMClass|Icon=" /usr/share/applications/deepseek-harness.desktop
```

修复：删除缺失的图标目录后重新构建（脚本会从 `assets/icons/` 复制）：

```sh
rm -rf "$DSH_SRC/apps/desktop/resources/icons"
bash scripts/build-deb.sh --check
```

补丁里的 `desktopName`、`syncDesktopName`、`icon` 三项共同保证
`app_id` / `WM_CLASS` / `.desktop` 三者一致。

---

## 8. Electron 下载失败

`prepare:runtime` 会从 Electron 官方源下载对应版本（当前 44.7.0）。
失败时保留原始错误，不要关闭 TLS 校验。

- 缓存位置：`$DSH_SRC/apps/desktop/.desktop-build/downloads`
- 重跑构建会复用已下载的压缩包
- 需要代理时只在当前 shell 设置 `HTTPS_PROXY`，不要改全局配置

---

## 9. 安装后应用仍显示旧版本

安装只替换磁盘文件，运行中的 Electron 进程仍持有旧代码；单实例锁会让
再次点击图标只是聚焦旧进程。

```sh
bash scripts/restart-dsh.sh
```

确认没有残留进程：

```sh
pgrep -af "/opt/DeepSeek Harness/deepseek-harness"
```

---

## 10. `dpkg -i` 依赖报错

正常情况依赖已满足。若报缺依赖：

```sh
sudo apt install -f
```

不要用 `--force-depends` 跳过。

---

## 11. 回滚后数据是否受影响

`~/.dsh`（会话、profile、插件、凭据）与 `/opt` 的应用文件分离，
`dpkg -i` 升级/回滚都不会动它。回滚只替换应用本体。

---

## 12. 不要执行的“省事”操作

| 操作 | 后果 |
| --- | --- |
| 在**非专用** checkout 上运行 `sync-upstream.sh --force` | `git reset --hard` 丢掉你的本地修改 |
| 删除 `pnpm-lock.yaml` | 依赖版本漂移，构建不可复现 |
| 关闭 TLS / 跳过 SHA 校验 | 供应链风险 |
| 为了绕过 sudo 限制去改 `/opt` 权限 | 提权问题应换到普通终端解决 |
| 修改 `smoke-runtime.ts` 断言来“修绿” | 掩盖真实差异 |

---

## 13. dsh-purge「应用」报 EACCES：`mkdir '/opt/DeepSeek Harness/resources/app.dshpurge-next'`

原因：Purge 的「应用」要把只读的 `app.asar` 解包成 `resources/app`，
临时目录必须建在 `resources` 下；dpkg 安装的 `/opt/DeepSeek Harness`
属于 `root:root`。

在普通终端执行一次：

```sh
sudo chown -R "$(id -u):$(id -g)" "/opt/DeepSeek Harness"
test -w "/opt/DeepSeek Harness/resources" && echo writable
```

或直接用安装脚本（会同时 `dpkg -i` 和 `chown`）：

```sh
bash scripts/install-deb.sh dist/deepseek-harness-0.2.2-rc.5-linux-amd64-unsigned.deb
```

注意：以后每次 `dpkg -i` 升级，被替换的文件会恢复为 root 所有，需要重新 `chown`。

---

## 14. 右键退出后 `deepseek-harness` 进程仍在

窗口消失但主进程/zygote/host 仍存活；再次点图标不会真正重启。

```sh
pkill -TERM -f "^/opt/DeepSeek Harness/deepseek-harness"
sleep 2
pgrep -af "/opt/DeepSeek Harness/deepseek-harness"   # 应为空
```

或直接用脚本（停止 + 重启）：

```sh
bash scripts/restart-dsh.sh
bash scripts/restart-dsh.sh --no-start   # 只停止
```

`^/opt/...` 锚定命令行开头，避免误杀包含该字符串的 shell/编辑器进程。

---

## 15. dsh-purge 应用后 76/77：补丁 #91 漂移

`diagnose --json` 里：

```json
"drifted": [{
  "id": 91,
  "name": "BROWSER_COOKIE_NAME_IGNORE_PORT",
  "anchors": [{"file": ".../dsh-client-connection/lib/index.js", "reason": "anchor_not_found"}]
}]
```

原因：0.2.2-rc.4 把浏览器会话 cookie 名从
`dsh-client-connection/lib/index.js` 移到了新包
`dsh-host-authentication-token/lib/index.js`；dsh-purge 1.7.20 仍指向旧包。

修复：

```sh
bash plugin-patch/reapply-plugin-patch.sh
# 然后在 Purge 面板点「应用」，再重启
```

脚本只改已安装插件的补丁表（幂等）。插件自动升级会覆盖这处修改，
升级后重新执行一次即可。参考 diff：
`plugin-patch/dsh-purge-0.2.2-rc.4.patch`。

---

## 16. 侧边栏 / Agent Teams 请求 400、WebSocket 握手失败

现象（浏览器控制台，0.2.2-rc.4 + 旧插件）：

```
/sidebar/api/settings.get         400 (empty body)
/sidebar/ws/agent-opens           Connection closed before receiving a handshake response
/plugins/dsh-agent-teams/state    400 (empty body)
```

原因：0.2.2-rc.2 起 Connection 移除了 `requestRejection`（改用
`admit`），并且 `webServer.register` / `registerUpgrade` 默认
`auth: 'required'`。仍调用 `connection.requestRejection(req)` 的插件
（`dsh-better-sidebar` 0.32.1、`@nanmicoder/dsh-agent-teams` 0.1.31）
会在 handler 内抛 TypeError，宿主捕获后统一回空 400；WS upgrade 同理。

修复：

```sh
bash plugin-patch/patch-plugin-auth.sh --check   # 先看是否需要
bash plugin-patch/patch-plugin-auth.sh           # 幂等，自动备份
bash scripts/restart-dsh.sh
```

脚本把两处过期的 fence 改为直接放行。宿主在 handler 之前已完成准入
（未声明 `auth` 的路由默认要求认证），因此不会放宽访问控制。

- 备份：`*.pre-0.2.2-rc.4.bak`（只创建一次）；`--revert` 还原
- 重装/升级插件会覆盖修改，重跑脚本即可
- 上游发布兼容 0.2.2-rc.2+ 的版本后，脚本会检测到锚点不存在并跳过

---

## 17. `dpkg -i` 升级后仍运行旧版本（解包宿主模式）

现象：`dpkg-query` 和包内文件都是新版本，但界面/日志仍是旧版本；
`resources/` 下同时存在新的 `app.asar` 和旧的 `app/` 目录。

原因：Electron 先找 `resources/app/`，再退回 `app.asar`。只要解包目录在，
`dpkg` 新装的 `app.asar` 就不会被加载。

确认：

```sh
node -e 'console.log(require("/opt/DeepSeek Harness/resources/app/package.json").version)'
node -e 'console.log(require("/opt/DeepSeek Harness/resources/app.asar/package.json").version)'
```

处理（用 dsh-purge 自带的解包器，保持补丁流程一致）：

```sh
# 1. 完全退出
bash scripts/restart-dsh.sh --no-start

# 2. 用新 app.asar 重建 resources/app（旧目录保留为 app.dshpurge-prev）
node --input-type=module - <<JS
import { extractAsarToSide, commitExtractedDir } from "$HOME/.dsh/profiles/desktop/node_modules/dsh-purge-community/lib/extract-asar.js";
import fs from "node:fs";
const res = "/opt/DeepSeek Harness/resources";
const r = extractAsarToSide(res + "/app.asar", res + "/app");
console.log("entries:", r.count);
commitExtractedDir(res + "/app", r.next);
console.log("now:", JSON.parse(fs.readFileSync(res + "/app/package.json", "utf8")).version);
JS
```

`<<JS`（不带引号）会让 shell 展开 `$HOME`；若 profile 名不是 `desktop`，
把路径里的 `desktop` 换成实际名称。

3. 重新应用宿主补丁并重启：

```sh
P="$HOME/.dsh/profiles/desktop/node_modules/dsh-purge-community"
DSH_SURFACE=desktop \
DSH_BASE="/opt/DeepSeek Harness/resources/app/dsh/node_modules/@deepseek-ai" \
  node "$P/bin/dsh-purge.js" --apply
bash scripts/restart-dsh.sh
```

确认补丁无待清洗项：

```sh
P="$HOME/.dsh/profiles/desktop/node_modules/dsh-purge-community"
DSH_SURFACE=desktop \
DSH_BASE="/opt/DeepSeek Harness/resources/app/dsh/node_modules/@deepseek-ai" \
  node "$P/bin/dsh-purge.js" --status | grep '补丁'
# 期望：... 已清洗, 0 待清洗
```

`app.dshpurge-prev` 是升级前的完整旧树，确认新版稳定后可删除以释放约
500 MB：

```sh
rm -rf "/opt/DeepSeek Harness/resources/app.dshpurge-prev"
```
