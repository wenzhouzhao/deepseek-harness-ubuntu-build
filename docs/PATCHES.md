# Linux 构建补丁说明

补丁文件：`patches/linux-x64-support.patch`
适用上游：**0.2.2-rc.5**（commit `9c2670d3`）
规模：6 个文件，约 29 行新增 / 13 行删除。

目标：让上游 Desktop 打包流程接受 `linux-x64` 目标，并用 electron-builder
产出可安装的 `.deb`。

`scripts/build-deb.sh` 会自动应用补丁（已应用则跳过）；如果补丁与新的上游
源码不匹配，构建会停止并提示按本文件重锚。

---

## 1. `apps/desktop/cli/dsh`

**作用**：安装后的 CLI 启动脚本在 Linux 上找不到可执行文件。

macOS 的布局是 `Contents/MacOS/DeepSeek Harness`；Linux 的 Electron 可执行文件
直接位于 `resources` 同级目录，名为 `deepseek-harness`。

```sh
# 原
ELECTRON_RUN_AS_NODE=1 exec "$resources/../MacOS/DeepSeek Harness" ...

# 改后
executable="$resources/../MacOS/DeepSeek Harness"
[ -x "$executable" ] || executable="$resources/../deepseek-harness"
ELECTRON_RUN_AS_NODE=1 exec "$executable" ...
```

**维护**：如果上游改了 CLI 启动器结构，只需保证 Linux 分支能找到
`<app>/deepseek-harness`。

---

## 2. `apps/desktop/scripts/desktop-build-paths.mjs`

**作用**：登记 `linux-x64` 为目标，并把目标映射到 `platform: 'linux'`。

```js
// 原
const SUPPORTED_TARGETS = new Set(['mac-arm64', 'mac-x64', 'win-x64'])
// 改后
const SUPPORTED_TARGETS = new Set(['mac-arm64', 'mac-x64', 'win-x64', 'linux-x64'])
```

0.2.2-rc.4 把 `desktopTargetPlatform()` 改成了 map 形式，补丁新增：

```js
'linux-x64': { platform: 'linux', arch: 'x64' },
```

同时把相关 JSDoc 的联合类型补上 `'linux-x64'` / `'linux'`。

**维护**：上游若再次改写这个函数，只需保留
`linux-x64 → { platform: 'linux', arch: 'x64' }` 的映射。

---

## 3. `apps/desktop/scripts/electron-builder-config.mjs`

最关键的一处，包含四个独立改动。

### 3.1 未签名的 Linux 构建跳过更新策略

```js
// 原
const policy = packagesMacOS && unsigned ? undefined : resolveDesktopPolicyEnvironment(env)
// 改后
const policy = (packagesMacOS && unsigned) || (resolvedPlatform === 'linux' && unsigned)
  ? undefined
  : resolveDesktopPolicyEnvironment(env)
```

原因：`resolveDesktopPolicyEnvironment()` 要求打包时提供强制更新策略源站。
Linux 是本地未签名构建，没有该部署配置，必须跳过；否则打包直接报错。
跳过只影响 `dshMandatoryUpdatePolicy` 元数据，不影响应用启动。

### 3.2 .deb 元数据

```js
extraMetadata: {
  // fpm 从打包后的 manifest 读取 homepage
  homepage: 'https://github.com/deepseek-ai/deepseek-harness',
  // Electron 的 app_id/WM_CLASS 取自 desktopName；StartupWMClass 必须一致，
  // 桌面环境才能把运行中的窗口归到这个 .desktop 条目上
  desktopName: 'deepseek-harness.desktop',
  dshDesktopAppId: appId,
  ...
}
```

### 3.3 Linux 目标改为 deb

```js
linux: {
  // 只给一张超大 PNG 会落到 hicolor/index.theme 未声明的大尺寸目录，图标会空白
  icon: fileURLToPath(new URL('../resources/icons', import.meta.url)),
  category: 'Development',
  executableName: 'deepseek-harness',
  maintainer: 'DeepSeek Harness <deepseek-harness@users.noreply.github.com>',
  synopsis: 'DeepSeek Harness desktop shell',
  syncDesktopName: true,
  target: ['deb'],
}
```

说明：

- 上游默认 `target: ['AppImage']`；这里改成 `deb`，便于 `dpkg` 原地升级
- 图标目录由构建脚本保证：缺少 `$DSH_SRC/apps/desktop/resources/icons` 时，
  从本仓库 `assets/icons/` 复制 16/32/48/64/128/256/512 七种尺寸
- `syncDesktopName: true` 让 electron-builder 生成的 `.desktop` 与
  `desktopName` 保持一致

---

## 4. `apps/desktop/scripts/prepare-cli.ts`

**作用**：允许 Linux 平台，并给非 Windows 的 `dsh` 启动脚本加执行位。

```ts
// 原
export function prepareDesktopCli(destination: string, platform: 'darwin' | 'win32'): void {
  ...
  if (platform === 'darwin') chmodSync(command, 0o755)
}
// 改后
export function prepareDesktopCli(destination: string, platform: 'darwin' | 'win32' | 'linux'): void {
  ...
  if (platform !== 'win32') chmodSync(command, 0o755)
}
```

---

## 5. `apps/desktop/scripts/prepare-dsh.ts`

**作用**：Linux 的 Electron 可执行文件路径。

```ts
// 原
const NODE = join(BUILD_PATHS.electron,
  process.platform === 'win32' ? 'electron.exe' : 'Electron.app/Contents/MacOS/Electron')
// 改后
const NODE = join(BUILD_PATHS.electron,
  process.platform === 'win32' ? 'electron.exe'
  : process.platform === 'linux' ? 'electron'
  : 'Electron.app/Contents/MacOS/Electron')
```

---

## 6. `apps/desktop/scripts/prepare-runtime.ts`

**作用**：与上一条相同，用于 `prepareElectron()` 里探测 Electron 内置 Node 版本。

```ts
const executable = join(BUILD_PATHS.electron,
  platform === 'win32' ? 'electron.exe'
  : platform === 'linux' ? 'electron'
  : 'Electron.app/Contents/MacOS/Electron')
```

---

## 不在补丁里、但构建必须存在的文件

### `apps/desktop/resources/icons/`（上游未跟踪）

七张 PNG（约 316 KB），本仓库备份在 `assets/icons/`。构建脚本会在该目录
缺失时自动复制。

### 构建环境变量

`scripts/build-deb.sh` 会设置：

```sh
DSH_DESKTOP_TARGET_PLATFORM=linux
DSH_DESKTOP_TARGET_ARCH=x64
DSH_DESKTOP_UNSIGNED=1
DSH_DESKTOP_APP_ID=com.deepseek.harness
DSH_GATE_CONCURRENCY=4
```

---

## 补丁维护流程

1. 对最新源码执行 `bash scripts/build-deb.sh --check`
2. 如果报 “patch does not apply”，对照本文件逐项检查 6 个文件
3. 手工改好后重新生成补丁：

   ```sh
   git -C "$DSH_SRC" diff > patches/linux-x64-support.patch
   ```

4. 在下面“版本记录”补一行

## 版本记录

| 补丁版本 | 针对上游 | 说明 |
| --- | --- | --- |
| 初版 | 0.2.1-rc.3 / `22ddee3` | 首次加入 Linux 构建支持 |
| 0.2.2-rc.4 / `ca33fd68` | `desktopTargetPlatform` 改为 map；适配新增的 `lib/operation-report-worker.js` 等上游变化 |
| 当前 | 0.2.2-rc.5 / `9c2670d3` | 补丁锚点无变化，直接复用 |
