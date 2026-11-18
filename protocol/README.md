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
| `settings.get` | `{}` | 占位 |
| `settings.set` | `{...}` | `{ok}` |
| `app.shutdown` | `{}` | `{ok}`，随后进程退出 |

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

`message.cleared` 的触发条件：

- 前台切到微信 / QQ 主窗口（已查看）。
- 系统通知从通知中心消失（点击忽略、划掉或点开后客户端收回）。

## 约定

- 事件只推变化；媒体进度后续最高 1Hz，由 UI 本地插值。
- 请求 5 秒超时；心跳由 Flutter 每 5 秒发 `app.ping`，连续 2 次失败即重启 sidecar。
- `apiVersion` 不匹配时 `app.hello` 返回 `-32000`，客户端应提示升级而不是继续使用。
- 错误码：`-32601` 方法不存在，`-32000` 版本不匹配。
- 日志写 `%LOCALAPPDATA%\guduo\logs\island_service.log`，stdout 只输出协议数据。
