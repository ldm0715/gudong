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
| `app.shutdown` | `{}` | `{ok}`，随后进程退出 |

`settings` 是扁平 JSON 对象，当前键：

| key | 类型 | 说明 |
| --- | --- | --- |
| `themeId` | string | 皮肤标识：`midnight`（午夜，默认）/ `daylight`（日光） |
| `showWeather` | bool | 是否在岛体显示天气，默认 `true` |
| `mediaEnabled` | bool | 是否读取 SMTC 媒体会话，默认 `true` |
| `showPlayingIndicator` | bool | 收起态播放时显示音波，默认 `true` |
| `showImeIndicator` | bool | 收起态常驻显示输入法状态，默认 `true` |
| `showImeBanner` | bool | 输入法切换时弹出横幅，默认 `true` |
| `tabOrder` | string[] | 岛体 tab 顺序：`messages` / `translate` / `weather` / `media` / `diagnostics` / `mail` |
| `hiddenTabs` | string[] | 隐藏的 tab；允许全部隐藏，此时岛体只显示标题栏与设置入口 |
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

`settings.get` 与 `settings.set` 的返回里还会带 `translateLlmKeyConfigured` / `translateDeeplKeyConfigured` / `translateCaiyunKeyConfigured` 三个只读布尔值。它们不写入 config.json，也不接受写入，表示对应密钥是否已在 Windows 凭据管理器里。

设置落盘到 `%APPDATA%\guduo\config.json`，先写临时文件再替换。`settings.set` 只合并传入的 key，未传的键保持不变；值必须是合法 JSON，空 key 返回 `-32602`。翻译密钥通过 `translate.setSecret` 写入 Windows 凭据管理器（目标名 `guduo/translate/llm`、`guduo/translate/deepl`、`guduo/translate/caiyun`），不落 config.json。

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
| `media.changed` | 媒体信息变化，带 `media`；播放中最多 1Hz 推送进度，客户端本地插值 |
| `media.lyrics` | 当前曲目歌词，带 `lyrics` 与 `pending`；切歌时立即发 `lyrics:null, pending:true`，抓取结束再发结果 |
| `mail.received` | 收取到一封新邮件，带 `accountId` 与 `item`（`MailSummary`）；首次连接的最近邮件不推事件，客户端在 `mail.account` 变为 `ready` 后调用 `mail.list` |
| `mail.account` | 账号连接状态变化，带 `account`（`MailAccount`） |
| `mail.oauth.completed` | 微软授权成功，带 `flowId` 与新建的 `account` |
| `mail.oauth.failed` | 微软授权失败或超时，带 `flowId` 与 `message` |

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
- 定位与抓取都在 sidecar 内完成：定位优先 ipwho.is，失败退 freeipapi；天气优先 wttr.in，失败退 Open-Meteo；wttr.in 只有 3 天预报，不足 5 天时用 7Timer 补齐。日志不记录 IP 与坐标。
- 刷新间隔 15 分钟，失败后 2 分钟重试；刷新失败时保留上一次 `snapshot`。

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

账号元数据写 `%APPDATA%\guduo\mail.json`，先写临时文件再替换。授权码、应用专用密码和微软 refresh token 写 Windows 凭据管理器，目标名 `guduo/mail/<id>`，任何接口都不回传。

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
- 日志写 `%LOCALAPPDATA%\guduo\logs\island_service.log`，stdout 只输出协议数据。
