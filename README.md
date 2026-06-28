# Codex 剩余用量菜单栏小组件

一个 macOS 菜单栏小组件，自动读取 Codex 会话日志里的 `rate_limits`，显示：

- `5 小时` 窗口剩余百分比和重置时间
- `1 周` 窗口剩余百分比和重置日期

## 运行

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

## 开机自启

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

菜单栏默认每 5 秒刷新一次；点击菜单里的“刷新”会立即重新读取最新日志。

可选环境变量：

```bash
CODEX_USAGE_AUTHORITY_HOST=Mac-mini
CODEX_USAGE_SNAPSHOT_URL=http://Mac-mini.local:8765/snapshot
CODEX_USAGE_DISABLE_LOCAL_FALLBACK=1
CODEX_USAGE_REFRESH_SECONDS=5
```

`CODEX_USAGE_DISABLE_LOCAL_FALLBACK=1` 只建议调试使用；正常使用时不要开启，否则外出时 MacBook Air 无法切到本机备用。
`CODEX_USAGE_REFRESH_SECONDS` 可以设为 2 到 300 秒之间的数值。

## iOS 小组件原型

Mac 端启动后会在 `8765` 端口提供一份不含本地会话路径的轻量 JSON 快照，供同一 Wi-Fi 下的 iOS App、Widget 和其他 Mac 读取：

- 局域网接口：`http://<Mac 主机名>.local:8765/snapshot`
- 本机调试：`http://127.0.0.1:8765/snapshot`
- iOS 源码：`iOSCompanion/`

当前 iOS 原型默认按顺序读取：

```text
http://Mac-mini.local:8765/snapshot
http://MacBook-Air.local:8765/snapshot
http://MacBookAir.local:8765/snapshot
```

也就是说：在家时 iPhone 优先读 Mac mini；外出时，如果 iPhone 和 MacBook Air 在同一网络里，iPhone 会读 MacBook Air 提供的本机备用数据。

Widget 使用 30 分钟 timeline 请求，实际刷新由 iOS 调度；Mac 关机或不在同一网络时会继续显示最后一次成功读取的数据，并在超过 1 小时后标记为旧数据。

Mac 端仍会额外导出一份可见调试副本：

```text
~/Library/Mobile Documents/com~apple~CloudDocs/CodexUsage/codex-usage-snapshot.json
```
