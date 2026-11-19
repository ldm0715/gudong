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
| `tabOrder` | string[] | 岛体 tab 顺序：`messages` / `translate` / `weather` / `media` / `diagnostics` |
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

- 未显式指定 `provider` 或为 `auto` 时，按 `translateAutoOrder` 从上到下选择第一个可用引擎；缺省顺序为 LLM → DeepL → 彩云 → 微软免密钥 → MyMemory。
- 彩云小译支持译为 `zh-CN` / `zh-TW`，以及中文译为 `en` / `ja` / `ko`；其他目标返回 `-32603`。未配置个人 Token 时使用官方公开测试 Token，可能被限流或随时失效。
- `microsoftFree` 是非官方接口，没有文档和 SLA，可能随时失效；失败时自动回退 MyMemory，结果的 `provider` 会返回 `mymemory`。
- `translate.models` 请求 `GET {translateBaseUrl}/models`，返回 `data[].id` 去重排序后的列表。
- MyMemory 不支持自动识别，sidecar 按字符集推断源语言；`q` 上限 500 字节，超长文本按句子分块。匿名约 5000 字符/天，配置 `translateMyMemoryEmail` 后约 50000 字符/天。
- MyMemory 的邮箱不是账号或密钥，只用于官方联系和识别用量，会随每次翻译请求以 `de` 参数发送；留空则不发送。
- 大模型默认使用与沉浸式翻译一致的 system/user 提示词结构；可用 `translateSystemPrompt` / `translateUserPrompt` 覆盖。
- 引擎失败时返回 `-32603`，`message` 为可读错误；不会自动回退到其他引擎，避免用户误以为在用大模型。
- 日志只记录引擎与错误，不记录原文、译文和密钥。

`message.cleared` 的触发条件：

- 前台切到微信 / QQ 主窗口（已查看）。
- 系统通知从通知中心消失（点击忽略、划掉或点开后客户端收回）。

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
