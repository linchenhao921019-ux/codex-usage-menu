# Codex 剩余用量菜单栏小组件

一个 macOS 菜单栏小组件，自动读取 Codex 会话日志里的 `rate_limits`，显示：

- `5 小时` 窗口剩余百分比和重置时间
- `1 周` 窗口剩余百分比和重置日期

## 安装 macOS App

### 从源码安装

适合从 GitHub 克隆项目，或在本机继续开发：

```bash
chmod +x scripts/*.sh
./scripts/install-macos-app.sh
```

安装后会生成：

```text
/Applications/Codex 用量.app
```

如果当前用户不能写入 `/Applications`，脚本会自动安装到：

```text
~/Applications/Codex 用量.app
```

这个 App 使用和 iOS App 相同的图标。双击 App 会在菜单栏显示用量；登录后也会自动启动。菜单里点击“退出”后，系统不会自动拉起，需要重新打开 App 或重新登录。

### 生成给别人安装的独立 App 包

适合放到 Google Drive 或 GitHub Release 里分享：

```bash
chmod +x scripts/*.sh
./scripts/package-macos-release.sh
```

生成文件：

```text
dist/Codex用量-macOS-universal.zip
dist/Codex用量-macOS-universal.dmg
```

朋友打开 DMG 或解压 zip 后，双击 `install.command` 即可安装并设置开机自启；也可以手动把 `Codex 用量.app` 拖到 Applications。当前发布包是 universal 版本，Apple Silicon 和 Intel Mac 都可以使用。

注意：这个 App 没有上架和 notarize。如果 macOS 阻止打开，请右键 `install.command` 或 App，选择“打开”。朋友的 Mac 也需要已经使用过 Codex，并存在 `~/.codex/sessions` 记录，才会显示真实用量。

## 调试运行

```bash
swift run codex-usage-menu
```

调试数据源：

```bash
swift run codex-usage-menu --json
```

调试 iOS 同步快照：

```bash
swift run codex-usage-menu --sync-json
```

## 兼容旧安装命令

旧脚本现在会转到新版 App 安装流程：

```bash
chmod +x scripts/install-launch-agent.sh
./scripts/install-launch-agent.sh
```

## 字体

小组件会优先使用 Google Sans Code。未安装时会自动回退到系统等宽数字字体。

```bash
brew install --cask font-google-sans-code
```

## 数据来源

默认以 Mac mini 作为优先权威数据源，并允许外出时切到本机备用：

- 在 `Mac-mini` 上运行时，工具会扫描本机 Codex 日志并对外提供快照。
- 在其他 Mac 上运行时，工具默认优先读取 `http://Mac-mini.local:8765/snapshot`。
- 如果 Mac mini 暂时不可达，其他 Mac 会自动读取自己的本机 Codex 日志，并继续在 `8765` 端口提供快照给 iPhone。
- 回到 Mac mini 所在网络后，其他 Mac 会自动恢复为读取 Mac mini 数据。

Mac mini 会扫描：

- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/archived_sessions/**/*.jsonl`

并读取最新的 `payload.rate_limits`。Codex 只有在产生过带用量信息的事件后，本工具才会显示真实百分比。

菜单栏默认每 60 秒刷新一次；点击菜单里的“刷新”会立即重新读取最新日志。

可选环境变量：

```bash
CODEX_USAGE_AUTHORITY_HOST=Mac-mini
CODEX_USAGE_SNAPSHOT_URL=http://Mac-mini.local:8765/snapshot
CODEX_USAGE_DISABLE_LOCAL_FALLBACK=1
CODEX_USAGE_REFRESH_SECONDS=60
CODEX_USAGE_REMOTE_TIMEOUT_SECONDS=1.5
```

`CODEX_USAGE_DISABLE_LOCAL_FALLBACK=1` 只建议调试使用；正常使用时不要开启，否则外出时 MacBook Air 无法切到本机备用。
`CODEX_USAGE_REFRESH_SECONDS` 可以设为 2 到 300 秒之间的数值。
`CODEX_USAGE_REMOTE_TIMEOUT_SECONDS` 控制非 Mac mini 机器等待 Mac mini 的秒数，默认 1.5 秒；Mac mini 不在当前网络时会快速回退本机数据。

## 备份规则

每次在 MacBook Air 或 Mac mini 修改软件后，都按同一套双备份规则保存：

1. 先运行 `./scripts/package-macos-release.sh`，生成最新 macOS 分享安装包。
2. 在 Google Drive 项目目录里保存一份完整 zip 备份，命名为 `Codex用量-最新版完整备份-YYYYMMDD-HHMMSS-GoogleDrive备份.zip`。
3. 把源码和当前可发布安装包提交到 Git，并推送到 GitHub。

`备份/` 目录只用于 Google Drive 完整备份，不提交到 GitHub；GitHub 备份保存源码和 `dist/` 下当前可发布的 zip/dmg。

## iOS 小组件原型

Mac 端启动后会在 `8765` 端口提供一份不含本地会话路径的轻量 JSON 快照，供同一 Wi-Fi 下的 iOS App、Widget 和其他 Mac 读取：

- 局域网接口：`http://<Mac 主机名>.local:8765/snapshot`
- 本机调试：`http://127.0.0.1:8765/snapshot`
- iOS 源码：`iOSCompanion/`

当前 iOS 原型默认按顺序读取：

```text
http://Mac-mini.local:8765/snapshot
http://10.241.1.21:8765/snapshot
http://10.241.1.186:8765/snapshot
http://linchenhaodeMacBook-Air.local:8765/snapshot
http://MacBook-Air.local:8765/snapshot
http://MacBookAir.local:8765/snapshot
```

也就是说：在家时 iPhone 优先读 Mac mini；外出时，如果 iPhone 和 MacBook Air 在同一网络里，iPhone 会读 MacBook Air 提供的本机备用数据。如果 iPhone 同时也不在 MacBook Air 所在局域网里，这个局域网原型无法实时取数，只能显示上次成功读取的数据。

Widget 使用 1 分钟 timeline 请求，实际刷新由 iOS 调度；Mac 关机或不在同一网络时会继续显示最后一次成功读取的数据，并在超过 1 小时后标记为旧数据。

Mac 端仍会额外导出一份可见调试副本：

```text
~/Library/Mobile Documents/com~apple~CloudDocs/CodexUsage/codex-usage-snapshot.json
```
