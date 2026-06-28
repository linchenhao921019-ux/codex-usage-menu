# Codex 剩余用量菜单栏小组件

一个 macOS 菜单栏小组件，自动读取本机 Codex 会话日志里的 `rate_limits`，显示：

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

工具会扫描：

- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/archived_sessions/**/*.jsonl`

并读取最新的 `payload.rate_limits`。Codex 只有在产生过带用量信息的事件后，本工具才会显示真实百分比。

## iOS 小组件原型

Mac 端启动后会在本机 `8765` 端口提供一份不含本地会话路径的轻量 JSON 快照，供同一 Wi-Fi 下的 iOS App 和 Widget 读取：

- 局域网接口：`http://<Mac 主机名>.local:8765/snapshot`
- 本机调试：`http://127.0.0.1:8765/snapshot`
- iOS 源码：`iOSCompanion/`

当前 iOS 原型默认读取：

```text
http://Mac-mini.local:8765/snapshot
```

Widget 使用 30 分钟 timeline 请求，实际刷新由 iOS 调度；Mac 关机或不在同一网络时会继续显示最后一次成功读取的数据，并在超过 1 小时后标记为旧数据。

Mac 端仍会额外导出一份可见调试副本：

```text
~/Library/Mobile Documents/com~apple~CloudDocs/CodexUsage/codex-usage-snapshot.json
```
