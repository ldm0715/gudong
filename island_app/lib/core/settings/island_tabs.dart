/// 岛体页面标识。持久化时使用 [id]，顺序与显隐来自设置。
enum IslandTab {
  messages('messages', '消息'),
  weather('weather', '天气'),
  media('media', '媒体'),
  diagnostics('diagnostics', '诊断');

  const IslandTab(this.id, this.label);

  final String id;
  final String label;

  static const List<IslandTab> all = [
    IslandTab.messages,
    IslandTab.weather,
    IslandTab.media,
    IslandTab.diagnostics,
  ];

  static IslandTab? byId(String id) {
    for (final tab in values) {
      if (tab.id == id) return tab;
    }
    return null;
  }
}
