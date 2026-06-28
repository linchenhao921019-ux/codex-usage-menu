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
