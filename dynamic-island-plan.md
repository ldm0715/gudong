# 灵动岛执行计划：Flutter UI + Rust Sidecar

> 状态：草案 v1
> 更新时间：2026-11-17
> 目标平台：Windows 10 / 11
> 技术路线：Flutter（Dart）负责 UI，Rust sidecar 负责系统集成

---

## 1. 目标与边界

### 1.1 目标

做一个每天可以挂着使用、不崩溃的 Windows 灵动岛：

- 微信 / QQ 未读提醒
- SMTC 音乐与歌词
- tab 切换、皮肤、展开/收起动画
- 托盘、全局快捷键、开机自启
- 设置页与本地持久化
- 预留插件协议，但 v1 不做插件市场

### 1.2 MVP 范围（只做这些）

- [ ] 微信 / QQ 未读提醒（任务栏闪烁；可选正文预览）
- [ ] SMTC 媒体控制 + 歌词
- [ ] tab 栏 + 页面显隐/排序
- [ ] 2–3 套皮肤
- [ ] 托盘、全局快捷键、开机自启
- [ ] 设置页、本地配置与凭据存储
- [ ] 插件协议骨架

### 1.3 明确不做（v1 砍掉）

- 邮件 / IMAP
- 日历 / CalDAV / Exchange
- AI 额度
- 天气
- 截图 / OCR
- 剪贴板历史
- 文件置物架
- 多窗口
- 插件市场、签名、审核

### 1.4 性能预算

| 指标 | 预算 |
| --- | --- |
| 空闲总内存（Flutter + sidecar） | ≤ 80MB |
| 空闲 CPU | ≤ 0.5% |
| 动画帧率 | 60fps，p95 帧时间 < 16.7ms |
| 冷启动 | ≤ 1.5s |
| 输入延迟 | ≤ 1 帧 |

测量要求：

- 一律使用 `flutter run --profile` 或 release 包
- 不使用 debug 模式判断性能
- 使用 DevTools（Performance / Memory）+ Windows 任务管理器（CPU / GPU / 私有内存）

### 1.5 时间假设

- 每周投入 20–25 小时：MVP 约 **6–8 周**
- 全职：约 **4–5 周**
- 每周 10 小时：约 **10–12 周**
- 插件化：MVP 之后额外 **2–4 周**

---

## 2. 总体架构

```text
┌──────────────────────────────────────────┐
│ Flutter（Dart）                           │
│  - 岛体绘制、动画、皮肤                    │
│  - tab、设置页、插件模板渲染               │
│  - 纯 UI 状态与交互                        │
└──────────────────┬───────────────────────┘
                   │ stdio JSON-RPC / 命名管道
┌──────────────────▼───────────────────────┐
│ Rust sidecar（island_service.exe）         │
│  - 微信 / QQ 任务栏监听、UIA               │
│  - SMTC 媒体、歌词                         │
│  - 凭据、配置、本地状态                    │
│  - 插件进程管理                            │
└──────────────────┬───────────────────────┘
                   │ JSON-RPC over stdio
┌──────────────────▼───────────────────────┐
│ 插件进程（.exe / .ps1 / Node）            │
└──────────────────────────────────────────┘
```

### 2.1 职责边界

| 放 Flutter | 放 Rust |
| --- | --- |
| 岛体绘制、展开收起、动画、皮肤 | 微信 / QQ 消息捕获、UIA |
| tab、设置页、插件模板渲染 | 媒体会话、歌词同步 |
| 交互状态、过渡效果 | IMAP / 日历 / 网络请求（后续） |
| 纯 UI 逻辑 | 凭据加密、本地数据库 |
| 插件数据的展示 | 插件进程启动、权限、IPC |

原则：

- Flutter 不碰 Win32 / COM / UIA
- Rust 不碰 UI
- 所有需要系统权限或长连接的逻辑放 sidecar

### 2.2 进程生命周期

- Flutter 启动时拉起 sidecar
- `app.hello` 握手，携带协议版本和能力
- 心跳检测；sidecar 崩溃后指数退避重启
- Flutter 退出时确保 sidecar 退出
- 命名互斥量保证单实例

### 2.3 IPC 选型

v1 使用 **stdio JSON-RPC 2.0**，按行收发 JSON：

- 无端口冲突
- 无鉴权问题
- 进程退出即断连，便于调试
- 后续需要多客户端时再升级命名管道 / WebSocket

协议示例：

```json
{"jsonrpc":"2.0","id":1,"method":"media.get","params":{}}
{"jsonrpc":"2.0","id":1,"result":{"title":"...","artist":"...","position":12.3}}
{"jsonrpc":"2.0","method":"event","params":{"type":"wechat.unread","account":"work","count":1}}
```

---

## 3. 阶段计划

### Phase 0：Walking Skeleton（3–5 天）

**目标**：在写业务前验证最容易翻车的平台能力。**Go / No-Go 关口。**

任务：

- [ ] 建 monorepo：`island_app`（Flutter）+ `island_service`（Rust）
- [ ] Flutter 透明、无边框、置顶、跳过任务栏窗口
- [ ] 点击穿透 + 逐像素命中（`win32` FFI，根据光标位置切换 `WS_EX_TRANSPARENT`）
- [ ] 托盘 + 全局快捷键
- [ ] stdio JSON-RPC 最小闭环：`hello` → `event` → Flutter 显示
- [ ] 从已有 Rust 代码中抽出微信任务栏闪烁监听，发送 `wechat.unread`
- [ ] 测基线：空闲内存、空闲 CPU、启动时间、动画帧率

**Gate**：

如果透明窗口、点击穿透、中文 IME、多屏 DPI 中任意一项无法通过，停止堆功能，先换方案。

**交付**：

- 一个能启动、能收到微信事件、能展开收起的 demo
- 一页性能基线数据

---

### Phase 1：骨架（1 周）

任务：

- [ ] Flutter 工程结构：`core/ipc`、`features/island`、`features/messages`、`features/media`、`features/settings`
- [ ] sidecar supervisor：启动、握手、心跳、崩溃退避重启、退出清理、单实例互斥
- [ ] 协议 v1：请求/响应/事件、错误码、`apiVersion`、能力声明
- [ ] 岛体外壳：收起/展开动画、圆角/阴影、拖拽、位置持久化、多屏 DPI
- [ ] 设置页骨架、主题系统
- [ ] 日志与诊断：sidecar 日志、Flutter 日志、崩溃记录

**交付**：

可运行的壳，页面为占位，但窗口 / IPC / 动画 / 托盘稳定。

---

### Phase 2：MVP 功能（2–3 周）

#### Rust sidecar

- [ ] 微信 / QQ：事件驱动监听，闪动后读一次会话列表；支持多开账号
- [ ] 托盘唤起微信
- [ ] SMTC：媒体信息、播放控制、进度、歌词
- [ ] 凭据与配置：Windows Credential Manager / 本地加密
- [ ] 事件合并与节流：媒体进度 1Hz，消息事件去重

#### Flutter

- [ ] 消息 tab：未读列表、联系人、摘要、点击切换微信
- [ ] 媒体 tab：封面、歌名、进度、歌词、播放控制
- [ ] tab 栏 + 页面显隐 / 排序
- [ ] 设置页：功能开关、皮肤、位置、自启、快捷键
- [ ] 性能优化：`RepaintBoundary`、`TickerMode` 暂停、避免全屏透明、避免大面积 `BackdropFilter`

**交付**：

自己愿意每天挂着使用的版本。

---

### Phase 3：打磨与发布（1–2 周）

- [ ] 皮肤与动效打磨，提供“减少动态效果”选项
- [ ] 多屏混合 DPI、任务栏位置、睡眠/唤醒、全屏游戏自动隐藏
- [ ] 中文 IME 回归测试（微软拼音、搜狗）
- [ ] 安装包：MSIX 或 Inno Setup，sidecar 一起打包
- [ ] 自动更新：app + service 原子更新
- [ ] 代码签名；无签名时在文档中说明 SmartScreen 提示
- [ ] 性能复测：内存、CPU、启动、帧率
- [ ] 发布说明、README、已知问题

---

### Phase 4：插件化（可选，MVP 之后 2–4 周）

- [ ] 协议 v2：插件清单、权限、`contributes`
- [ ] 插件进程：`.exe` / `.ps1` / Node，stdio JSON-RPC
- [ ] Flutter 宿主模板：列表、详情、表单、状态条、提示
- [ ] 先写 2–3 个第一方插件验证协议
- [ ] **不做市场、不做签名、不做审核**，等真实第三方需求出现再做
- [ ] 性能约束：插件懒启动、空闲退出、并发上限

---

## 4. 仓库结构

```text
/island_app
  lib/
    core/ipc/          # JSON-RPC 客户端、模型、重连
    features/island/   # 岛体、动画、窗口
    features/messages/
    features/media/
    features/settings/
    features/plugins/  # 模板渲染
  windows/
/island_service
  src/
    main.rs
    ipc/
    wechat/            # 从岛仔移植
    media/             # 从岛仔移植
    plugins/
    state/
/protocol/             # JSON Schema / 文档
/docs/
```

---

## 5. 协议最小集

```text
app.hello            -> { version, capabilities }
media.get            -> { title, artist, position, playing }
media.control        -> { action }
messages.list        -> [{ account, contact, summary, time }]
messages.open        -> { account }
settings.get/set     -> { ... }

event: media.changed
event: message.unread
event: system.power
event: plugin.event
```

约定：

- 每个消息一行 JSON
- `apiVersion` 不兼容时拒绝启动并提示升级
- 事件只推变化，不按帧推数据
- 媒体进度最高 1Hz；微信事件只在闪动时推送
- 事件可合并：50ms 窗口内同类事件合并

---

## 6. 风险清单

| 风险 | 概率 | 应对 |
| --- | --- | --- |
| 透明窗口 / 穿透 / DPI 翻车 | 高 | Phase 0 先验证；过不了就换 WPF 或原生壳 |
| 微信更新导致 UIA 失效 | 高 | 事件驱动 + 版本适配；降级为“有新提醒” |
| sidecar 崩溃 | 中 | supervisor 重启，UI 显示重连 |
| 内存超预算 | 中 | Phase 0 基线 + 每阶段复测；限制插件并发 |
| 范围蔓延 | 高 | 严格按 MVP 砍功能，邮件 / 日历全部后置 |
| 杀软误报 / 签名 | 中 | 两个 exe 都签名；无签名就文档说明 |
| 中文 IME 异常 | 中 | Phase 0 验证；必要时改用原生输入框方案 |
| 插件安全 | 中 | 权限清单、出进程、敏感数据二次确认 |

---

## 7. 第一周具体任务

- [ ] 建 monorepo，Flutter Windows 工程跑起来
- [ ] 透明置顶无边框窗口 + 托盘 + 快捷键
- [ ] Rust sidecar 启动，stdio `hello` 握手
- [ ] 移植微信任务栏闪烁监听，发送 `message.unread`
- [ ] 测基线：空闲内存、CPU、启动、展开动画帧率
- [ ] 写一页 Phase 0 结论：哪些通过、哪些要换方案

---

## 8. 技术选型清单

### Flutter 侧

| 需求 | 方案 |
| --- | --- |
| 无边框、透明、置顶、跳过任务栏 | `window_manager` + `flutter_acrylic` |
| 点击穿透 / 逐像素命中 | `win32` FFI：`WS_EX_LAYERED \| WS_EX_TRANSPARENT` |
| 托盘 | `tray_manager` |
| 全局快捷键 | `hotkey_manager` |
| 开机自启 | `launch_at_startup` |
| 多屏定位 | `screen_retriever` + 自定义 DPI 逻辑 |
| 自动更新 | `auto_updater` / WinSparkle / 自建 |
| 本地存储 | SQLite（`drift` / `sqflite_common_ffi`）或 JSON |

### Rust sidecar

| 需求 | 方案 |
| --- | --- |
| Windows API | `windows` crate |
| 微信 / QQ 监听 | 任务栏闪烁事件 + UIA，参考岛仔 `wechat.rs` |
| 媒体 | SMTC，参考岛仔 `smtc.rs` |
| IPC | `serde_json` + stdin/stdout 行协议 |
| 凭据 | Windows Credential Manager |
| 插件 | 子进程 + JSON-RPC，能力权限 |

### 可复用资产（岛仔，MIT）

- `wechat.rs`：任务栏闪烁、多开账号、托盘唤起、UIA
- `smtc.rs`：Windows 媒体会话、播放器兼容
- `bodian.rs` 等：Windows 私有 API / 内存读取
- 保留版权声明与 MIT 许可

---

## 9. 性能优化清单

### Flutter

- [ ] `RepaintBoundary` 包住动画区域
- [ ] `AnimatedBuilder` 传 `child`，静态子树不重建
- [ ] 多用 `const`，拆小 `build`
- [ ] 避免 `Opacity`，用 `FadeTransition` 或颜色 alpha
- [ ] 避免 `ClipPath`、`saveLayer`；圆角用 `DecoratedBox`
- [ ] 图片设置 `cacheWidth` / `cacheHeight`
- [ ] 字体子集化
- [ ] 收起后 `TickerMode(enabled: false)` 或 `controller.stop()`
- [ ] 页面按需构建，避免 `IndexedStack` 全量 build
- [ ] 窗口大小贴合岛体，不做全屏透明窗口
- [ ] 亚克力 / 模糊只在展开时开启

### Sidecar

- [ ] 事件驱动，避免高频轮询
- [ ] 媒体进度 1Hz，Flutter 本地插值
- [ ] IPC 事件合并与节流
- [ ] 插件懒启动、空闲退出
- [ ] 单插件内存上限与并发上限

---

## 10. 测试矩阵

### 平台

- [ ] Windows 10 22H2
- [ ] Windows 11 最新版
- [ ] 100% / 125% / 150% / 200% DPI
- [ ] 多显示器，混合 DPI
- [ ] 任务栏顶部 / 底部 / 左侧 / 右侧

### 场景

- [ ] 睡眠 / 唤醒
- [ ] 全屏游戏 / 视频
- [ ] 微信 3.x / 4.x / 多开
- [ ] QQ 登录 / 未登录
- [ ] 微软拼音 / 搜狗输入法
- [ ] 杀软 / SmartScreen

### 自动化

- [ ] Rust：协议、状态机、微信事件解析单元测试
- [ ] 协议契约测试：sidecar 模拟 + Flutter 解析
- [ ] Flutter：widget 测试、关键动画 golden 测试
- [ ] 集成冒烟测试：启动 → 握手 → 事件 → 展开 → 退出

---

## 11. 待确认问题

1. 每周能投入多少小时？
2. 插件 host 是 v1 就要，还是 Phase 4 再说？
3. 你写了一半的 Rust 主要是 UI 还是集成逻辑？
   - UI：归档，不移植
   - 集成：抽成 `island_service`，去掉 egui 依赖
4. 是否接受 Flutter 45–70MB 的内存基线？
5. 是否需要代码签名 / 自动更新作为 v1 交付项？

---

## 12. 里程碑总览

| 里程碑 | 内容 | 预计 |
| --- | --- | --- |
| M0 | Walking Skeleton + 性能基线 | 3–5 天 |
| M1 | 窗口 / IPC / 动画 / 托盘稳定 | +1 周 |
| M2 | 微信 + QQ + 媒体 + tab 可用 | +2–3 周 |
| M3 | 打磨 / 打包 / 发布 | +1–2 周 |
| M4 | 插件协议 + 第一方插件 | +2–4 周 |

MVP 完成标准：

- 连续挂机 7 天不崩溃
- 空闲内存 ≤ 80MB，空闲 CPU ≤ 0.5%
- 微信 / QQ 提醒不漏、不重复
- 展开 / 收起动画稳定 60fps
- 多屏、DPI、睡眠唤醒无异常
