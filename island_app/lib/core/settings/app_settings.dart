import 'island_tabs.dart';

/// 用户设置。持久化由 sidecar 负责，字段名与 config.json 保持一致。
class AppSettings {
  const AppSettings({
    this.themeId = 'midnight',
    this.showWeather = true,
    this.mediaEnabled = true,
    this.showPlayingIndicator = true,
    this.showImeIndicator = true,
    this.showImeBanner = true,
    this.tabOrder = defaultTabOrder,
    this.hiddenTabs = const [],
    this.dockSide = 'top',
    this.dockOffset,
    this.translateProvider = 'auto',
    this.translateBaseUrl = 'https://api.openai.com/v1',
    this.translateModel = '',
    this.translateTarget = 'zh-CN',
    this.translateSource = 'auto',
    this.translateAutoOrder = defaultTranslateAutoOrder,
    this.translateUserPrompt = defaultTranslateUserPrompt,
    this.translateSystemPrompt = '',
    this.translateMyMemoryEmail = '',
    this.translateLlmKeyConfigured = false,
    this.translateDeeplKeyConfigured = false,
    this.translateCaiyunKeyConfigured = false,
    this.mailPollSeconds = defaultMailPollSeconds,
    this.mailTranslateProvider = 'auto',
    this.quotaOrder = defaultQuotaOrder,
    this.hiddenQuotaProviders = const [],
    this.quotaGlmRegion = 'global',
    this.quotaGlmKeyConfigured = false,
    this.quotaDeepseekKeyConfigured = false,
    this.quotaOpencodeKeyConfigured = false,
    this.quotaOpencodeCookieConfigured = false,
  });

  static const List<String> defaultTabOrder = [
    'messages',
    'mail',
    'translate',
    'weather',
    'media',
    'quota',
    'diagnostics',
  ];

  static const List<String> defaultQuotaOrder = ['glm', 'deepseek', 'opencode'];

  static const int defaultMailPollSeconds = 180;

  static const List<String> defaultTranslateAutoOrder = [
    'llm',
    'deepl',
    'caiyun',
    'microsoftFree',
    'mymemory',
  ];

  /// 留空表示使用内置翻译指令；填写普通文字会作为额外要求拼接。
  static const String defaultTranslateUserPrompt = '';

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeId: json['themeId']?.toString() ?? 'midnight',
      showWeather: json['showWeather'] != false,
      mediaEnabled: json['mediaEnabled'] != false,
      showPlayingIndicator: json['showPlayingIndicator'] != false,
      showImeIndicator: json['showImeIndicator'] != false,
      showImeBanner: json['showImeBanner'] != false,
      tabOrder: _normalizeOrder(json['tabOrder']),
      hiddenTabs: _normalizeHidden(json['hiddenTabs']),
      dockSide: _normalizeDockSide(json['dockSide']),
      dockOffset: (json['dockOffset'] as num?)?.toDouble(),
      translateProvider: _normalizeTranslateProvider(json['translateProvider']),
      translateBaseUrl:
          json['translateBaseUrl']?.toString() ??
          'https://api.openai.com/v1',
      translateModel: json['translateModel']?.toString() ?? '',
      translateTarget: json['translateTarget']?.toString() ?? 'zh-CN',
      translateSource: json['translateSource']?.toString() ?? 'auto',
      translateAutoOrder: _normalizeTranslateAutoOrder(
        json['translateAutoOrder'],
      ),
      translateUserPrompt:
          json['translateUserPrompt']?.toString() ?? defaultTranslateUserPrompt,
      translateSystemPrompt: json['translateSystemPrompt']?.toString() ?? '',
      translateMyMemoryEmail:
          json['translateMyMemoryEmail']?.toString() ?? '',
      translateLlmKeyConfigured: json['translateLlmKeyConfigured'] == true,
      translateDeeplKeyConfigured: json['translateDeeplKeyConfigured'] == true,
      translateCaiyunKeyConfigured:
          json['translateCaiyunKeyConfigured'] == true,
      mailPollSeconds: _normalizeMailPollSeconds(json['mailPollSeconds']),
      mailTranslateProvider: _normalizeTranslateProvider(
        json['mailTranslateProvider'],
      ),
      quotaOrder: _normalizeQuotaOrder(json['quotaOrder']),
      hiddenQuotaProviders: _normalizeHiddenQuotaProviders(
        json['hiddenQuotaProviders'],
      ),
      quotaGlmRegion: json['quotaGlmRegion'] == 'bigmodel-cn'
          ? 'bigmodel-cn'
          : 'global',
      quotaGlmKeyConfigured: json['quotaGlmKeyConfigured'] == true,
      quotaDeepseekKeyConfigured:
          json['quotaDeepseekKeyConfigured'] == true,
      quotaOpencodeKeyConfigured:
          json['quotaOpencodeKeyConfigured'] == true,
      quotaOpencodeCookieConfigured:
          json['quotaOpencodeCookieConfigured'] == true,
    );
  }

  final String themeId;
  final bool showWeather;
  final bool mediaEnabled;
  final bool showPlayingIndicator;

  /// 收起态常驻显示当前输入法模式。
  final bool showImeIndicator;

  /// 输入法切换时弹出横幅。
  final bool showImeBanner;
  final List<String> tabOrder;
  final List<String> hiddenTabs;

  /// 停靠边缘：`top` / `left` / `right`。
  final String dockSide;

  /// 岛体中心沿停靠边缘的物理像素坐标。
  final double? dockOffset;

  /// 翻译引擎：`auto` / `llm` / `deepl` / `caiyun` / `microsoftFree` / `mymemory`。
  final String translateProvider;
  final String translateBaseUrl;
  final String translateModel;
  final String translateTarget;
  final String translateSource;

  /// 自动模式的引擎优先级，按列表顺序选择第一个可用引擎。
  final List<String> translateAutoOrder;

  /// 用户提示词模板，支持 `{{to}}` 和 `{{text}}`。
  final String translateUserPrompt;
  final String translateSystemPrompt;
  final String translateMyMemoryEmail;

  /// 只读派生状态，来自 sidecar，不写回 config.json。
  final bool translateLlmKeyConfigured;
  final bool translateDeeplKeyConfigured;
  final bool translateCaiyunKeyConfigured;

  /// 邮件轮询间隔秒数，sidecar 会再限制在 60–900。
  final int mailPollSeconds;

  /// 邮件详情翻译使用的服务，与翻译页的全局服务相互独立。
  final String mailTranslateProvider;

  /// 额度服务顺序：`glm` / `deepseek` / `opencode`。
  final List<String> quotaOrder;

  /// 隐藏的额度服务，展开面板与收起态都不显示。
  final List<String> hiddenQuotaProviders;

  /// GLM 接口区域：`global`（Z.ai）/ `bigmodel-cn`（智谱开放平台）。
  final String quotaGlmRegion;

  /// 只读派生状态，来自 sidecar，不写回 config.json。
  final bool quotaGlmKeyConfigured;
  final bool quotaDeepseekKeyConfigured;
  final bool quotaOpencodeKeyConfigured;
  final bool quotaOpencodeCookieConfigured;

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

  /// 已排好序的额度服务 id，未知项丢弃，缺失的补在末尾。
  List<String> get orderedQuotaProviders {
    final ordered = <String>[];
    for (final id in quotaOrder) {
      if (defaultQuotaOrder.contains(id) && !ordered.contains(id)) {
        ordered.add(id);
      }
    }
    for (final id in defaultQuotaOrder) {
      if (!ordered.contains(id)) ordered.add(id);
    }
    return ordered;
  }

  /// 展开面板和收起态实际使用的额度服务。
  List<String> get visibleQuotaProviders => orderedQuotaProviders
      .where((id) => !hiddenQuotaProviders.contains(id))
      .toList(growable: false);

  /// [includeRuntime] 为 true 时带上只读凭据状态，只用于设置窗口的启动参数。
  /// 写回 sidecar 时必须保持默认 false，否则派生键会混进 settings.set。
  Map<String, dynamic> toJson({bool includeRuntime = false}) => {
    'themeId': themeId,
    'showWeather': showWeather,
    'mediaEnabled': mediaEnabled,
    'showPlayingIndicator': showPlayingIndicator,
    'showImeIndicator': showImeIndicator,
    'showImeBanner': showImeBanner,
    'tabOrder': tabOrder,
    'hiddenTabs': hiddenTabs,
    'dockSide': dockSide,
    if (dockOffset != null) 'dockOffset': dockOffset,
    'translateProvider': translateProvider,
    'translateBaseUrl': translateBaseUrl,
    'translateModel': translateModel,
    'translateTarget': translateTarget,
    'translateSource': translateSource,
    'translateAutoOrder': translateAutoOrder,
    'translateUserPrompt': translateUserPrompt,
    'translateSystemPrompt': translateSystemPrompt,
    'translateMyMemoryEmail': translateMyMemoryEmail,
    'mailPollSeconds': mailPollSeconds,
    'mailTranslateProvider': mailTranslateProvider,
    'quotaOrder': quotaOrder,
    'hiddenQuotaProviders': hiddenQuotaProviders,
    'quotaGlmRegion': quotaGlmRegion,
    if (includeRuntime) ...{
      'translateLlmKeyConfigured': translateLlmKeyConfigured,
      'translateDeeplKeyConfigured': translateDeeplKeyConfigured,
      'translateCaiyunKeyConfigured': translateCaiyunKeyConfigured,
      'quotaGlmKeyConfigured': quotaGlmKeyConfigured,
      'quotaDeepseekKeyConfigured': quotaDeepseekKeyConfigured,
      'quotaOpencodeKeyConfigured': quotaOpencodeKeyConfigured,
      'quotaOpencodeCookieConfigured': quotaOpencodeCookieConfigured,
    },
  };

  AppSettings copyWith({
    String? themeId,
    bool? showWeather,
    bool? mediaEnabled,
    bool? showPlayingIndicator,
    bool? showImeIndicator,
    bool? showImeBanner,
    List<String>? tabOrder,
    List<String>? hiddenTabs,
    String? dockSide,
    double? dockOffset,
    String? translateProvider,
    String? translateBaseUrl,
    String? translateModel,
    String? translateTarget,
    String? translateSource,
    List<String>? translateAutoOrder,
    String? translateUserPrompt,
    String? translateSystemPrompt,
    String? translateMyMemoryEmail,
    bool? translateLlmKeyConfigured,
    bool? translateDeeplKeyConfigured,
    bool? translateCaiyunKeyConfigured,
    int? mailPollSeconds,
    String? mailTranslateProvider,
    List<String>? quotaOrder,
    List<String>? hiddenQuotaProviders,
    String? quotaGlmRegion,
    bool? quotaGlmKeyConfigured,
    bool? quotaDeepseekKeyConfigured,
    bool? quotaOpencodeKeyConfigured,
    bool? quotaOpencodeCookieConfigured,
  }) {
    return AppSettings(
      themeId: themeId ?? this.themeId,
      showWeather: showWeather ?? this.showWeather,
      mediaEnabled: mediaEnabled ?? this.mediaEnabled,
      showPlayingIndicator: showPlayingIndicator ?? this.showPlayingIndicator,
      showImeIndicator: showImeIndicator ?? this.showImeIndicator,
      showImeBanner: showImeBanner ?? this.showImeBanner,
      tabOrder: tabOrder ?? this.tabOrder,
      hiddenTabs: hiddenTabs ?? this.hiddenTabs,
      dockSide: dockSide ?? this.dockSide,
      dockOffset: dockOffset ?? this.dockOffset,
      translateProvider: translateProvider ?? this.translateProvider,
      translateBaseUrl: translateBaseUrl ?? this.translateBaseUrl,
      translateModel: translateModel ?? this.translateModel,
      translateTarget: translateTarget ?? this.translateTarget,
      translateSource: translateSource ?? this.translateSource,
      translateAutoOrder: translateAutoOrder ?? this.translateAutoOrder,
      translateUserPrompt: translateUserPrompt ?? this.translateUserPrompt,
      translateSystemPrompt: translateSystemPrompt ?? this.translateSystemPrompt,
      translateMyMemoryEmail:
          translateMyMemoryEmail ?? this.translateMyMemoryEmail,
      translateLlmKeyConfigured:
          translateLlmKeyConfigured ?? this.translateLlmKeyConfigured,
      translateDeeplKeyConfigured:
          translateDeeplKeyConfigured ?? this.translateDeeplKeyConfigured,
      translateCaiyunKeyConfigured:
          translateCaiyunKeyConfigured ?? this.translateCaiyunKeyConfigured,
      mailPollSeconds: mailPollSeconds ?? this.mailPollSeconds,
      mailTranslateProvider:
          mailTranslateProvider ?? this.mailTranslateProvider,
      quotaOrder: quotaOrder ?? this.quotaOrder,
      hiddenQuotaProviders:
          hiddenQuotaProviders ?? this.hiddenQuotaProviders,
      quotaGlmRegion: quotaGlmRegion ?? this.quotaGlmRegion,
      quotaGlmKeyConfigured:
          quotaGlmKeyConfigured ?? this.quotaGlmKeyConfigured,
      quotaDeepseekKeyConfigured:
          quotaDeepseekKeyConfigured ?? this.quotaDeepseekKeyConfigured,
      quotaOpencodeKeyConfigured:
          quotaOpencodeKeyConfigured ?? this.quotaOpencodeKeyConfigured,
      quotaOpencodeCookieConfigured:
          quotaOpencodeCookieConfigured ?? this.quotaOpencodeCookieConfigured,
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

  static String _normalizeDockSide(Object? raw) =>
      raw == 'left' || raw == 'right' ? raw as String : 'top';

  static List<String> _normalizeTranslateAutoOrder(Object? raw) {
    final ids = <String>[];
    if (raw is List) {
      for (final value in raw) {
        final id = value.toString();
        if (defaultTranslateAutoOrder.contains(id) && !ids.contains(id)) {
          ids.add(id);
        }
      }
    }
    for (final id in defaultTranslateAutoOrder) {
      if (!ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  static int _normalizeMailPollSeconds(Object? raw) {
    final value = raw is num ? raw.toInt() : defaultMailPollSeconds;
    if (value < 60) return 60;
    if (value > 900) return 900;
    return value;
  }

  static String _normalizeTranslateProvider(Object? raw) {
    const providers = {
      'auto',
      'llm',
      'deepl',
      'caiyun',
      'microsoftFree',
      'mymemory',
    };
    final value = raw?.toString();
    return providers.contains(value) ? value! : 'auto';
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

  static List<String> _normalizeQuotaOrder(Object? raw) {
    final ids = <String>[];
    if (raw is List) {
      for (final value in raw) {
        final id = value.toString();
        if (defaultQuotaOrder.contains(id) && !ids.contains(id)) ids.add(id);
      }
    }
    for (final id in defaultQuotaOrder) {
      if (!ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  static List<String> _normalizeHiddenQuotaProviders(Object? raw) {
    final ids = <String>[];
    if (raw is List) {
      for (final value in raw) {
        final id = value.toString();
        if (defaultQuotaOrder.contains(id) && !ids.contains(id)) ids.add(id);
      }
    }
    return ids;
  }
}
