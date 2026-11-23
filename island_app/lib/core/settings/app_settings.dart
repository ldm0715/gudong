import 'island_tabs.dart';

/// 用户设置。持久化由 sidecar 负责，字段名与 config.json 保持一致。
class AppSettings {
  const AppSettings({
    this.themeId = 'midnight',
    this.showWeather = true,
    this.weatherLocationMode = 'auto',
    this.weatherLocationName = '',
    this.weatherLatitude,
    this.weatherLongitude,
    this.mediaEnabled = true,
    this.showPlayingIndicator = true,
    this.showImeIndicator = true,
    this.showImeBanner = true,
    this.showScheduleIndicator = true,
    this.enabledAgents = defaultEnabledAgents,
    this.showAgentIndicator = true,
    this.showAgentBanner = true,
    this.autoCollapseOnMaximized = true,
    this.tabOrder = defaultTabOrder,
    this.hiddenTabs = const [],
    this.dashboardMetrics = defaultDashboardMetrics,
    this.islandMetrics = const [],
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
    this.quotaNewApiSites = const [],
    this.quotaNewApiKeyConfigured = const {},
    this.quotaNewApiAccessTokenConfigured = const {},
    this.quotaKrillBaseUrl = defaultQuotaKrillBaseUrl,
    this.quotaKrillTokenConfigured = false,
    this.shelfMaxItems = defaultShelfMaxItems,
    this.shelfViewMode = 'list',
  });

  static const List<String> defaultTabOrder = [
    'messages',
    'mail',
    'translate',
    'weather',
    'media',
    'quota',
    'dashboard',
    'schedule',
    'diagnostics',
  ];

  static const List<String> defaultQuotaOrder = [
    'glm',
    'deepseek',
    'opencode',
    'krill',
  ];

  static const String defaultQuotaKrillBaseUrl = 'https://www.krill-code.com';

  /// 默认开启检测的本地 agent。
  static const List<String> defaultEnabledAgents = [
    'claude',
    'codex',
    'dsh',
    'pi',
    'omp',
  ];

  /// 收起态最多显示的指标数量，超出部分在解析时丢弃。
  static const int maxIslandMetrics = 2;

  static const List<String> defaultDashboardMetrics = [
    'upload',
    'download',
    'network',
    'cpu',
    'memory',
    'gpu',
    'gpuMemory',
    'cpuFrequency',
    'totalTraffic',
  ];

  static const int defaultMailPollSeconds = 180;

  static const int defaultShelfMaxItems = 100;

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
      weatherLocationMode: json['weatherLocationMode'] == 'manual'
          ? 'manual'
          : 'auto',
      weatherLocationName: json['weatherLocationName']?.toString() ?? '',
      weatherLatitude: (json['weatherLatitude'] as num?)?.toDouble(),
      weatherLongitude: (json['weatherLongitude'] as num?)?.toDouble(),
      mediaEnabled: json['mediaEnabled'] != false,
      showPlayingIndicator: json['showPlayingIndicator'] != false,
      showImeIndicator: json['showImeIndicator'] != false,
      showImeBanner: json['showImeBanner'] != false,
      showScheduleIndicator: json['showScheduleIndicator'] != false,
      enabledAgents: _normalizeAgents(json['enabledAgents']),
      showAgentIndicator: json['showAgentIndicator'] != false,
      showAgentBanner: json['showAgentBanner'] != false,
      autoCollapseOnMaximized: json['autoCollapseOnMaximized'] != false,
      tabOrder: _normalizeOrder(json['tabOrder']),
      hiddenTabs: _normalizeHidden(json['hiddenTabs']),
      dashboardMetrics: _normalizeMetrics(
        json['dashboardMetrics'],
        allByDefault: true,
      ),
      islandMetrics: _normalizeMetrics(
        json['islandMetrics'],
        allByDefault: false,
        maxCount: maxIslandMetrics,
      ),
      dockSide: _normalizeDockSide(json['dockSide']),
      dockOffset: (json['dockOffset'] as num?)?.toDouble(),
      translateProvider: _normalizeTranslateProvider(json['translateProvider']),
      translateBaseUrl:
          json['translateBaseUrl']?.toString() ?? 'https://api.openai.com/v1',
      translateModel: json['translateModel']?.toString() ?? '',
      translateTarget: json['translateTarget']?.toString() ?? 'zh-CN',
      translateSource: json['translateSource']?.toString() ?? 'auto',
      translateAutoOrder: _normalizeTranslateAutoOrder(
        json['translateAutoOrder'],
      ),
      translateUserPrompt:
          json['translateUserPrompt']?.toString() ?? defaultTranslateUserPrompt,
      translateSystemPrompt: json['translateSystemPrompt']?.toString() ?? '',
      translateMyMemoryEmail: json['translateMyMemoryEmail']?.toString() ?? '',
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
      quotaDeepseekKeyConfigured: json['quotaDeepseekKeyConfigured'] == true,
      quotaOpencodeKeyConfigured: json['quotaOpencodeKeyConfigured'] == true,
      quotaOpencodeCookieConfigured:
          json['quotaOpencodeCookieConfigured'] == true,
      quotaNewApiSites: _normalizeNewApiSites(json['quotaNewApiSites']),
      quotaNewApiKeyConfigured: _normalizeBoolMap(
        json['quotaNewApiKeyConfigured'],
      ),
      quotaNewApiAccessTokenConfigured: _normalizeBoolMap(
        json['quotaNewApiAccessTokenConfigured'],
      ),
      quotaKrillBaseUrl:
          json['quotaKrillBaseUrl']?.toString() ?? defaultQuotaKrillBaseUrl,
      quotaKrillTokenConfigured: json['quotaKrillTokenConfigured'] == true,
      shelfMaxItems: _normalizeShelfMaxItems(json['shelfMaxItems']),
      shelfViewMode: _normalizeShelfViewMode(json['shelfViewMode']),
    );
  }

  final String themeId;
  final bool showWeather;

  /// 天气定位方式：`auto` 按出口 IP 定位，`manual` 使用下方坐标。
  final String weatherLocationMode;
  final String weatherLocationName;
  final double? weatherLatitude;
  final double? weatherLongitude;
  final bool mediaEnabled;
  final bool showPlayingIndicator;

  /// 收起态常驻显示当前输入法模式。
  final bool showImeIndicator;

  /// 输入法切换时弹出横幅。
  final bool showImeBanner;

  /// 当天有日程时在收起态显示闹钟图标。
  final bool showScheduleIndicator;

  /// 开启检测的本地 agent id。
  final List<String> enabledAgents;

  /// 运行中在收起态显示 agent 图标。
  final bool showAgentIndicator;

  /// 回合结束时弹出横幅。
  final bool showAgentBanner;

  /// 前台窗口最大化时只保留一条横杠，点击后显示收起态。
  final bool autoCollapseOnMaximized;
  final List<String> tabOrder;
  final List<String> hiddenTabs;

  /// 仪表盘展开面板显示的指标 id。
  final List<String> dashboardMetrics;

  /// 收起态显示的指标 id。
  final List<String> islandMetrics;

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

  /// 额度服务顺序：`glm` / `deepseek` / `opencode` / `newapi:<siteId>`。
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

  /// New API 站点列表，每个站点独立保存地址、凭据与顺序。
  final List<QuotaNewApiSite> quotaNewApiSites;

  /// 只读派生状态：站点 id → 是否已保存对应凭据，不写回 config.json。
  final Map<String, bool> quotaNewApiKeyConfigured;
  final Map<String, bool> quotaNewApiAccessTokenConfigured;

  /// Krill Code 站点地址与 JWT 状态。
  final String quotaKrillBaseUrl;
  final bool quotaKrillTokenConfigured;

  /// 中转站条目上限，引用式存储只限制列表长度。
  final int shelfMaxItems;

  /// 中转站默认视图：`list`（列表）或 `grid`（图标网格）。
  final String shelfViewMode;

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
      if (_quotaProviderKnown(id) && !ordered.contains(id)) ordered.add(id);
    }
    for (final id in defaultQuotaOrder) {
      if (!ordered.contains(id)) ordered.add(id);
    }
    for (final site in quotaNewApiSites) {
      final id = site.providerId;
      if (site.ready && !ordered.contains(id)) ordered.add(id);
    }
    return ordered;
  }

  /// 展开面板和收起态实际使用的额度服务。
  /// Krill 未保存 JWT 前不占用面板空间。
  List<String> get visibleQuotaProviders => orderedQuotaProviders
      .where((id) => !hiddenQuotaProviders.contains(id))
      .where((id) => id != 'krill' || quotaKrillTokenConfigured)
      .toList(growable: false);

  QuotaNewApiSite? newApiSite(String id) {
    for (final site in quotaNewApiSites) {
      if (site.id == id) return site;
    }
    return null;
  }

  bool _quotaProviderKnown(String id) {
    if (defaultQuotaOrder.contains(id)) return true;
    if (!id.startsWith(QuotaNewApiSite.providerPrefix)) return false;
    final site = newApiSite(id.substring(QuotaNewApiSite.providerPrefix.length));
    return site?.ready == true;
  }

  /// [includeRuntime] 为 true 时带上只读凭据状态，只用于设置窗口的启动参数。
  /// 写回 sidecar 时必须保持默认 false，否则派生键会混进 settings.set。
  Map<String, dynamic> toJson({bool includeRuntime = false}) => {
    'themeId': themeId,
    'showWeather': showWeather,
    'weatherLocationMode': weatherLocationMode,
    'weatherLocationName': weatherLocationName,
    if (weatherLatitude != null) 'weatherLatitude': weatherLatitude,
    if (weatherLongitude != null) 'weatherLongitude': weatherLongitude,
    'mediaEnabled': mediaEnabled,
    'showPlayingIndicator': showPlayingIndicator,
    'showImeIndicator': showImeIndicator,
    'showImeBanner': showImeBanner,
    'showScheduleIndicator': showScheduleIndicator,
    'enabledAgents': enabledAgents,
    'showAgentIndicator': showAgentIndicator,
    'showAgentBanner': showAgentBanner,
    'autoCollapseOnMaximized': autoCollapseOnMaximized,
    'tabOrder': tabOrder,
    'hiddenTabs': hiddenTabs,
    'dashboardMetrics': dashboardMetrics,
    'islandMetrics': islandMetrics,
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
    'quotaNewApiSites': [
      for (final site in quotaNewApiSites) site.toJson(),
    ],
    'quotaKrillBaseUrl': quotaKrillBaseUrl,
    'shelfMaxItems': shelfMaxItems,
    'shelfViewMode': shelfViewMode,
    if (includeRuntime) ...{
      'translateLlmKeyConfigured': translateLlmKeyConfigured,
      'translateDeeplKeyConfigured': translateDeeplKeyConfigured,
      'translateCaiyunKeyConfigured': translateCaiyunKeyConfigured,
      'quotaGlmKeyConfigured': quotaGlmKeyConfigured,
      'quotaDeepseekKeyConfigured': quotaDeepseekKeyConfigured,
      'quotaOpencodeKeyConfigured': quotaOpencodeKeyConfigured,
      'quotaOpencodeCookieConfigured': quotaOpencodeCookieConfigured,
      'quotaNewApiKeyConfigured': quotaNewApiKeyConfigured,
      'quotaNewApiAccessTokenConfigured': quotaNewApiAccessTokenConfigured,
      'quotaKrillTokenConfigured': quotaKrillTokenConfigured,
    },
  };

  AppSettings copyWith({
    String? themeId,
    bool? showWeather,
    String? weatherLocationMode,
    String? weatherLocationName,
    double? weatherLatitude,
    double? weatherLongitude,
    bool? mediaEnabled,
    bool? showPlayingIndicator,
    bool? showImeIndicator,
    bool? showImeBanner,
    bool? showScheduleIndicator,
    List<String>? enabledAgents,
    bool? showAgentIndicator,
    bool? showAgentBanner,
    bool? autoCollapseOnMaximized,
    List<String>? tabOrder,
    List<String>? hiddenTabs,
    List<String>? dashboardMetrics,
    List<String>? islandMetrics,
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
    List<QuotaNewApiSite>? quotaNewApiSites,
    Map<String, bool>? quotaNewApiKeyConfigured,
    Map<String, bool>? quotaNewApiAccessTokenConfigured,
    String? quotaKrillBaseUrl,
    bool? quotaKrillTokenConfigured,
    int? shelfMaxItems,
    String? shelfViewMode,
  }) {
    return AppSettings(
      themeId: themeId ?? this.themeId,
      showWeather: showWeather ?? this.showWeather,
      weatherLocationMode: weatherLocationMode ?? this.weatherLocationMode,
      weatherLocationName: weatherLocationName ?? this.weatherLocationName,
      weatherLatitude: weatherLatitude ?? this.weatherLatitude,
      weatherLongitude: weatherLongitude ?? this.weatherLongitude,
      mediaEnabled: mediaEnabled ?? this.mediaEnabled,
      showPlayingIndicator: showPlayingIndicator ?? this.showPlayingIndicator,
      showImeIndicator: showImeIndicator ?? this.showImeIndicator,
      showImeBanner: showImeBanner ?? this.showImeBanner,
      showScheduleIndicator:
          showScheduleIndicator ?? this.showScheduleIndicator,
      enabledAgents: enabledAgents == null
          ? this.enabledAgents
          : _normalizeAgents(enabledAgents),
      showAgentIndicator: showAgentIndicator ?? this.showAgentIndicator,
      showAgentBanner: showAgentBanner ?? this.showAgentBanner,
      autoCollapseOnMaximized:
          autoCollapseOnMaximized ?? this.autoCollapseOnMaximized,
      tabOrder: tabOrder ?? this.tabOrder,
      hiddenTabs: hiddenTabs ?? this.hiddenTabs,
      dashboardMetrics: dashboardMetrics ?? this.dashboardMetrics,
      islandMetrics: islandMetrics == null
          ? this.islandMetrics
          : _normalizeMetrics(
              islandMetrics,
              allByDefault: false,
              maxCount: maxIslandMetrics,
            ),
      dockSide: dockSide ?? this.dockSide,
      dockOffset: dockOffset ?? this.dockOffset,
      translateProvider: translateProvider ?? this.translateProvider,
      translateBaseUrl: translateBaseUrl ?? this.translateBaseUrl,
      translateModel: translateModel ?? this.translateModel,
      translateTarget: translateTarget ?? this.translateTarget,
      translateSource: translateSource ?? this.translateSource,
      translateAutoOrder: translateAutoOrder ?? this.translateAutoOrder,
      translateUserPrompt: translateUserPrompt ?? this.translateUserPrompt,
      translateSystemPrompt:
          translateSystemPrompt ?? this.translateSystemPrompt,
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
      hiddenQuotaProviders: hiddenQuotaProviders ?? this.hiddenQuotaProviders,
      quotaGlmRegion: quotaGlmRegion ?? this.quotaGlmRegion,
      quotaGlmKeyConfigured:
          quotaGlmKeyConfigured ?? this.quotaGlmKeyConfigured,
      quotaDeepseekKeyConfigured:
          quotaDeepseekKeyConfigured ?? this.quotaDeepseekKeyConfigured,
      quotaOpencodeKeyConfigured:
          quotaOpencodeKeyConfigured ?? this.quotaOpencodeKeyConfigured,
      quotaOpencodeCookieConfigured:
          quotaOpencodeCookieConfigured ?? this.quotaOpencodeCookieConfigured,
      quotaNewApiSites: quotaNewApiSites ?? this.quotaNewApiSites,
      quotaNewApiKeyConfigured:
          quotaNewApiKeyConfigured ?? this.quotaNewApiKeyConfigured,
      quotaNewApiAccessTokenConfigured:
          quotaNewApiAccessTokenConfigured ??
          this.quotaNewApiAccessTokenConfigured,
      quotaKrillBaseUrl: quotaKrillBaseUrl ?? this.quotaKrillBaseUrl,
      quotaKrillTokenConfigured:
          quotaKrillTokenConfigured ?? this.quotaKrillTokenConfigured,
      shelfMaxItems: shelfMaxItems ?? this.shelfMaxItems,
      shelfViewMode: shelfViewMode ?? this.shelfViewMode,
    );
  }

  /// 指标顺序固定，未出现在列表中的 id 视为关闭。
  static List<String> _normalizeMetrics(
    Object? raw, {
    required bool allByDefault,
    int? maxCount,
  }) {
    if (raw is! List) {
      return allByDefault ? List<String>.of(defaultDashboardMetrics) : const [];
    }
    final ids = raw.map((value) => value.toString()).toSet();
    final metrics = [
      for (final id in defaultDashboardMetrics)
        if (ids.contains(id)) id,
    ];
    if (maxCount == null || metrics.length <= maxCount) return metrics;
    return metrics.take(maxCount).toList(growable: false);
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

  static String _normalizeShelfViewMode(Object? raw) =>
      raw == 'grid' ? 'grid' : 'list';

  static int _normalizeShelfMaxItems(Object? raw) {
    final value = raw is num ? raw.toInt() : defaultShelfMaxItems;
    if (value < 10) return 10;
    if (value > 500) return 500;
    return value;
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

  static List<String> _normalizeAgents(Object? raw) {
    if (raw is! List) return List<String>.of(defaultEnabledAgents);
    final ids = <String>{};
    for (final value in raw) {
      final id = value.toString();
      if (defaultEnabledAgents.contains(id)) ids.add(id);
    }
    return [
      for (final id in defaultEnabledAgents)
        if (ids.contains(id)) id,
    ];
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
        if (_isQuotaProviderId(id) && !ids.contains(id)) ids.add(id);
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
        if (_isQuotaProviderId(id) && !ids.contains(id)) ids.add(id);
      }
    }
    return ids;
  }

  static bool _isQuotaProviderId(String id) =>
      defaultQuotaOrder.contains(id) ||
      id.startsWith(QuotaNewApiSite.providerPrefix);

  static List<QuotaNewApiSite> _normalizeNewApiSites(Object? raw) {
    if (raw is! List) return const [];
    final sites = <QuotaNewApiSite>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final site = QuotaNewApiSite.fromJson(Map<String, dynamic>.from(item));
      if (site.id.isEmpty || ids.contains(site.id)) continue;
      ids.add(site.id);
      sites.add(site);
    }
    return sites;
  }

  static Map<String, bool> _normalizeBoolMap(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, bool>{};
    raw.forEach((key, value) {
      if (value == true) result[key.toString()] = true;
    });
    return result;
  }
}

/// 一个 New API 站点。凭据单独放在 Windows 凭据管理器。
class QuotaNewApiSite {
  const QuotaNewApiSite({
    required this.id,
    this.name = '',
    this.baseUrl = '',
    this.mode = 'account',
    this.userId = '',
    this.quotaPerUnit = 0,
    this.currencySymbol = '',
  });

  factory QuotaNewApiSite.fromJson(Map<String, dynamic> json) {
    return QuotaNewApiSite(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      mode: json['mode'] == 'token' ? 'token' : 'account',
      userId: json['userId']?.toString() ?? '',
      quotaPerUnit: (json['quotaPerUnit'] as num?)?.toDouble() ?? 0,
      currencySymbol: json['currencySymbol']?.toString() ?? '',
    );
  }

  static const String providerPrefix = 'newapi:';

  final String id;
  final String name;
  final String baseUrl;
  final String mode;
  final String userId;

  /// 手动换算比例：1 货币单位 = 多少配额；`0` 表示自动读取 `/api/status`。
  final double quotaPerUnit;

  /// 手动货币符号；为空表示自动。
  final String currencySymbol;

  String get providerId => '$providerPrefix$id';

  bool get ready => baseUrl.trim().isNotEmpty;

  bool get accountMode => mode != 'token';

  String get label {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final uri = Uri.tryParse(baseUrl.trim());
    final host = uri?.host ?? '';
    return host.isEmpty ? 'New API' : 'New API · $host';
  }

  QuotaNewApiSite copyWith({
    String? name,
    String? baseUrl,
    String? mode,
    String? userId,
    double? quotaPerUnit,
    String? currencySymbol,
  }) {
    return QuotaNewApiSite(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      mode: mode ?? this.mode,
      userId: userId ?? this.userId,
      quotaPerUnit: quotaPerUnit ?? this.quotaPerUnit,
      currencySymbol: currencySymbol ?? this.currencySymbol,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'mode': mode,
    'userId': userId,
    'quotaPerUnit': quotaPerUnit,
    'currencySymbol': currencySymbol,
  };
}
