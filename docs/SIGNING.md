# 签名与校验

Linux 没有 macOS/Windows 那种系统强制代码签名。对 `.deb` 来说，签名能证明
“这个包由某把密钥的持有者打包”，但不能证明它是 DeepSeek 官方发布。

本仓库提供两种实用方案，默认只做第一种。

---

## 1. 默认：SHA256 校验和

每次 `scripts/build-deb.sh` 都会在 `dist/` 生成：

```
deepseek-harness-<version>-linux-amd64-unsigned.deb
SHA256SUMS
```

校验：

```sh
cd dist
sha256sum -c SHA256SUMS
```

这只能发现下载损坏，**不能**证明来源；攻击者如果同时改包和校验和，校验仍会通过。

---

## 2. 推荐：GPG 签名校验和文件

### 2.1 准备密钥（只需一次）

```sh
gpg --full-generate-key          # 建议 ed25519，设置 passphrase
gpg --list-secret-keys --keyid-format long
gpg --armor --export <KEY_ID> > packager-public-key.asc
```

把 `packager-public-key.asc` 发布到仓库 Releases 或 README，并公布指纹：

```sh
gpg --fingerprint <KEY_ID>
```

### 2.2 签名

构建时自动签：

```sh
SIGN_KEY=<KEY_ID> bash scripts/build-deb.sh
```

或对已有的 `dist/` 补签：

```sh
bash scripts/sign-artifacts.sh --key <KEY_ID>
```

产物：

```
dist/SHA256SUMS
dist/SHA256SUMS.asc     # detached, armored
```

如果密钥有 passphrase，gpg 会通过 pinentry 提示；无人值守构建请使用
gpg-agent 缓存或专用签名密钥。

### 2.3 用户校验

```sh
gpg --import packager-public-key.asc
bash scripts/verify-artifacts.sh
```

脚本会先验证 `SHA256SUMS.asc`，再用它校验每个 `.deb`。

---

## 3. 可选：给 `.deb` 内嵌 OpenPGP 签名

需要额外安装 `debsigs`：

```sh
sudo apt install debsigs
bash scripts/sign-artifacts.sh --key <KEY_ID> --debsigs
```

这会在 `.deb` 里加入 `_gpgorigin` 成员。注意：

- `dpkg -i` **不会**校验它
- 只有配置了 `debsig-verify` 策略的环境才会强制校验
- 主要用于审查和“包本身带签名”的完整性展示

`dpkg-sig` 已停止维护，不建议使用。

---

## 4. 如果通过 APT 仓库分发

要让 `apt install` 自动校验，需要签仓库元数据，而不是单个 `.deb`：

```sh
# 在仓库目录下
apt-ftparchive packages pool > Packages
apt-ftparchive release . > Release
gpg --clearsign -o InRelease Release
gpg --armor --detach-sign -o Release.gpg Release
```

用户端：

```sh
sudo install -m 0644 packager-public-key.asc /usr/share/keyrings/dsh-build.asc
echo "deb [signed-by=/usr/share/keyrings/dsh-build.asc] https://example.com/dsh stable main" \
  | sudo tee /etc/apt/sources.list.d/dsh.list
sudo apt update
sudo apt install deepseek-harness
```

仓库服务器（reprepro/aptly/静态托管）不在本工具范围内；本节只说明签名格式。

---

## 5. 边界与威胁模型

| 签名对象 | 能证明 | 不能证明 |
| --- | --- | --- |
| SHA256SUMS | 下载未损坏 | 来源、未被替换 |
| SHA256SUMS.asc | 校验和由该密钥持有者签出 | 密钥未被盗、包内容安全 |
| `.deb` 的 `_gpgorigin` | 包内嵌签名可查验 | `dpkg` 会校验、官方身份 |
| APT `InRelease` | apt 会校验仓库元数据 | 上游应用本身可信 |

补充：

- 本工具构建的是**未签名的 Electron 应用**；Linux 不强制校验应用内部二进制
- 签名密钥应离线保存或至少设置 passphrase；CI 使用专用密钥并限制权限
- 如果你不是 DeepSeek，签名只代表“你的构建”，不要暗示官方背书
