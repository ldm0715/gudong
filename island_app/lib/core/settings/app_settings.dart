import 'island_tabs.dart';

/// 用户设置。持久化由 sidecar 负责，字段名与 config.json 保持一致。
class AppSettings {
  const AppSettings({
    this.themeId = 'midnight',
    this.showWeather = true,
    this.mediaEnabled = true,
    this.showPlayingIndicator = true,
    this.tabOrder = defaultTabOrder,
    this.hiddenTabs = const [],
    this.windowX,
    this.windowY,
  });

  static const List<String> defaultTabOrder = [
    'messages',
    'weather',
    'media',
    'diagnostics',
  ];

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeId: json['themeId']?.toString() ?? 'midnight',
      showWeather: json['showWeather'] != false,
      mediaEnabled: json['mediaEnabled'] != false,
      showPlayingIndicator: json['showPlayingIndicator'] != false,
      tabOrder: _normalizeOrder(json['tabOrder']),
      hiddenTabs: _normalizeHidden(json['hiddenTabs']),
      windowX: (json['windowX'] as num?)?.toDouble(),
      windowY: (json['windowY'] as num?)?.toDouble(),
    );
  }

  final String themeId;
  final bool showWeather;
  final bool mediaEnabled;
  final bool showPlayingIndicator;
  final List<String> tabOrder;
  final List<String> hiddenTabs;
  final double? windowX;
  final double? windowY;

  /// 已排好序的全部页面，未知 id 被丢弃，缺失的补在末尾。
  List<IslandTab> get orderedTabs {
    final ordered = <IslandTab>[];
    for (final id in tabOrder) {
      final tab = IslandTab.byId(id);
      if (tab != null && !ordered.contains(tab)) ordered.add(tab);
    }
    for (final tab in IslandTab.all) {
      if (!ordered.contains(tab)) ordered.add(tab);
    }
    return ordered;
  }

  /// 岛体实际显示的页面。允许为空，此时岛体只保留标题栏与设置入口。
  List<IslandTab> get visibleTabs => orderedTabs
      .where((tab) => !hiddenTabs.contains(tab.id))
      .toList(growable: false);

  Map<String, dynamic> toJson() => {
    'themeId': themeId,
    'showWeather': showWeather,
    'mediaEnabled': mediaEnabled,
    'showPlayingIndicator': showPlayingIndicator,
    'tabOrder': tabOrder,
    'hiddenTabs': hiddenTabs,
    if (windowX != null) 'windowX': windowX,
    if (windowY != null) 'windowY': windowY,
  };

  AppSettings copyWith({
    String? themeId,
    bool? showWeather,
    bool? mediaEnabled,
    bool? showPlayingIndicator,
    List<String>? tabOrder,
    List<String>? hiddenTabs,
    double? windowX,
    double? windowY,
  }) {
    return AppSettings(
      themeId: themeId ?? this.themeId,
      showWeather: showWeather ?? this.showWeather,
      mediaEnabled: mediaEnabled ?? this.mediaEnabled,
      showPlayingIndicator:
          showPlayingIndicator ?? this.showPlayingIndicator,
      tabOrder: tabOrder ?? this.tabOrder,
      hiddenTabs: hiddenTabs ?? this.hiddenTabs,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
    );
  }

  static List<String> _normalizeOrder(Object? raw) {
    final ids = <String>[];
    if (raw is List) {
      for (final value in raw) {
        final id = value.toString();
        if (IslandTab.byId(id) != null && !ids.contains(id)) ids.add(id);
      }
    }
    for (final id in defaultTabOrder) {
      if (!ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  static List<String> _normalizeHidden(Object? raw) {
    final ids = <String>[];
    if (raw is List) {
      for (final value in raw) {
        final id = value.toString();
        if (IslandTab.byId(id) != null && !ids.contains(id)) ids.add(id);
      }
    }
    return ids;
  }
}
