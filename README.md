# 🔐 MidwayBar

macOS 菜单栏 Midway Session 监控工具。像电池图标一样，实时显示 Midway 认证剩余时间。

## 效果

菜单栏显示：`🔐 70%`

点击展开：
```
🟢 Midway Session
─────────────────
  User:       jiasunm
  Auth:       pin + u2f
  Login:      17:33:17
  Expires:    13:33:17
  Remaining:  14h 2m (70%)
  [██████████████░░░░░░]

  ↻ Refresh          ⌘R
  ⌨ Run mwinit -s -o ⌘M
  Quit MidwayBar     ⌘Q
```

颜色：🟢 >50% | 🟡 20-50% | 🔴 <20% 或过期

## 安装

```bash
cd ~/Code/MidwayBar
swift build -c release
cp .build/release/MidwayBar ~/bin/midway-bar
```

## 启动

```bash
midway-bar &
```

## 开机自启

```bash
cp com.neo.midwaybar.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.neo.midwaybar.plist
```

## 工作原理

- 调用 `https://midway-auth.amazon.com/api/session-status` 获取 session 状态
- 读取 `~/.midway/cookie` 进行认证
- 每 60 秒自动刷新
- 只读操作，不修改 session

## 技术栈

- Swift 5.9 + AppKit
- Swift Package Manager
- 无第三方依赖
- 编译后仅 125KB
