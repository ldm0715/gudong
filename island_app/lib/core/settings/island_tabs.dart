/// 岛体页面标识。持久化时使用 [id]，顺序与显隐来自设置。
enum IslandTab {
  messages('messages', '消息'),
  mail('mail', '邮箱'),
  translate('translate', '翻译'),
  weather('weather', '天气'),
  media('media', '媒体'),
  quota('quota', '额度'),
  schedule('schedule', '日程'),
  diagnostics('diagnostics', '诊断');

  const IslandTab(this.id, this.label);

  final String id;
  final String label;

  static const List<IslandTab> all = [
    IslandTab.messages,
    IslandTab.mail,
    IslandTab.translate,
    IslandTab.weather,
    IslandTab.media,
    IslandTab.quota,
    IslandTab.schedule,
    IslandTab.diagnostics,
  ];

  static IslandTab? byId(String id) {
    for (final tab in values) {
      if (tab.id == id) return tab;
    }
    return null;
  }
}
