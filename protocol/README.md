# Sidecar IPC 协议 v1

传输：stdio，UTF-8，每行一个 JSON（JSON-RPC 2.0）。`apiVersion` 当前为 `1`。

## 请求 / 响应

| method | params | result |
| --- | --- | --- |
| `app.hello` | `{apiVersion}` | `{version, apiVersion, capabilities}` |
| `app.ping` | `{}` | `{pong, uptimeMs}` |
| `messages.list` | `{}` | `{items:[Unread], listener:{ok, message}, notifications:{ok, message}}` |
| `messages.seen` | `{id}` / `{source, account}` / `{}`（空对象 = 全部） | `{ok, removed}` |
| `messages.open` | `{id}` 或 `{source, account}` | `{ok, message?}`；成功后客户端切到前台并清除该提醒 |
| `media.get` | `{}` | `{title, artist, position, playing, available}`（Phase 0 为占位） |
| `weather.get` | `{}` | `{snapshot, status}`；`snapshot` 可能为 `null` |
| `settings.get` | `{}` | `{settings}` |
| `settings.set` | `{settings:{...}}` | `{ok, settings}`；按 key 合并后返回全量设置 |
| `app.shutdown` | `{}` | `{ok}`，随后进程退出 |

`settings` 是扁平 JSON 对象，当前键：

| key | 类型 | 说明 |
| --- | --- | --- |
| `themeId` | string | 皮肤标识：`midnight`（午夜，默认）/ `daylight`（日光） |
| `showWeather` | bool | 是否在岛体显示天气，默认 `true` |
| `windowX` / `windowY` | number | 窗口左上角屏幕坐标（物理像素），缺省表示按默认位置摆放 |

设置落盘到 `%APPDATA%\guduo\config.json`，先写临时文件再替换。`settings.set` 只合并传入的 key，未传的键保持不变；值必须是合法 JSON，空 key 返回 `-32602`。

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
| `weather.updated` | 实况刷新成功或失败，带 `snapshot`（可能为 `null`）与 `status` |

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
