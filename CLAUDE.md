# Guduo 核心规范（当前生效版）

## 项目概览

Windows 桌面灵动岛。`island_app`（Flutter）负责岛体、动画与设置窗口；`island_service`（Rust）负责系统集成。两端通过 stdio JSON-RPC 2.0 通信，`apiVersion = 1`。当前处于 Phase 2。

## 核心规则

### 1. 架构边界（最高优先级）

- 系统检测、采集、控制、网络、定位、凭据、持久化一律写在 `island_service`；Flutter 只订阅事件并渲染。
- 禁止用 Dart FFI 或平台通道绕过 sidecar 直接读系统状态。
- 判断标准：Win32 / COM / UIA / 注册表 / 系统通知 / 进程 / 网络 → Rust；布局、动画、样式、交互 → Flutter。
- 动手前先确认变更归属；只改展示就只动 `island_app`，只改系统能力就只动 `island_service`。
- 新增能力流程：Rust 实现 → 定义协议 → Flutter 加 controller/订阅 → 渲染。顺序不能反。

### 2. 前后端通信（以 `protocol/README.md` 为准）

- stdio、UTF-8、每行一个 JSON、JSON-RPC 2.0。
- 请求 `{jsonrpc,id,method,params}`；响应同 `id` 返回 `result` 或 `error`；事件 `method:"event"` 且不带 `id`。
- 方法名、事件名、字段名禁止凭记忆写；改动前先读 `protocol/README.md`，改协议先登记文档并同步 `rpc.rs` 的 `CAPABILITIES`，再改两端。
- 不假设字段命名统一：设置键 lowerCamelCase，天气快照 snake_case，以文档为准。
- 事件只推变化；媒体进度 ≤ 1Hz，客户端本地插值；同类事件去重（微信同账号 5 秒内合并）。
- 设置是扁平 JSON，`settings.set` 只合并传入的 key；写盘先临时文件再替换到 `%APPDATA%\guduo\config.json`。
- `apiVersion` 不匹配返回 `-32000`，客户端停在“需升级”，禁止退避重启。
- 请求 5 秒超时；心跳 `app.ping` 每 5 秒，连续 2 次失败重启 sidecar。
- 错误码只用 `-32700/-32600/-32601/-32602/-32603/-32000`。
- stdout 只输出协议；日志只写 `%LOCALAPPDATA%\guduo\logs\island_service.log`；Rust 侧由单一 event-writer 线程写 stdout。

### 3. 构建与验证

- 只改 `island_app/`：不运行 `cargo build`，不运行 `scripts\build.ps1`。用 `flutter analyze` / `flutter test`，需要实机看效果才 `flutter run -d windows`。
- 只改 `island_service/`：只跑 `cargo build --release` 和 `cargo test`。
- 两端都改或要出包：才运行 `powershell -ExecutionPolicy Bypass -File scripts\build.ps1`。
- 前端视觉验证交给用户，只输出检查清单。

### 4. 界面与主题

- 颜色只从 `IslandColors`（ThemeExtension）取，皮肤由 `themeId` 决定（`midnight` / `daylight`）；禁止硬编码色值。
- 交互控件默认只使用 Material 3 组件（`FilledButton` / `OutlinedButton` / `TextButton` / `TextField` / `DropdownMenu` / `Switch` / `Dialog` 等）；禁止再引入 `DropdownButton`、`FlatButton` 等 M2 控件，存量自定义控件在改到时一并收敛。
- 岛体内部受 380×260 尺寸限制的紧凑控件可以自绘，但高度、圆角、字体、配色必须与同屏其他控件一致。
- 窗口透明、无边框、置顶、跳过任务栏；点击穿透按光标逐像素切换 `WS_EX_LAYERED | WS_EX_TRANSPARENT`。
- tab 固定为 `messages` / `translate` / `weather` / `media` / `diagnostics`；顺序与显隐由 `tabOrder` / `hiddenTabs` 驱动，允许全部隐藏。
- 动画区域包 `RepaintBoundary`；收起后停用 Ticker / 动画；避免 `Opacity`、`ClipPath`、`saveLayer` 与大面积 `BackdropFilter`。
- 图片必须指定 `cacheWidth` / `cacheHeight`（封面 104px），image cache 上限 32MB。
- 播放进度用独立 250ms 时钟插值，只重建进度区域，不重建岛体外壳。

### 5. 性能预算

- 空闲 private working set 合计 ≤ 80MB，空闲 CPU ≤ 0.5%，冷启动 ≤ 1.5s，动画 p95 帧时间 < 16.7ms。
- 性能只以 profile / release 包为准，禁止用 debug 模式判断。

## 详细规范（按需加载）

- 协议与字段：@protocol/README.md
- 路线与阶段交付：@dynamic-island-plan.md
- 验收与性能基线：@docs/phase2-report.md

## 常用命令

- `cd island_app && flutter run -d windows` — 开发运行
- `flutter analyze` / `flutter test` — 前端检查与测试
- `cd island_service && cargo build --release` — 单独构建 sidecar
- `cargo test` — sidecar 测试
- `powershell -ExecutionPolicy Bypass -File scripts\build.ps1` — 两端都改或出包时才用
- `powershell -ExecutionPolicy Bypass -File scripts\measure-baseline.ps1` — 性能基线（需先退出应用）

## 文档更新约定

- 修改 `CLAUDE.md` 时执行覆盖修改，严禁追加历史记录。
- 历史变更读 `git log`，禁止写入 `CLAUDE.md` 或 `.claude/rules/`。
