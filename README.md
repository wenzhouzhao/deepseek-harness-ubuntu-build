# DeepSeek Harness Ubuntu Build

> **Unofficial.** This is a community build toolkit for DeepSeek Harness Desktop on
> Ubuntu / Debian x86_64. It is not affiliated with or endorsed by DeepSeek.
>
> 上游只发布 macOS / Windows 桌面包；Linux 桌面版由这里的补丁和脚本在本地构建。

- 目标运行环境：Ubuntu 24.04 x86_64（同类 Debian 系发行版同理）
- 当前适配：**DeepSeek Harness 0.2.2-rc.4**
- 历史验证：0.2.1-rc.3
- 产物：未签名的 `deepseek-harness-<version>-linux-amd64-unsigned.deb`
- 本仓库只包含补丁、脚本和文档；不包含上游源码

---

## 1. 它做什么

上游 `apps/desktop` 的发布目标只有 `mac-arm64`、`mac-x64`、`win-x64`
（见 `apps/desktop/scripts/package-target.ts`），GitHub Releases 也只提供源码
tag；官网下载页只给 macOS `.dmg` 和 Windows `.exe`。

本工具给上游源码打 6 处小补丁，让 electron-builder 能产出 `linux-x64` 的
`.deb`，并提供安装、回滚、重启脚本。补丁逐项说明见
[docs/PATCHES.md](docs/PATCHES.md)。

---

## 2. 环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | Ubuntu / Debian x86_64（x64 桌面） |
| Node.js | `>= 24.9.0` |
| pnpm | 按上游 `packageManager`（当前 `pnpm@11.28.5`，corepack 会自动使用） |
| git | 用于获取/更新上游源码 |
| 磁盘 | 建议 ≥ 12 GB 可用（源码 + `node_modules` + 构建产物约 6–10 GB） |
| 桌面 | 安装/重启步骤需要图形会话；纯 SSH 可用 `--no-install` 只构建 |
| dpkg | 安装 `.deb` 时使用 |

首次准备：

```sh
# 下载本仓库后，把上游源码放在同级目录
git clone --depth 1 https://github.com/deepseek-ai/deepseek-harness.git ../deepseek-harness
```

也可以放到任意位置，通过 `DSH_SRC` 指定。

---

## 3. 快速开始

```sh
cd deepseek-harness-ubuntu-build

# 只做前置检查：源码身份、Node 版本、补丁能否应用、图标
bash scripts/build-deb.sh --check

# 构建 → 安装 → 修正 /opt 权限 → 重启（默认行为）
bash scripts/build-deb.sh

# 只构建，不安装
bash scripts/build-deb.sh --no-install

# 构建 + 安装，但不自动重启
bash scripts/build-deb.sh --no-start
```

产物会复制到 `dist/`，并打印 SHA256。

### 指定其他源码目录

```sh
DSH_SRC=/path/to/deepseek-harness bash scripts/build-deb.sh
# 或
bash scripts/build-deb.sh --src=/path/to/deepseek-harness
```

脚本会校验 `package.json` 的 `name` 必须是 `@deepseek-ai/dsh-root`，避免误改其他仓库。

### 纯命令行 / SSH 环境

```sh
bash scripts/build-deb.sh --no-install
sudo bash scripts/install-deb.sh dist/deepseek-harness-*.deb
```

---

## 4. 构建流程

`scripts/build-deb.sh` 依次执行：

1. 解析并校验上游源码，检查 Node / pnpm / git
2. 应用 `patches/linux-x64-support.patch`（已应用则跳过；冲突则停止并提示重锚）
3. 缺少 `apps/desktop/resources/icons` 时，从 `assets/icons/` 复制 hicolor 图标
4. `pnpm install --frozen-lockfile`
5. 编译 artifacts、打包 dsh / desktop-host / vendor / native entry
6. 准备 Electron runtime、primary runtime、包集合和 dsh 运行时树
7. `electron-builder --linux --x64` 生成 `.deb`

### 关于 `--defer-runtime-smoke`

上游 `prepare:dsh` 的 smoke 会断言“新装插件通过 HMR 立即生效”。Linux profile
合法返回 `restart-required / no-hmr`，该 smoke 因此失败（产物本身没问题）。
脚本默认跳过它，改为安装后实际启动验证；设置 `DEFER_RUNTIME_SMOKE=0`
可运行原版 smoke。

---

## 5. 脚本一览

| 脚本 | 作用 |
| --- | --- |
| `scripts/build-deb.sh` | 检查/应用补丁并构建；默认安装 + chown + 重启 |
| `scripts/install-deb.sh` | `dpkg -i` + `chown` 当前用户到 `/opt/DeepSeek Harness` |
| `scripts/restart-dsh.sh` | 结束残留进程并启动新实例（`--no-start` 只停止） |
| `scripts/sync-upstream.sh` | `--force` 拉取上游最新 master 并重置源码树，然后重建 |
| `scripts/lib.sh` | 共享函数（源码解析、校验、路径） |

常用环境变量：

| 变量 | 作用 |
| --- | --- |
| `DSH_SRC` | 上游源码路径 |
| `DSH_APP` | 应用可执行文件（默认 `/opt/DeepSeek Harness/deepseek-harness`） |
| `DSH_APP_DIR` | 安装目录（默认 `/opt/DeepSeek Harness`） |
| `DSH_GATE_CONCURRENCY` | 并行构建数（默认 4） |
| `SKIP_BUILD=1` | 复用已编译产物，只重新打包 |
| `DEFER_RUNTIME_SMOKE=0` | 运行上游 smoke（Linux 上会失败，见上） |
| `DSH_REF` | `sync-upstream.sh` 拉取的分支/标签（默认 `master`） |

---

## 6. 安装 / 升级 / 回滚

### 安装或升级

```sh
sudo dpkg -i dist/deepseek-harness-0.2.2-rc.4-linux-amd64-unsigned.deb
sudo chown -R "$(id -u):$(id -g)" "/opt/DeepSeek Harness"
```

或直接使用脚本（推荐，包含 chown）：

```sh
bash scripts/install-deb.sh dist/deepseek-harness-0.2.2-rc.4-linux-amd64-unsigned.deb
```

- 包名固定 `deepseek-harness`，`dpkg -i` 原地升级
- `chown` 是第三方插件（如 dsh-purge）解包宿主的前提
- `~/.dsh`（会话、profile、插件、凭据）不受影响
- 安装后必须退出并重开应用；`scripts/restart-dsh.sh` 会处理残留进程

验证：

```sh
dpkg-query -W -f='${Version}\n' deepseek-harness
dsh --version
```

### 回滚

保留旧 `.deb` 即可原地回滚：

```sh
sudo dpkg -i /path/to/old/deepseek-harness-0.2.1-rc.3-linux-amd64-unsigned.deb
```

### 权限说明（NoNewPrivs）

在容器或某些 IDE 沙箱里，进程树带 `NoNewPrivs: 1`，`sudo`/`su` 会被内核拒绝，
和密码无关。安装步骤请在自己的桌面终端执行；脚本会检测并提示。

---

## 7. 更新上游

```sh
# 警告：会丢弃 DSH_SRC 中的本地修改，请使用专门用于打包的 checkout
bash scripts/sync-upstream.sh --force

# 只更新源码，不构建
bash scripts/sync-upstream.sh --force --no-build
```

脚本使用浅拉取（`--depth=1` + HTTP/1.1）以降低大包传输中断的概率。

上游如果改动了补丁涉及的 6 个文件，`build-deb.sh` 会停止并提示。此时按
[docs/PATCHES.md](docs/PATCHES.md) 手工重锚，然后重新生成补丁：

```sh
git -C "$DSH_SRC" diff > patches/linux-x64-support.patch
```

---

## 8. 验证

1. `dpkg-query` 版本正确
2. `dsh --version` 正确
3. 从应用菜单启动，窗口与工作区正常
4. 直接验证产物内的 CLI：

   ```sh
   U="$DSH_SRC/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/linux-unpacked"
   ELECTRON_RUN_AS_NODE=1 "$U/deepseek-harness" \
     --expose-internals "$U/resources/app.asar/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js" --version
   ```

排障见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

---

## 9. 目录结构

```
deepseek-harness-ubuntu-build/
├── README.md
├── LICENSE                     # MIT（本仓库脚本与补丁）
├── NOTICE.md                   # 上游/插件/图标归属说明
├── .gitignore
├── assets/icons/               # hicolor 图标（16–512），构建时复制到上游
├── patches/
│   └── linux-x64-support.patch # 6 文件补丁（当前适配 0.2.2-rc.4）
├── scripts/
│   ├── build-deb.sh
│   ├── install-deb.sh
│   ├── restart-dsh.sh
│   ├── sync-upstream.sh
│   └── lib.sh
├── plugin-patch/               # 可选：dsh-purge 在 0.2.2-rc.4 上的兼容修正
│   ├── reapply-plugin-patch.sh
│   └── dsh-purge-0.2.2-rc.4.patch
└── docs/
    ├── PATCHES.md
    └── TROUBLESHOOTING.md
```

## 10. 版本记录

| 日期 | 上游版本 | 结果 |
| --- | --- | --- |
| 2026-10-26 | 0.2.1-rc.3 | 构建并安装成功 |
| 2026-11-18 | 0.2.2-rc.4 | 构建成功，77/77 宿主补丁验证通过 |

## 11. 注意

- 产物**未签名**，仅供本机安装；不要当作官方发行包分发
- 上游是 developer preview，接口会变；每次更新后按第 7 节重放补丁并重建
- 本仓库不包含上游源码；请遵守上游 MIT 许可与品牌规范，详见 [NOTICE.md](NOTICE.md)
