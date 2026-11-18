# Guduo

Windows 顶部的灵动岛：Flutter 负责岛体与动画，Rust sidecar 负责系统集成。当前处于 Phase 0 Walking Skeleton，微信未读与点击穿透已可验证。

## 快速开始

```powershell
# 构建 sidecar + Flutter，并复制 sidecar 到输出目录
powershell -ExecutionPolicy Bypass -File scripts\build.ps1

# 启动
island_app\build\windows\x64\runner\Release\island_app.exe
```

开发时也可以分开跑：

```bash
cd island_service && cargo build --release
cd island_app && flutter run -d windows
```

快捷键 `Ctrl + Alt + Space` 展开 / 收起，托盘右键可退出。

## 当前能力

- 透明、无边框、置顶、跳过任务栏
- 悬停展开 / 移出收起
- 逐像素点击穿透：岛体外点击直达下层窗口
- 托盘与全局快捷键
- 微信未读提醒：任务栏闪动，不显示联系人和内容
- QQ 消息预览：读取 Windows 通知正文，显示联系人和内容
- 点击消息条目打开对应微信 / QQ 并切到前台
- 已查看或忽略通知后自动清除提醒
- 消息 / 媒体 / 诊断三个 tab，诊断页含输入法测试
- 性能基线采集脚本

> 微信 4.x 不使用 Windows 通知中心，因此只显示“微信有未读”，不显示联系人和内容。QQ 需要开启“新消息通知”才能显示预览。

## 文档

- [Phase 0 报告与验收清单](docs/phase0-report.md)
- [Sidecar IPC 协议](protocol/README.md)
- [完整执行计划](dynamic-island-plan.md)
