# Sidecar IPC 协议 v1

传输：stdio，UTF-8，每行一个 JSON（JSON-RPC 2.0）。`apiVersion` 当前为 `1`。

## 请求 / 响应

| method | params | result |
| --- | --- | --- |
| `app.hello` | `{apiVersion}` | `{version, apiVersion, capabilities}` |
| `app.ping` | `{}` | `{pong, uptimeMs}` |
| `app.openUrl` | `{url}` | `{ok}`；只接受 `http://` / `https://`，用系统默认浏览器打开 |
| `messages.list` | `{}` | `{items:[Unread], listener:{ok, message}, notifications:{ok, message}}` |
| `messages.seen` | `{id}` / `{source, account}` / `{}`（空对象 = 全部） | `{ok, removed}` |
| `messages.open` | `{id}` 或 `{source, account}` | `{ok, message?}`；成功后客户端切到前台并清除该提醒 |
| `media.get` | `{}` | `{media: MediaSnapshot}` |
| `media.control` | `{action, source?, position?}` | `{ok, message?}`；`action` 为 `toggle` / `next` / `previous` / `seek` |
| `lyrics.get` | `{}` | `{lyrics: LyricsSnapshot \| null, pending}` |
| `weather.get` | `{}` | `{snapshot, status}`；`snapshot` 可能为 `null` |
| `weather.search` | `{query}` | `{places:[PlaceOption]}`；`query` 限 1–80 字符，网络请求在天气线程内执行 |
| `weather.refresh` | `{}` | `{ok}`；立即触发一次实况刷新，结果通过 `weather.updated` 推送 |
| `volume.get` | `{}` | `{volume, muted}`；`volume` 为 0–1 的主音量，未采样前为 `0` / `false` |
| `volume.set` | `{volume}` | `{ok}`；设置主音量并解除静音，结果通过 `volume.changed` 推送 |
| `volume.mute` | `{muted}` | `{ok}`；设置静音状态 |
| `volume.preview` | `{}` | `{ok}`；按当前音量播放一次短提示音，用于拖动结束后的响度反馈 |
| `metrics.get` | `{}` | `{snapshot}`；最近一帧 `MetricsSnapshot`，首次采样完成前为 `null` |
| `ime.get` | `{}` | `{mode}`；`mode` 为 `zh` / `en`，首次采样前为 `null` |
| `translate.run` | `{text, to?, provider?}` | `{text, provider, to, from?}`；`provider` 为 `llm` / `deepl` / `caiyun` / `microsoftFree` / `mymemory`，省略按设置，auto 时按可用凭据选择 |
| `translate.models` | `{baseUrl?, apiKey?}` | `{models:[string]}`；拉取 OpenAI 兼容服务的模型列表，`apiKey` 省略时读已保存的 LLM Key |
| `translate.setSecret` | `{provider, key}` | `{ok, configured}`；`provider` 为 `llm` / `deepl` / `caiyun`，空 `key` 表示删除 |
| `settings.get` | `{}` | `{settings}` |
| `settings.set` | `{settings:{...}}` | `{ok, settings}`；按 key 合并后返回全量设置 |
| `mail.accounts.list` | `{}` | `{accounts:[MailAccount]}`；不含任何密码或令牌 |
| `mail.accounts.add` | `{provider, email, password?, custom?, label?}` | `{account: MailAccount}`；写入账号与凭据后立即返回，连接结果由 `mail.account` 事件推送 |
| `mail.accounts.update` | `{id, label}` | `{account: MailAccount}`；只修改别名，`label` 为空表示清除别名，不影响凭据和连接 |
| `mail.accounts.remove` | `{id}` | `{ok}`；删除账号、凭据和内存缓存 |
| `mail.oauth.begin` | `{provider}` | `{flowId, verificationUri, userCode, expiresIn, interval}`；目前 `provider` 只接受 `microsoft` |
| `mail.oauth.cancel` | `{flowId}` | `{ok}`；停止等待授权 |
| `mail.list` | `{accountId?, limit?, unreadOnly?}` | `{items:[MailSummary], accounts:[MailAccount]}`；只返回内存中最近收取的邮件 |
| `mail.get` | `{id}` | `{item: MailDetail}`；正文已随收信缓存，通常不需要再连服务器 |
| `mail.refresh` | `{accountId?}` | `{ok}`；立即触发一次增量收取 |
| `mail.markSeen` | `{id?, accountId?}` | `{ok, marked, message?}`；传 `id` 只标记该封；传 `accountId` 标记该账号全部未读；都不传处理所有启用账号 |
| `quota.get` | `{}` | `{providers:[QuotaProvider], updatedAtMs}`；返回最近一次快照，未刷新过时为空数组 |
| `quota.refresh` | `{provider?}` | `{ok}`；`provider` 为 `glm` / `deepseek` / `opencode` / `krill` / `newapi:<siteId>`，省略表示全部；结果通过 `quota.updated` 推送 |
| `quota.setSecret` | `{provider, field, value, siteId?}` | `{ok, configured}`；`field` 为 `apiKey`、`cookie`（仅 `opencode`）、`accessToken`（仅 `newapi`）或 `jwt`（仅 `krill`）；`newapi` 必须带 `siteId`；`value` 为空表示删除 |
| `agents.get` | `{}` | `{sessions:[AgentSession], agents:[AgentStatus]}`；返回最近一次本地会话扫描结果 |
| `schedule.list` | `{}` | `{items:[ScheduleItem]}`；按 `atMs` 升序，含已触发条目 |
| `schedule.add` | `{title, atMs}` | `{item:ScheduleItem}`；`title` 1–80 字符，`atMs` 必须晚于当前时间 |
| `schedule.update` | `{id, title?, atMs?}` | `{item:ScheduleItem}`；至少传一个字段，改成未来时间会重置 `fired` |
| `schedule.remove` | `{id}` | `{ok}`；删除后不可恢复 |
| `schedule.clearExpired` | `{}` | `{ok, removed}`；删除所有 `fired=true` 的日程，返回删除数量 |
| `anniversary.list` | `{}` | `{items:[AnniversaryItem]}`；按 `date` 升序 |
| `anniversary.add` | `{title, date}` | `{item:AnniversaryItem}`；`title` 1–80 字符，`date` 为 `YYYY-MM-DD` |
| `anniversary.update` | `{id, title?, date?}` | `{item:AnniversaryItem}`；至少传一个字段 |
| `anniversary.remove` | `{id}` | `{ok}`；删除后不可恢复 |
| `shelf.list` | `{}` | `{items:[ShelfItem]}`；按加入时间倒序 |
| `shelf.add` | `{paths:[string]}` | `{items, added, skipped:[{path, reason}]}`；单次 1–64 个路径，`reason` 为 `missing` / `limit` / `invalid` |
| `shelf.remove` | `{id}` | `{ok}`；只删除中转站条目，不动原文件 |
| `shelf.removeMany` | `{ids:[string]}` | `{ok, removed}`；批量删除条目，不动原文件 |
| `shelf.clear` | `{}` | `{ok, removed}`；清空全部条目 |
| `shelf.reveal` | `{id}` | `{ok}`；在资源管理器中定位原文件 |
| `app.shutdown` | `{}` | `{ok}`，随后进程退出 |

`settings` 是扁平 JSON 对象，当前键：

| key | 类型 | 说明 |
| --- | --- | --- |
| `themeId` | string | 皮肤标识：`midnight`（午夜，默认）/ `daylight`（日光） |
| `showWeather` | bool | 是否在岛体显示天气，默认 `true` |
| `weatherLocationMode` | string | 定位方式：`auto`（默认，按出口 IP）/ `manual`（使用下方坐标） |
| `weatherLocationName` | string | 手动定位的展示名称，如「广州 · 广东省 · 中国」 |
| `weatherLatitude` / `weatherLongitude` | number | 手动定位坐标，`weatherLocationMode=manual` 时生效 |
| `mediaEnabled` | bool | 是否读取 SMTC 媒体会话，默认 `true` |
| `showPlayingIndicator` | bool | 收起态播放时显示音波，默认 `true` |
| `showImeIndicator` | bool | 收起态常驻显示输入法状态，默认 `true` |
| `showImeBanner` | bool | 输入法切换时弹出横幅，默认 `true` |
| `showScheduleIndicator` | bool | 当天有日程时在收起态显示闹钟图标，默认 `true` |
| `tabOrder` | string[] | 岛体 tab 顺序：`messages` / `mail` / `translate` / `weather` / `media` / `quota` / `dashboard` / `schedule` / `diagnostics` |
| `hiddenTabs` | string[] | 隐藏的 tab；允许全部隐藏，此时岛体只显示标题栏与设置入口 |
| `dashboardMetrics` | string[] | 仪表盘显示的指标：`upload` / `download` / `network` / `cpu` / `memory` / `gpu` / `gpuMemory` / `cpuFrequency` / `totalTraffic`；缺省为全部 |
| `islandMetrics` | string[] | 收起态显示的指标，取值同上；缺省为空，最多 2 个，多余项忽略 |
| `translateProvider` | string | 翻译引擎：`auto`（默认）/ `llm` / `deepl` / `caiyun` / `microsoftFree` / `mymemory` |
| `translateBaseUrl` | string | OpenAI 兼容服务的 base URL，默认 `https://api.openai.com/v1` |
| `translateModel` | string | 大模型名称，空表示未配置 |
| `translateTarget` | string | 目标语言，默认 `zh-CN` |
| `translateSource` | string | 源语言，默认 `auto`（自动识别；MyMemory 不支持自动识别时由 sidecar 推断） |
| `translateAutoOrder` | string[] | 自动模式的引擎优先级，默认 `["llm","deepl","caiyun","microsoftFree","mymemory"]`；未知项忽略，缺项补齐 |
| `translateUserPrompt` | string | 额外翻译要求，默认空。填普通文字会拼在默认翻译指令后；含 `{{to}}` / `{{text}}` 时按模板替换 |
| `translateSystemPrompt` | string | 自定义系统提示词，空表示使用内置模板，`{{to}}` 会替换为目标语言名 |
| `translateMyMemoryEmail` | string | MyMemory 可选邮箱，作为 `de` 参数随请求发送；匿名约 5000 字符/天，填写后约 50000 字符/天 |
| `windowX` / `windowY` | number | 窗口左上角屏幕坐标（物理像素），缺省表示按默认位置摆放 |
| `mailPollSeconds` | number | 邮件轮询间隔秒数，默认 `180`，限制在 `60`–`900` |
| `mailTranslateProvider` | string | 邮件翻译使用的服务，默认 `auto`；取值与 `translateProvider` 相同，两者相互独立 |
| `quotaOrder` | string[] | 额度服务顺序：`glm` / `deepseek` / `opencode` / `krill` / `newapi:<siteId>`；未知项忽略，缺项补齐 |
| `hiddenQuotaProviders` | string[] | 隐藏的额度服务；展开面板与收起态都不显示 |
| `quotaGlmRegion` | string | GLM 区域：`global`（Z.ai，默认）/ `bigmodel-cn`（智谱开放平台） |
| `quotaNewApiSites` | object[] | New API 站点列表，见下方 `NewApiSite`；可添加多个，地址为空的站点不参与刷新 |
| `quotaKrillBaseUrl` | string | Krill Code 站点地址，默认 `https://www.krill-code.com` |
| `quotaRefreshSeconds` | number | 额度刷新间隔秒数，默认 `300`，限制在 `60`–`3600` |
| `enabledAgents` | string[] | 需要检测的本地 agent：`claude` / `codex` / `dsh` / `pi` / `omp`；缺省为全部，空数组表示全部关闭 |
| `showAgentIndicator` | bool | 收起态显示运行中的 agent 图标，默认 `true` |
| `showAgentBanner` | bool | agent 回合结束时弹出横幅，默认 `true` |
| `autoCollapseOnMaximized` | bool | 前台窗口最大化时只保留一条横杠，点击横杠显示收起态，默认 `true` |
| `launchAtLogin` | bool | 登录 Windows 后自动启动；写入 HKCU `Software\Microsoft\Windows\CurrentVersion\Run`，启动项指向 sidecar 同目录的 `island_app.exe`。`settings.get` 返回注册表真实状态，不写入 config.json |
| `shelfMaxItems` | number | 中转站条目上限，默认 `100`，限制在 `10`–`500`；达到上限后拒绝新条目，不淘汰旧条目 |
| `shelfViewMode` | string | 中转站默认视图：`list`（列表，默认）/ `grid`（图标网格） |

`NewApiSite`：

```json
{
  "id": "na_lx2k9",
  "name": "",
  "baseUrl": "https://ai.example.com",
  "mode": "account",
  "userId": "1",
  "quotaPerUnit": 0,
  "currencySymbol": ""
}
```

- `id` 由客户端生成并在站点生命周期内保持不变；凭据与额度 id 都用它区分，不能包含空格或斜杠。
- `name` 为空时优先使用站点 `/api/status` 的 `system_name`，取不到再按站点域名显示；`mode` 为 `account`（系统访问令牌 + 用户 ID）或 `token`（API 密钥）。
- `userId` 只在账户模式使用，会作为 `New-Api-User` 请求头发送。
- `quotaPerUnit` 为手动换算比例：1 货币单位 = 多少配额；`0` 表示自动读取 `/api/status`。`/api/status` 被站点前端拦截时用它兜底。
- `currencySymbol` 为手动货币符号：`¥` / `$` / 空（自动）。

`settings.get` 与 `settings.set` 的返回里还会带 `translateLlmKeyConfigured` / `translateDeeplKeyConfigured` / `translateCaiyunKeyConfigured` 三个只读布尔值，以及 `quotaGlmKeyConfigured` / `quotaDeepseekKeyConfigured` / `quotaOpencodeKeyConfigured` / `quotaOpencodeCookieConfigured` / `quotaKrillTokenConfigured`。`quotaNewApiKeyConfigured` 与 `quotaNewApiAccessTokenConfigured` 是只读对象，键为站点 `id`、值为是否已保存。它们不写入 config.json，也不接受写入。

设置落盘到 `%APPDATA%\gudong\config.json`，先写临时文件再替换。`settings.set` 只合并传入的 key，未传的键保持不变；值必须是合法 JSON，空 key 返回 `-32602`。翻译密钥通过 `translate.setSecret` 写入 Windows 凭据管理器（目标名 `gudong/translate/llm`、`gudong/translate/deepl`、`gudong/translate/caiyun`），不落 config.json。额度凭据通过 `quota.setSecret` 写入同一凭据管理器（目标名 `gudong/quota/glm`、`gudong/quota/deepseek`、`gudong/quota/opencode`、`gudong/quota/opencode-cookie`、`gudong/quota/krill`；New API 为 `gudong/quota/newapi/<siteId>` 与 `gudong/quota/newapi/<siteId>/access`）。

`QuotaProvider`：

```json
{
  "id": "glm",
  "label": "GLM",
  "status": "ok",
  "plan": "GLM Coding Pro",
  "windows": [
    {
      "kind": "session",
      "label": "5-hour",
      "usedPercent": 32.0,
      "remainingPercent": 68.0,
      "windowMinutes": 300,
      "resetsAtMs": 1795000000000,
      "showMeter": true
    },
    {
      "kind": "weekly",
      "label": "Weekly",
      "usedPercent": 18.0,
      "remainingPercent": 82.0,
      "windowMinutes": 10080,
      "resetsAtMs": 1795500000000,
      "showMeter": true
    }
  ],
  "updatedAtMs": 1794997775244
}
```

- `id` 为 `glm` / `deepseek` / `opencode` / `krill` / `newapi:<siteId>`；`status` 为 `ok` / `notConfigured` / `unauthorized` / `rateLimited` / `unavailable`。
- `logo` 可选，为站点图标的 data URI；New API 站点优先使用 `/api/status` 返回的 `logo` 地址，其次尝试 `/logo.png`、`/favicon.png`、`/favicon.ico`，缺失时客户端使用内置图标。图片会缩到 64px 后再下发。
- `windows[].kind` 为 `session`（5 小时）/ `weekly` / `monthly` / `billing`；`billing` 用于余额或 MCP 额度。余额窗口没有 `usedPercent`，`showMeter=false`，数值在 `remaining` 与 `currency` 中。
- `resetsAtMs` 是 Unix 毫秒时间戳；缺失表示服务没有提供重置时间。
- GLM 使用 `quotaGlmRegion` 选择 Z.ai 或智谱开放平台，5 小时与周窗口来自 Coding Plan 配额接口；DeepSeek 只有余额；OpenCode 的 API Key 读取 Go 额度，Cookie 额外补充 Zen 余额。
- 每个 `quotaNewApiSites` 条目都会生成一个 `newapi:<siteId>` 额度服务，按站点分别展示。`account` 模式请求 `/api/user/self` 返回账户额度；`token` 模式请求 `/api/usage/token` 返回令牌额度。
- 余额按 `/api/status` 的 `quota_per_unit` 与 `quota_display_type` 换算：`USD` 显示美元、`CNY` 使用 `usd_exchange_rate` 显示人民币、`CUSTOM` 使用自定义符号与汇率、`TOKENS` 显示原始配额。`unlimited_quota` 为真时只显示“无限额度”。
- `/api/status` 不可用或没有 `quota_per_unit` 时，使用站点的 `quotaPerUnit` / `currencySymbol`；两者都为空则显示原始配额。
- Krill Code 使用 `quotaKrillBaseUrl` 与 JWT 请求 `/api/subscription` 读取套餐用量、到期时间，再请求 `/api/credits` 读取余额。`subscriptions` 可能有多项，会逐个生成额度窗口；字段缺失时回退到 `summary` 汇总值。
- New API 返回 401/403 时，`message` 尽量保留服务端原文（例如“access token 无效”或“New-Api-User 与登录用户不匹配”），便于区分令牌错误与用户 ID 不匹配。
- 凭据缺失时返回 `notConfigured` 且 `windows` 为空；凭据失效返回 `unauthorized`，客户端应提示重新填写。
- 刷新间隔由 `quotaRefreshSeconds` 控制，`quota.refresh` 可立即触发一次；单个服务请求失败时只把该服务标记为错误状态并清空其窗口，其他服务不受影响。

`AgentSession`：

```json
{
  "id": "claude",
  "label": "Claude Code",
  "sessionId": "18712d4b-fa3a-47ae-9f25-2b26e30f5140",
  "title": "修复邮件视图返回与复制问题",
  "cwd": "F:\\My_Project\\guduo",
  "state": "running",
  "startedAtMs": 1795226659675,
  "lastActiveAtMs": 1795327374442
}
```

- `id` 为 `claude` / `codex` / `dsh` / `pi` / `omp`；`state` 为 `running` 或 `waiting`（等待授权 / 输入）。
- `title` 优先取 agent 自己写入的标题；没有时退化为首条用户消息或项目目录名。
- 同一 agent 可以有多条会话；收起态按 agent 去重显示图标。

`AgentStatus`：

```json
{
  "id": "claude",
  "label": "Claude Code",
  "enabled": true,
  "available": true,
  "state": "running",
  "sessionCount": 1,
  "message": ""
}
```

- `state` 为 `idle` / `running` / `waiting` / `missing`；`missing` 表示本机没有找到该 agent 的会话目录。
- `enabled` 来自 `enabledAgents`；关闭后 `state` 固定为 `idle`。

`AgentFinished`：

```json
{
  "id": "claude",
  "label": "Claude Code",
  "sessionId": "18712d4b-fa3a-47ae-9f25-2b26e30f5140",
  "title": "修复邮件视图返回与复制问题",
  "cwd": "F:\\My_Project\\guduo",
  "state": "done",
  "startedAtMs": 1795327350000,
  "endedAtMs": 1795327374442,
  "durationMs": 24442,
  "replyPreview": "已补上返回手势，并修复复制为空的问题，共改 4 个文件。"
}
```

- `state` 为 `done`（正常结束）或 `aborted`（中断 / 失败）。
- `durationMs`、`replyPreview` 可能缺省；`replyPreview` 最多约 200 字符，客户端只做单行省略显示。
- 检测只读取本地会话文件，不修改 agent 配置，也不联网；日志不记录标题与回复正文。

`Unread`：

```json
{
  "id": "qq:n123",
  "source": "qq",
  "account": 0,
  "window": 0,
  "count": 1,
  "time": "12:34:56",
  "kind": "toast",
  "contact": "张三",
  "preview": "晚上一起吃饭吗"
}
```

- `id` 是稳定键：微信任务栏提醒为 `wechat:flash:<pid>`，系统通知为 `<source>:n<通知编号>`。
- `source` 为 `wechat` 或 `qq`；`kind` 为 `taskbar`（只看得到闪动）或 `toast`（带联系人和预览）。
- 微信 4.x 不使用 Windows 通知中心，微信提醒只有 `kind=taskbar`，没有 `contact` / `preview`。
- QQ 的 `toast` 来自 Windows 通知正文；`contact` / `preview` 只在能读到系统通知时出现。
- `account` / `window` 是进程号与闪动窗口句柄，不作为跨重启的稳定标识；系统通知无法归属账号时为 `0`。

## 事件

服务端主动推送，`method` 固定为 `event`：

```json
{"jsonrpc":"2.0","method":"event","params":{"type":"message.unread","source":"wechat","account":12345,"window":67890,"count":1,"time":"12:34:56"}}
```

| type | 说明 |
| --- | --- |
| `service.ready` | sidecar 启动完成，带 `version` / `apiVersion` / `capabilities` |
| `system.status` | `component` 为 `wechat` 或 `notifications`，带 `ok`、`message` |
| `message.unread` | 新增或更新一条提醒；同一账号 5 秒内的重复闪动合并 |
| `message.cleared` | 提醒已失效，带 `id`，或 `source` + 可选 `account`；清空该来源时只带 `source` |
| `ime.changed` | 中英文输入法切换，带 `mode`（`zh` / `en`）与 `banner`；`banner=false` 表示只是切换窗口 / 焦点后的模式同步，只更新状态、不弹横幅 |
| `weather.updated` | 实况刷新成功或失败，带 `snapshot`（可能为 `null`）与 `status` |
| `volume.changed` | 系统主音量或静音状态变化，带 `volume`（0–1）与 `muted` |
| `metrics.updated` | 系统指标采样完成，带 `snapshot`；固定 1Hz 推送 |
| `media.changed` | 媒体信息变化，带 `media`；播放中最多 1Hz 推送进度，客户端本地插值 |
| `media.lyrics` | 当前曲目歌词，带 `lyrics` 与 `pending`；切歌时立即发 `lyrics:null, pending:true`，抓取结束再发结果 |
| `mail.received` | 收取到一封新邮件，带 `accountId` 与 `item`（`MailSummary`）；首次连接的最近邮件不推事件，客户端在 `mail.account` 变为 `ready` 后调用 `mail.list` |
| `mail.account` | 账号连接状态变化，带 `account`（`MailAccount`） |
| `mail.oauth.completed` | 微软授权成功，带 `flowId` 与新建的 `account` |
| `mail.oauth.failed` | 微软授权失败或超时，带 `flowId` 与 `message` |
| `quota.updated` | 额度刷新完成，带 `providers`（全部已知服务）与 `updatedAtMs`；未配置的服务也会出现，`status` 为 `notConfigured` |
| `agent.updated` | 本地 agent 会话扫描结果变化，带 `sessions`（运行中的会话）与 `agents`（全部 agent 的状态） |
| `agent.finished` | 某个会话的回合结束，带 `id` / `sessionId` / `title` / `endedAtMs` / `replyPreview` 等；只在本次运行期间观察到该会话运行过时才推送 |
| `foreground.maximized` | 前台窗口最大化状态变化，带 `maximized`；前台是 gudong 自身窗口时不更新，客户端保持上一次状态 |
| `schedule.updated` | 日程新增、修改、删除或触发后推送最新全量列表，带 `items` |
| `schedule.fired` | 日程到点，带 `item`；sidecar 同时播放系统提示音并发送 Windows 气泡通知 |
| `anniversary.updated` | 倒计时 / 纪念日新增、修改或删除后推送最新全量列表，带 `items` |
| `shelf.updated` | 中转站条目新增、删除、清空或重复拖入置顶后推送最新全量列表，带 `items` |
| `shelf.icon` | 某个条目的系统缩略图 / 原始图标生成完成，带 `id` 与 `data`（PNG data URL）；每个条目只推一次，客户端按 `id` 缓存 |

`ScheduleItem`：

```json
{
  "id": "s_18f2a3b4c5d_0",
  "title": "项目周会",
  "atMs": 1795000000000,
  "fired": false,
  "createdAtMs": 1794997775244
}
```

- `atMs` 是本地时间对应的 Unix 毫秒时间戳，用于日历分组与到点检查。
- `fired` 为 `true` 表示已经提醒过；修改 `atMs` 会重置为 `false`。
- 日程写 `%APPDATA%\gudong\schedule.json`，先写临时文件再替换，最多 500 条；启动时自动过滤标题为空或时间非法的条目。
- 启动时已过点但未触发的日程会被直接标记为已触发，不补发横幅、提示音或 Windows 通知。
- 已触发日程保留 7 天，之后由 sidecar 自动清理；客户端也可调用 `schedule.clearExpired` 手动清理。
- 到点检查在 sidecar 线程内完成，客户端只消费 `schedule.fired` 与 `schedule.updated`。

`AnniversaryItem`：

```json
{
  "id": "a_18f2a3b4c5d_0",
  "title": "加入 广大黄埔研究院",
  "date": "2025-09-04",
  "createdAtMs": 1794997775244
}
```

- `date` 是本地日历日期 `YYYY-MM-DD`，必须是合法日期，不接受 `2025-9-4` 这类非补零格式。
- 剩余 / 已过天数由客户端按本地日期计算，sidecar 不推送每日变化。
- 倒计时与纪念日写在 `%APPDATA%\gudong\anniversaries.json`，先写临时文件再替换，最多 200 条。
- 该页面位于日程 tab 的第二页，不单独占用 `tabOrder`。

`ShelfItem`：

```json
{
  "id": "f_18f2a3b4c5d_0",
  "path": "C:\\Users\\me\\Desktop\\report.pdf",
  "name": "report.pdf",
  "kind": "document",
  "size": 1048576,
  "modifiedMs": 1794997775244,
  "addedAtMs": 1794997775244,
  "missing": false
}
```

- 中转站是引用式存储：只记录路径，不复制文件内容，因此没有单文件大小和总容量限制。
- `kind` 为 `image` / `video` / `audio` / `document` / `archive` / `installer` / `folder` / `file`，由 sidecar 按扩展名归类，客户端只负责映射图标。
- `missing=true` 表示原文件已不存在；条目保留，不自动删除，`shelf.reveal` 会拒绝失效条目。
- 相同路径重复拖入会置顶并刷新元数据，不新增条目；达到 `shelfMaxItems` 后返回 `reason=limit`，不淘汰旧条目。
- 索引写 `%APPDATA%\gudong\shelf.json`，先写临时文件再替换。启动时重新检查路径存在性。
- 图标由 sidecar 在后台线程用 `IShellItemImageFactory` 生成 96 px 缩略图；文件夹和无法生成缩略图的文件退回 shell 原始图标。编码为 PNG 后通过 `shelf.icon` 推送，生成失败不推送，客户端退回分类图标。
- 拖入和拖出都由 Flutter 侧原生拖放实现：拖入拿到文件路径后调用 `shelf.add`；拖出直接由窗口进程把 `CF_HDROP` 交给目标程序，不经过 sidecar。
- 不在 sidecar 里调用 `DoDragDrop`：OLE 拖拽循环需要稳定的 UI 线程消息循环，后台线程一旦收不到鼠标抬起消息会占住全局鼠标捕获，影响资源管理器等所有程序的拖放。

`MediaSnapshot`：

```json
{
  "available": true,
  "title": "晴天",
  "artist": "周杰伦",
  "album": "叶惠美",
  "source": "QQMusic.exe",
  "kind": "music",
  "playing": true,
  "position": 42.5,
  "duration": 269.0,
  "artwork": "data:image/png;base64,..."
}
```

- `kind` 为 `music` / `video` / `unknown`；`source` 是播放器的应用标识。
- 封面只在曲目变化的那次事件中携带，之后的事件与心跳不带 `artwork`；重连后
  `media.get` 返回的快照仍包含当前封面。
- 无会话时 `available` 为 `false`，其余字段为零值。
- `media.control` 的 `source` 缺省时控制当前会话；`seek` 需要 `position`（秒），
  非法参数返回 `-32602`，播放器拒绝或超时返回 `ok:false`。

`LyricsSnapshot`：

```json
{
  "title": "晴天",
  "artist": "周杰伦",
  "source": "qqmusic",
  "lines": [
    { "time": 3.0, "text": "故事的小黄花" },
    { "time": 7.5, "text": "从出生那年就飘着" }
  ]
}
```

- 只要有标题就尝试匹配；播放器上报的 `kind` 不参与判断，视频通常匹配不到歌词后自动放弃。
- 按歌名精确匹配 QQ 音乐候选，歌手与时长用于同名词条排序。
- 抓取在 sidecar 线程内完成，切歌后旧请求的结果会被丢弃。
- `pending=true` 表示正在抓取；抓取失败或没有匹配时会发一次 `pending=false` 的空结果。
- 客户端按播放位置在本地选行，不需要额外请求。

`MetricsSnapshot`：

```json
{
  "uploadBps": 128000.0,
  "downloadBps": 1500000.0,
  "cpuPercent": 23.4,
  "memoryPercent": 61.0,
  "memoryUsedBytes": 10192158720,
  "memoryTotalBytes": 17179869184,
  "cpuMhz": 3200,
  "cpuMaxMhz": 4800,
  "gpuPercent": 42.0,
  "gpuMemoryPercent": 33.0,
  "gpuMemoryUsedBytes": 4294967296,
  "gpuMemoryTotalBytes": 12884901888,
  "totalUploadBytes": 812345678,
  "totalDownloadBytes": 9123456789,
  "updatedAtMs": 1794997775244
}
```

- `uploadBps` / `downloadBps` 为 1 秒窗口内的平均字节速率；`cpuPercent` / `memoryPercent` / `gpuPercent` / `gpuMemoryPercent` 为 0–100。
- `cpuMhz` / `cpuMaxMhz` 为各逻辑核心当前与最大主频的平均值；取不到时为 `0`。
- `gpuPercent` 为所有 GPU 引擎利用率之和，多引擎叠加后截断到 100。
- `gpuMemoryUsedBytes` / `gpuMemoryTotalBytes` 为所有适配器的专用显存已用与总量；总量取不到时为 `0`，此时 `gpuMemoryPercent` 也为 `0`。
- GPU 数据来自 PDH 性能计数器与 DXGI；驱动或系统不支持时相关字段为 `0`，不影响其余指标。
- `totalUploadBytes` / `totalDownloadBytes` 是 sidecar 启动以来的累计收发字节，不跨会话累加。
- 采样在 sidecar 内以 1Hz 运行，`metrics.updated` 固定推送；客户端可本地插值刷新界面。
- 网络只统计处于 Up 状态的硬件网卡，虚拟网桥与回环接口不计入，避免重复计数。
- 采样线程启动后第一帧在约 1 秒后产生；在此之前 `metrics.get` 返回 `snapshot: null`。

`WeatherSnapshot`：

```json
{
  "place": "广州",
  "temp_c": 19.0,
  "kind": "cloudy",
  "description": "阴",
  "is_day": false,
  "updated_at_ms": 1794997775244,
  "feels_like_c": 17.0,
  "humidity": 68,
  "wind_kph": 19.0,
  "high_c": 24.0,
  "low_c": 18.0,
  "hours": [
    {
      "time": "21:00",
      "temp_c": 12.0,
      "kind": "cloudy",
      "description": "阴",
      "is_day": false,
      "precip_probability": 10,
      "feels_like_c": 11.0
    }
  ],
  "days": [
    {
      "date": "2026-11-18",
      "kind": "rain",
      "description": "附近有零星降雨",
      "high_c": 24.0,
      "low_c": 18.0,
      "precip_probability": 20
    }
  ]
}
```

- `kind` 为 `clear` / `partly` / `cloudy` / `fog` / `drizzle` / `rain` / `snow` / `thunder`，由 sidecar 统一归一化，客户端只负责映射图标。
- `feels_like_c` / `humidity` / `wind_kph` / `precip_probability` 可能缺省；`days` 最多 5 天。
- `hours` 覆盖未来 24 小时，`time` 是地点本地时间 `HH:mm`；字段与 `days` 类似，额外带 `is_day`。wttr.in 路径按 3 小时粒度返回 8 个时段，Open-Meteo 路径返回逐小时 24 个点；数据缺失时为空数组。
- 定位与抓取都在 sidecar 内完成：定位优先 ipwho.is，失败退 freeipapi；天气优先 wttr.in，失败退 Open-Meteo；wttr.in 只有 3 天预报，不足 5 天时用 7Timer 补齐。日志不记录 IP 与坐标。
- `weatherLocationMode=manual` 时跳过 IP 定位，直接使用 `weatherLatitude` / `weatherLongitude`；搜索接口走 Open-Meteo 地理编码。设置变更后天气线程立即刷新，切回 `auto` 时重新定位。
- `weather.search` 是网络请求，sidecar 立即返回 `Pending` 并在天气线程内完成，客户端超时应放宽到 15–20 秒。
- 刷新间隔 15 分钟，失败后 2 分钟重试；刷新失败时保留上一次 `snapshot`。

`PlaceOption`：

```json
{
  "name": "广州",
  "admin": "广东省",
  "country": "中国",
  "latitude": 23.11667,
  "longitude": 113.25,
  "label": "广州 · 广东省 · 中国"
}
```

- `label` 已按「名称 · 行政区 · 国家」去重拼接，可直接展示或写入 `weatherLocationName`。
- 最多返回 8 条；`admin`、`country` 可能缺省。

## 翻译

`translate.run` 在 sidecar 的后台线程执行，耗时可能超过普通请求的 5 秒；客户端应放宽到 60–90 秒。

| provider | 接口 | 凭据 |
| --- | --- | --- |
| `llm` | `POST {translateBaseUrl}/chat/completions`（OpenAI 兼容） | `translate.setSecret` 的 `llm` |
| `deepl` | `POST api.deepl.com/v2/translate`；Key 以 `:fx` 结尾时走 `api-free.deepl.com` | `deepl` |
| `caiyun` | `POST api.interpreter.caiyunai.com/v1/translator` | 可选个人 Token；未配置时用官方公开测试 Token |
| `microsoftFree` | `POST edge.microsoft.com/translate/translatetext`（Edge 内部接口） | 无 |
| `mymemory` | `GET api.mymemory.translated.net/get` | 无 |

- 未显式指定 `provider` 或为 `auto` 时，按 `translateAutoOrder` 从上到下依次尝试，失败后继续下一个可用引擎；缺省顺序为 LLM → DeepL → 彩云 → 微软免密钥 → MyMemory。结果里的 `provider` 是实际成功的引擎。
- 彩云小译支持译为 `zh-CN` / `zh-TW`，以及中文译为 `en` / `ja` / `ko`；其他目标返回 `-32603`。未配置个人 Token 时使用官方公开测试 Token，可能被限流或随时失效。
- `microsoftFree` 是非官方接口，没有文档和 SLA，可能随时失效；失败时自动回退 MyMemory，结果的 `provider` 会返回 `mymemory`。
- `translate.models` 请求 `GET {translateBaseUrl}/models`，返回 `data[].id` 去重排序后的列表。
- MyMemory 不支持自动识别，sidecar 按字符集推断源语言；`q` 上限 500 字节，超长文本按句子分块。匿名约 5000 字符/天，配置 `translateMyMemoryEmail` 后约 50000 字符/天。
- MyMemory 的邮箱不是账号或密钥，只用于官方联系和识别用量，会随每次翻译请求以 `de` 参数发送；留空则不发送。
- 大模型默认使用与沉浸式翻译一致的 system/user 提示词结构；可用 `translateSystemPrompt` / `translateUserPrompt` 覆盖。
- 显式指定 `provider` 失败时返回 `-32603`，`message` 为可读错误，不回退；`auto` 模式会继续尝试后续引擎，全部失败才返回 `-32603`。
- 日志只记录引擎与错误，不记录原文、译文和密钥。

`message.cleared` 的触发条件：

- 前台切到微信 / QQ 主窗口（已查看）。
- 系统通知从通知中心消失（点击忽略、划掉或点开后客户端收回）。

## 邮件

收件箱。当前阶段不发送、不回复、不删除、不移动；打开单封邮件会自动标为已读，也支持一键标记当前筛选范围。正文一律用 `BODY.PEEK` 读取。

### 账号

`MailAccount`：

```json
{
  "id": "m_7f3a1c",
  "provider": "qq",
  "email": "user@example.com",
  "label": "工作",
  "authType": "password",
  "enabled": true,
  "custom": null,
  "webmailUrl": "https://mail.qq.com/",
  "state": "ready",
  "message": "",
  "lastSyncAt": 1794997775244,
  "reauthRequired": false
}
```

- `id` 由 sidecar 生成并持久化，不等同于邮箱地址，删除重加后仍可保持稳定。
- `provider` 为 `qq` / `163` / `126` / `exmail` / `icloud` / `gmail` / `microsoft` / `custom`；主机和端口由预设决定，`custom` 使用 `custom:{host, port, username}`。
- `authType` 为 `password` 或 `oauth2`。`password` 指邮箱授权码或应用专用密码，不是登录密码。
- `state` 为 `idle` / `connecting` / `ready` / `auth` / `failed`；`auth` 表示授权码或令牌被拒，此时 `reauthRequired` 为 `true`。
- `message` 是可直接展示的中文状态说明；`lastSyncAt` 为最近一次成功同步的毫秒时间戳。
- 只支持 IMAP over TLS（通常 993），严格校验证书；不支持 143、STARTTLS 和明文连接。

| provider | 主机 | 认证 | 说明 |
| --- | --- | --- | --- |
| `qq` | `imap.qq.com` | 授权码 | |
| `163` | `imap.163.com` | 授权码 | 登录前需发送 RFC 2971 `ID` |
| `126` | `imap.126.com` | 授权码 | 登录前需发送 RFC 2971 `ID` |
| `exmail` | `imap.exmail.qq.com` | 客户端专用密码 | 企业策略可能禁用 IMAP |
| `icloud` | `imap.mail.me.com` | App 专用密码 | 需开启双重认证 |
| `gmail` | `imap.gmail.com` | 应用专用密码 | 需开启两步验证 |
| `microsoft` | `outlook.office365.com` | OAuth2 + XOAUTH2 | 不支持密码直连 |
| `custom` | 用户填写 | 密码 | 仅 993 或自定义 TLS 端口 |

账号元数据写 `%APPDATA%\gudong\mail.json`，先写临时文件再替换。授权码、应用专用密码和微软 refresh token 写 Windows 凭据管理器，目标名 `gudong/mail/<id>`，任何接口都不回传。

`mail.accounts.add` 只落盘并返回，不等待网络：连接、登录和首次同步都在后台进行，结果通过 `mail.account` 事件推送。相同 `provider` + 邮箱 + `custom` 端点重复添加时覆盖凭据并重置状态。

### 微软 OAuth

- `mail.oauth.begin` 返回设备码，用户在浏览器完成登录；sidecar 在后台轮询 token 端点，不阻塞请求。
- 成功后自动创建 `provider=microsoft`、`authType=oauth2` 的账号并发 `mail.oauth.completed`；失败或 15 分钟超时发 `mail.oauth.failed`。
- access token 只放内存，过期前 5 分钟刷新；refresh token 失效时账号转为 `state=auth`、`reauthRequired=true`，不自动重试。
- scope 为 `offline_access` 与 `https://outlook.office.com/IMAP.AccessAsUser.All`。企业租户可能要求管理员同意。
- 当前构建尚未内置 Azure 公共客户端 `client_id`：`mail.oauth.begin` 返回 `-32603`，`mail.accounts.add` 对 `microsoft` 返回 `-32602`。配置 client_id 后启用。

### 邮件

`MailSummary`：

```json
{
  "id": "mail:m_7f3a1c:8123:456",
  "accountId": "m_7f3a1c",
  "from": "张三",
  "fromAddress": "zhangsan@example.com",
  "subject": "项目进度",
  "receivedAt": 1794997775244,
  "unread": true,
  "snippet": "本周的进度是…",
  "hasAttachments": false
}
```

`MailDetail` 在摘要基础上增加：

```json
{
  "text": "纯文本正文…",
  "truncated": false,
  "links": [{ "label": "查看详情", "url": "https://example.com/detail" }]
}
```

- `id` 为 `mail:<accountId>:<uidValidity>:<uid>`；`uidValidity` 变化后旧 id 全部失效，客户端应重新 `mail.list`。
- `receivedAt` 为毫秒时间戳；`unread` 来自 IMAP `FLAGS`。
- 正文优先 `text/plain`；只有 HTML 时转换为纯文本，并剥离引用历史和签名；上限 64KB，超出时 `truncated=true`。
- 不返回 HTML，不加载远程图片，不下载附件；`hasAttachments` 由 `BODYSTRUCTURE` 判断。
- 每账号在内存中保留最近 20 封（含正文），超出淘汰；不落盘。多账号时每个账号各自保留 20 封。
- `mail.list` 的 `limit` 按账号计算，默认 `20`，限制在 `1`–`20`；`mail.get` 只返回已缓存的正文，未缓存返回 `-32602`。
- 首次连接读取最近 20 封写入缓存，随后推送 `mail.account` 的 `state=ready`；客户端收到后调用 `mail.list`。之后每轮只取 `UID <last+1>:*` 且每次最多 5 封，逐封推 `mail.received`。
- 轮询间隔取 `mailPollSeconds`；连接或登录失败按 30 秒起指数退避，最长 60 秒。
- `mail.markSeen` 使用独立短连接，避免和常驻收信连接争用；传 `id` 时先校验 `uidValidity`，变化则返回错误让客户端刷新。单个账号失败会返回 `ok:false` 和可读消息，成功账号的缓存仍会更新。
- 客户端打开单封未读邮件时应调用 `mail.markSeen {id}`；批量已读传 `accountId` 或不传参数。

### 翻译

- 复用现有 `translate.run`，不新增邮件专用翻译方法。
- 客户端把 `MailDetail.text` 或主题作为 `text` 传入；`mail.get` 返回的正文已清理引用和签名，可直接翻译。
- 翻译按需触发，sidecar 不自动翻译、不缓存译文；客户端可按邮件 `id` + 目标语言自行缓存。
- 翻译超时沿用 60–90 秒约定；大模型调用失败时不要静默回退到其他引擎。

### 日志

- 日志只记录账号 `id`、`provider`、连接状态和错误类型。
- 不记录邮箱地址、主题、正文、验证码、授权码、access token 或 refresh token。

## 约定

- 事件只推变化；媒体进度后续最高 1Hz，由 UI 本地插值。
- 请求 5 秒超时；心跳由 Flutter 每 5 秒发 `app.ping`，连续 2 次失败即重启 sidecar。
- `apiVersion` 不匹配时 `app.hello` 返回 `-32000`，客户端应停在“需升级”状态，不要退避重启。
- 错误码：

| code | 含义 |
| --- | --- |
| `-32700` | JSON 解析失败，`id` 为 `null` |
| `-32600` | 请求结构不合法（缺少 `method`） |
| `-32601` | 方法不存在 |
| `-32602` | 参数不合法 |
| `-32603` | 服务端内部错误（例如配置写盘失败） |
| `-32000` | `apiVersion` 不匹配 |

- 能力声明：`service.ready` 事件与 `app.hello` 结果里的 `capabilities` 来自 sidecar 内同一份常量。
- 日志写 `%LOCALAPPDATA%\gudong\logs\island_service.log`，stdout 只输出协议数据。
