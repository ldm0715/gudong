# Phase 0：Walking Skeleton 报告

状态：代码完成，Windows 交互项待人工验证。
日期：2026-11-17

## 已实现

- [x] monorepo：`island_app`（Flutter）+ `island_service`（Rust）
- [x] Flutter 透明、无边框、置顶、跳过任务栏，启动定位在主屏顶部居中
- [x] 逐像素命中：16ms 轮询光标，岛体外自动加 `WS_EX_TRANSPARENT | WS_EX_LAYERED`
- [x] 托盘：左键展开/收起、右键菜单、显示岛体、退出
- [x] 全局快捷键：`Ctrl + Alt + Space`
- [x] stdio JSON-RPC：`app.hello` → `service.ready` / `system.status` / `message.unread`
- [x] 从岛仔抽出的微信任务栏闪动监听；同一账号 5 秒内合并
- [x] sidecar supervisor：握手、5 秒心跳、崩溃指数退避重启、退出清理
- [x] 诊断页：连接状态、微信监听状态、IME 输入测试
- [x] 性能采集脚本 `scripts/measure-baseline.ps1`

## Gate 验收

逐项做，任一项失败就停功能、先换方案。

### 1. 透明与置顶

- [ ] 岛体外的窗口区域完全透明，能看到桌面/其他窗口
- [ ] 岛体始终在最前，切换前台窗口后仍置顶
- [ ] 任务栏不出现 island_app 图标

### 2. 点击穿透

- [ ] 光标在岛体外时，点击能落到下层窗口（试桌面图标、浏览器）
- [ ] 光标移到岛体上后自动展开；点击能命中岛体（tab、按钮）
- [ ] 展开态下，点击面板外区域能落到下层窗口
- [ ] 快速从外部移入并点击时，第一次点击偶尔穿透属于已知问题

### 3. 中文 IME

- [ ] 展开 → 诊断 → 输入框，用微软拼音输入中文正常
- [ ] 用搜狗输入法输入中文正常，候选框位置正确
- [ ] 输入框获得焦点后，快捷键/托盘仍可用

### 4. 多屏与 DPI

- [ ] 100% / 125% / 150% / 200% 缩放下岛体位置与大小正常
- [ ] 混合 DPI 多显示器下，移动到副屏后点击可命中（Phase 0 窗口固定在主屏，此项标记为已知限制）
- [ ] 任务栏在顶部时，岛体与任务栏不重叠（Phase 3 处理）

### 5. 事件闭环

- [ ] 启动后诊断页显示“微信监听中”
- [ ] 有微信新消息时，收起态出现未读数字、边框闪烁
- [ ] 展开 → 消息页出现对应账号；点右侧勾选后消失
- [ ] 微信在前台查看该账号时不会误报
- [ ] 退出微信后 sidecar 不崩溃

### 6. 生命周期

- [ ] 托盘退出后，任务管理器里 `island_app.exe` 和 `island_service.exe` 都消失
- [ ] 手动结束 `island_service.exe`，UI 显示重连中，并在 1–2 秒后恢复
- [ ] 连续挂机 1 小时无崩溃、无明显内存增长

## 性能基线

先构建，再安静挂机采样：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
powershell -ExecutionPolicy Bypass -File scripts\measure-baseline.ps1
```

帧率需要单独测：

```powershell
cd island_app
flutter run --profile -d windows
```

展开/收起连续操作 10 次，用 DevTools Performance 记录帧时间。

| 指标 | 预算 | 实测 | 结论 |
| --- | --- | --- | --- |
| 空闲内存（总） | ≤ 80MB | 待填 | |
| 空闲 CPU（总，全核占比） | ≤ 0.5% | 待填 | |
| 冷启动到首帧 | ≤ 1.5s | 待填 | |
| 展开/收起 p95 帧时间 | < 16.7ms | 待填 | |
| 输入延迟 | ≤ 1 帧 | 待填 | |

## Phase 0 已知限制

- 窗口固定 420×300，未做动态贴合岛体。
- 微信多开时账号按闪动窗口进程号识别，未做托盘宿主映射；Phase 2 补。
- 点击穿透轮询 16ms，快速移入后立即点击可能穿透一次。
- 启动时 `window_manager.show()` 会切换一次前台焦点。
- 透明效果依赖 DWM accent；如果实测出现不透明色块，Gate 不通过，按计划换 WPF/原生壳。
- 媒体、设置、自启、位置持久化均为占位。
- 单实例互斥、安装包未做。

## 本次构建与自测记录

- `cargo build --release`、`flutter build windows --release` 均通过。
- `flutter analyze` 无问题，`flutter test` 2 项通过。
- sidecar stdio 冒烟测试通过：`app.hello` → `system.status(listening)` → `messages.list` → `app.shutdown`。
- 微信闪动事件链路需要真实微信消息触发，未做自动化注入。

## 下一步

通过 Gate 后进入 Phase 1：工程结构、协议 v1 完整化、岛体外壳动画、设置页骨架、日志与诊断。
