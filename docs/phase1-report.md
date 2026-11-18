# Phase 1：骨架 报告

状态：代码完成，交互项待人工验收；性能基线已采样，**空闲内存超出预算**。
日期：2026-11-18

## 已实现

### 工程结构

- [x] `core/`：`ipc`、`click_through`、`settings`、`theme`、`window`、`logging`
- [x] `features/`：`island`、`messages`、`weather`、`media`、`diagnostics`、`settings`
- [x] 拆除 `island_view.dart`（1098 行、4 个 tab）与混杂未读 / 天气 / 连接状态的旧 controller
- [x] 布局尺寸与命中区域集中到 `IslandLayout`，点击穿透不再手抄常量

### sidecar supervisor 与协议 v1

- [x] supervisor 只负责启动、握手、心跳、退避重启、退出清理；功能数据由各 feature controller 自己拉取
- [x] `apiVersion` 不匹配进入不可恢复的 `incompatible` 状态，状态灯显示“需升级”，不再无限重启
- [x] 补齐错误码：`-32700` / `-32600` / `-32601` / `-32602` / `-32603` / `-32000`
- [x] `capabilities` 收敛为 sidecar 内唯一常量，`service.ready` 与 `app.hello` 共用
- [x] `settings.get/set` 落盘到 `%APPDATA%\guduo\config.json`，临时文件替换，写盘成功才更新内存
- [x] 首次启动创建配置文件；已有文件损坏时不覆盖

### 单实例与崩溃记录

- [x] sidecar：`Local\guduo-island-service` 命名互斥量，第二实例静默退出
- [x] Flutter：`Local\guduo-island-app` 命名互斥量，第二实例聚焦已有岛体后退出
- [x] 开发热重启不触发单实例退出；debug 下重复启动会在控制台给出中文提示
- [x] Flutter 未捕获异常写入 `crash.log`；Rust panic hook 写入 sidecar 日志（含 backtrace）
- [x] 日志拆分：`app.log` / `crash.log` / `instance.log` / `settings.log`，主日志 1MB 轮换

### 窗口外壳

- [x] 悬浮 700ms 后展开态顶部出现 36×4 拖拽把手，使用 `window_manager.startDragging()` 原生拖动
- [x] 窗口位置按物理像素保存（`GetWindowRect` / `SetWindowPos`），多屏混合 DPI 下不偏移
- [x] 启动恢复时夹到虚拟桌面范围，副屏拔掉后不会留在不可见区域
- [x] 点击穿透的 DPI 换算每帧按客户区宽度重算，随窗口所在屏自动生效

### 主题与设置窗口

- [x] `IslandColors` 改为 `ThemeExtension`，提供 `midnight` / `daylight` 两套皮肤
- [x] 岛体所有硬编码配色迁移到主题 token
- [x] 独立设置窗口（`desktop_multi_window`，880×640 居中），左侧导航 + 右侧卡片内容
- [x] 导航：常规、页面管理、音乐与歌词、专注与饮水、待办与置物、通知/邮箱与日程、AI 额度、天气、关于
- [x] 已实现页面：常规（主题、显示天气）、天气（显示开关、数据说明）、关于（版本、日志目录、配置文件路径）
- [x] 岛体入口：状态灯右侧齿轮 + 托盘“设置”
- [x] 跨窗口保存通过 `WindowMethodChannel`，设置窗口只提交皮肤与功能开关，避免覆盖窗口位置
- [x] 设置窗口尺寸、居中、前台由 Win32 直接处理（子引擎未注册 `window_manager`）
- [x] 设置窗口重复打开时聚焦已有窗口，卸载时随主进程退出

### 诊断

- [x] 诊断页增加客户端版本、sidecar 版本/状态、日志目录与“打开日志目录”
- [x] 连接阶段变化写入 `app.log`（`[sidecar] phase=...`）

## Phase 1 验收清单

逐项做，任一项失败先修再进 Phase 2。

### 1. 启动与连接

- [ ] 启动后状态灯显示“已连接”，诊断页 sidecar 显示版本
- [ ] 手动结束 `island_service.exe`，UI 显示重连中并在 1–2 秒内恢复
- [ ] 临时把 sidecar `API_VERSION` 改为 2：状态灯显示“需升级”，日志只有一次 `launching`

### 2. 岛体交互

- [ ] 悬停展开 / 移出收起，动画与 Phase 0 一致
- [ ] 悬浮约 0.7 秒后顶部出现拖拽条，可拖动窗口
- [ ] 拖到新位置后重启，窗口回到该位置；`config.json` 的 `windowX/Y` 更新
- [ ] 有副屏时拖到副屏，重启仍在副屏
- [ ] 125% / 150% 缩放下，岛体外点击仍能穿透

### 3. 消息与天气

- [ ] 微信 / QQ 新消息出现横幅、边框闪烁，条目可点击打开客户端
- [ ] “全部已读”清空列表
- [ ] 天气 chip 与天气 tab 数据正常

### 4. 设置窗口

- [ ] 点状态灯右侧齿轮打开设置窗口；再点聚焦而不是重复开新窗口
- [ ] 托盘“设置”行为一致
- [ ] 左侧各栏目可切换，占位页正常
- [ ] 切换午夜 / 日光：岛体与设置窗口同时变色
- [ ] 关闭“显示天气”：收起态天气消失，重启保持
- [ ] 关于页可打开日志目录
- [ ] 关闭设置窗口再打开，设置保持；`windowX/Y` 未被覆盖

### 5. 单实例与生命周期

- [ ] 启动第二个 `island_app.exe`：只保留一个进程，已有岛体被叫到前台
- [ ] 同时启动第二个 sidecar：立即退出且不输出协议数据
- [ ] 托盘退出后任务管理器无 `island_app.exe` / `island_service.exe`
- [ ] 连续挂机 1 小时无崩溃、无明显内存增长

## 性能基线

测量条件：Windows 10 22H2、125% 缩放、release 构建、空闲 15 秒采样。

| 指标 | 预算 | 实测 | 结论 |
| --- | --- | --- | --- |
| 空闲内存（private 合计） | ≤ 80MB | 108.3MB（working 111.7MB） | **超标** |
| 空闲 CPU（全核占比） | ≤ 0.5% | 0.061% | 通过 |
| 冷启动到窗口可见 | ≤ 1.5s | 1.399s | 勉强通过 |
| 展开 / 收起 p95 帧时间 | < 16.7ms | 未测 | 待测 |
| 输入延迟 | ≤ 1 帧 | 未测 | 待测 |

进程明细：

| 进程 | working | private |
| --- | --- | --- |
| island_app | 88.7MB | 103.0MB |
| island_service | 22.9MB | 5.3MB |

复测命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\measure-baseline.ps1
```

帧率需要单独测：

```powershell
cd island_app
flutter run --profile -d windows
```

结论：内存超预算约 28MB，是进入 Phase 2 前必须处理的问题；CPU 与冷启动达标。

## Phase 1 已知限制

- 窗口固定 420×300，未做动态贴合岛体尺寸。
- 位置恢复在 sidecar 连接后进行，冷启动可能看到一次位置跳动。
- 设置窗口使用原生标题栏；子引擎无法使用 `window_manager`，最小尺寸未强制。
- 设置页大部分栏目为占位，Phase 2 起逐步接入。
- 媒体仍为占位；`media.get` 只返回不可用。
- 天气和 QQ 通知预览属于 MVP 之外的扩展功能，代码保留但不计入 MVP 验收。
- debug 模式重复启动会直接退出（有控制台提示），这是刻意行为：两个实例共用一个 sidecar 会抢微信监听和快捷键。
- 动画帧率与输入延迟未实测；单实例、拖拽、多屏行为依赖人工验收。

## 本次构建与自测记录

- `cargo test`：13 通过，2 个需要本机环境的用例显式忽略
- `flutter analyze`：无问题
- `flutter test`：10 通过（消息解析、天气解析、设置序列化、主题解析）
- 两端 release 构建通过，sidecar 已复制到 Release 目录
- sidecar 协议冒烟（临时 `APPDATA`）：
  - 非法 JSON 返回 `-32700`
  - 缺 `method` 返回 `-32600`
  - `settings.set` 非对象参数返回 `-32602`
  - 设置合并、落盘、重启读取正常
- 版本不匹配实测：只启动一次 sidecar，`phase=incompatible`，无退避重启
- 单实例实测：sidecar 第二实例 `rc=0`、stdout 为空；Flutter 第二实例退出且只保留一个进程
- 窗口位置恢复实测：`restore 300,50 ok=true`；后续拖拽把位置更新为 `1175,0` 并持久化
- 设置窗口实测：标题、880×640、居中、125% DPI 正常，引擎启动无异常，`settings-crash.log` 为空

## 过程中修复的问题

- `JsonRpcClient` 每条请求调用 `stdin.flush()`，并发请求会同步抛出 `StreamSink is bound to a stream`，导致 5 个 controller 中只有第一个初始拉取成功。已移除多余 flush 并加异常保护。
- 两个进程同时写 `app.log` 会交错覆盖；单实例退出改为写独立的 `instance.log`，重复实例在日志初始化之前退出。

## 下一步

1. **内存优化**：profile 模式拆解 Flutter 引擎、字体资源、插件与常驻控制器的占用，先把空闲内存压回 80MB 以内。
2. **Phase 2**：SMTC 媒体信息与控制、微信 / QQ 事件驱动监听与多开账号、凭据与配置完善、tab 显隐与排序。
3. 补自动化：协议契约测试、单实例与窗口位置的集成冒烟。
