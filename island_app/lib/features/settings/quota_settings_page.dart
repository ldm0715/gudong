import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/log.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../quota/quota_bridge.dart';
import '../quota/quota_icons.dart';
import 'settings_panel.dart';

class _QuotaProviderMeta {
  const _QuotaProviderMeta({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

const List<_QuotaProviderMeta> _builtinProviders = [
  _QuotaProviderMeta(
    id: 'glm',
    label: 'GLM',
    description: 'Z.ai / 智谱 Coding Plan 的 5 小时与周额度',
  ),
  _QuotaProviderMeta(
    id: 'deepseek',
    label: 'DeepSeek',
    description: 'DeepSeek 账户余额',
  ),
  _QuotaProviderMeta(
    id: 'opencode',
    label: 'OpenCode',
    description: 'OpenCode Go 额度与 Zen 余额',
  ),
  _QuotaProviderMeta(
    id: 'krill',
    label: 'Krill Code',
    description: 'Krill AI 的套餐用量与账户余额',
  ),
];

/// 下拉框和排序列表共用的一项，New API 站点会带上站点数据。
class _ProviderEntry {
  const _ProviderEntry({
    required this.id,
    required this.label,
    required this.description,
    this.site,
  });

  final String id;
  final String label;
  final String description;
  final QuotaNewApiSite? site;
}

const String _addNewApiValue = '__add_newapi__';

/// AI - 额度设置：选择服务后只显示对应凭据，New API 支持添加多个站点。
class QuotaSettingsPage extends StatefulWidget {
  const QuotaSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  State<QuotaSettingsPage> createState() => _QuotaSettingsPageState();
}

class _QuotaSettingsPageState extends State<QuotaSettingsPage> {
  final TextEditingController _glmKey = TextEditingController();
  final TextEditingController _deepseekKey = TextEditingController();
  final TextEditingController _opencodeKey = TextEditingController();
  final TextEditingController _opencodeCookie = TextEditingController();
  final TextEditingController _krillToken = TextEditingController();
  late final TextEditingController _krillBaseUrl = TextEditingController(
    text: widget.settings.quotaKrillBaseUrl,
  );
  final TextEditingController _newApiKey = TextEditingController();
  final TextEditingController _newApiAccessToken = TextEditingController();
  final Map<String, TextEditingController> _siteNames = {};
  final Map<String, TextEditingController> _siteBaseUrls = {};
  final Map<String, TextEditingController> _siteUserIds = {};
  final Map<String, TextEditingController> _siteRates = {};

  late bool _glmConfigured = widget.settings.quotaGlmKeyConfigured;
  late bool _deepseekConfigured = widget.settings.quotaDeepseekKeyConfigured;
  late bool _opencodeKeyConfigured =
      widget.settings.quotaOpencodeKeyConfigured;
  late bool _opencodeCookieConfigured =
      widget.settings.quotaOpencodeCookieConfigured;
  late bool _krillConfigured = widget.settings.quotaKrillTokenConfigured;
  late final Map<String, bool> _newApiKeysConfigured = Map.of(
    widget.settings.quotaNewApiKeyConfigured,
  );
  late final Map<String, bool> _newApiTokensConfigured = Map.of(
    widget.settings.quotaNewApiAccessTokenConfigured,
  );
  late String _selectedProvider = widget.settings.orderedQuotaProviders.first;
  Map<String, String> _logos = const {};
  Map<String, String> _labels = const {};
  Timer? _brandingTimer;
  String _status = '';
  bool _busy = false;

  IslandColors get _colors => context.islandColors;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLogos());
    // 设置窗口早于 sidecar 首次刷新时，定时从快照里补齐站点图标与名称。
    _brandingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_loadLogos()),
    );
  }

  bool _sameMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _loadLogos() async {
    try {
      final result = await quotaChannel.invokeMethod<dynamic>('get');
      final raw = result is Map ? result['providers'] : null;
      if (raw is! List) return;
      final logos = <String, String>{};
      final labels = <String, String>{};
      for (final item in raw) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id is! String) continue;
        final logo = item['logo'];
        if (logo is String && logo.isNotEmpty) logos[id] = logo;
        final label = item['label'];
        if (label is String && label.trim().isNotEmpty) {
          labels[id] = label.trim();
        }
      }
      final nextLogos = {..._logos, ...logos};
      final nextLabels = {..._labels, ...labels};
      if (mounted &&
          (!_sameMap(_logos, nextLogos) || !_sameMap(_labels, nextLabels))) {
        setState(() {
          _logos = nextLogos;
          _labels = nextLabels;
        });
      }
    } catch (error) {
      AppLog.write('[quota] load logos failed: $error');
    }
  }

  @override
  void dispose() {
    _brandingTimer?.cancel();
    for (final controller in [
      _glmKey,
      _deepseekKey,
      _opencodeKey,
      _opencodeCookie,
      _krillToken,
      _krillBaseUrl,
      _newApiKey,
      _newApiAccessToken,
      ..._siteNames.values,
      ..._siteBaseUrls.values,
      ..._siteUserIds.values,
      ..._siteRates.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _nameController(QuotaNewApiSite site) =>
      _siteNames.putIfAbsent(
        site.id,
        () => TextEditingController(text: site.name),
      );

  TextEditingController _baseUrlController(QuotaNewApiSite site) =>
      _siteBaseUrls.putIfAbsent(
        site.id,
        () => TextEditingController(text: site.baseUrl),
      );

  TextEditingController _userIdController(QuotaNewApiSite site) =>
      _siteUserIds.putIfAbsent(
        site.id,
        () => TextEditingController(text: site.userId),
      );

  TextEditingController _rateController(QuotaNewApiSite site) =>
      _siteRates.putIfAbsent(
        site.id,
        () => TextEditingController(
          text: site.quotaPerUnit > 0 ? site.quotaPerUnit.toString() : '',
        ),
      );


  Future<void> _saveSecret(
    String provider,
    String field,
    TextEditingController controller,
    void Function(bool configured) apply,
    void Function(bool configured) markSettings, {
    String? siteId,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await quotaChannel.invokeMethod<dynamic>('setSecret', {
        'provider': provider,
        'siteId': ?siteId,
        'field': field,
        'value': controller.text.trim(),
      });
      final configured = result is Map && result['configured'] == true;
      if (!mounted) return;
      setState(() {
        apply(configured);
        _status = configured ? '已保存' : '已清除';
      });
      markSettings(configured);
      if (configured) controller.clear();
    } catch (error) {
      AppLog.write('[quota] save secret failed: $error');
      if (mounted) setState(() => _status = '保存失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearSecret(
    String provider,
    String field,
    TextEditingController controller,
    void Function(bool configured) apply,
    void Function(bool configured) markSettings, {
    String? siteId,
  }) {
    controller.clear();
    unawaited(
      _saveSecret(
        provider,
        field,
        controller,
        apply,
        markSettings,
        siteId: siteId,
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      await quotaChannel.invokeMethod<dynamic>('refresh', const {});
      if (mounted) setState(() => _status = '已请求刷新');
    } catch (error) {
      AppLog.write('[quota] refresh failed: $error');
      if (mounted) setState(() => _status = '刷新失败');
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await quotaChannel.invokeMethod<dynamic>('openUrl', {'url': url});
    } catch (error) {
      AppLog.write('[quota] open url failed: $error');
    }
  }

  String get _glmUrl => widget.settings.quotaGlmRegion == 'bigmodel-cn'
      ? 'https://bigmodel.cn/coding-plan/personal/usage'
      : 'https://z.ai/manage-apikey/coding-plan/personal/my-plan';

  List<_ProviderEntry> _providerEntries(AppSettings settings) {
    return [
      for (final meta in _builtinProviders)
        _ProviderEntry(
          id: meta.id,
          label: meta.label,
          description: meta.description,
        ),
      for (final site in settings.quotaNewApiSites)
        _ProviderEntry(
          id: site.providerId,
          label: _siteLabel(site),
          description: site.ready
              ? 'New API · ${site.baseUrl.trim()}'
              : 'New API 站点，尚未填写地址',
          site: site,
        ),
    ];
  }

  String _siteLabel(QuotaNewApiSite site) {
    final name = site.name.trim();
    if (name.isNotEmpty) return name;
    return _labels[site.providerId] ?? site.label;
  }

  _ProviderEntry _entryFor(
    List<_ProviderEntry> entries,
    String id,
  ) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return _ProviderEntry(id: id, label: id, description: '');
  }

  /// 服务是否至少有一个可用凭据。OpenCode 的 API Key 与 Cookie 任一存在即可。
  bool _configured(_ProviderEntry entry) {
    final site = entry.site;
    if (site != null) {
      if (!site.ready) return false;
      if (site.accountMode) {
        return _newApiTokensConfigured[site.id] == true &&
            site.userId.trim().isNotEmpty;
      }
      return _newApiKeysConfigured[site.id] == true;
    }
    return switch (entry.id) {
      'glm' => _glmConfigured,
      'deepseek' => _deepseekConfigured,
      'opencode' => _opencodeKeyConfigured || _opencodeCookieConfigured,
      'krill' => _krillConfigured,
      _ => false,
    };
  }

  void _setVisible(String id, bool visible) {
    final hidden = widget.settings.hiddenQuotaProviders.toList();
    if (visible) {
      hidden.remove(id);
    } else if (!hidden.contains(id)) {
      hidden.add(id);
    }
    widget.onSave(widget.settings.copyWith(hiddenQuotaProviders: hidden));
  }

  void _reorder(int oldIndex, int newIndex) {
    final ids = widget.settings.orderedQuotaProviders.toList();
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    if (newIndex < 0 || newIndex >= ids.length) return;
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    widget.onSave(widget.settings.copyWith(quotaOrder: ids));
  }

  void _selectProvider(String id) {
    final changed = id != _selectedProvider;
    setState(() => _selectedProvider = id);
    if (changed) {
      _newApiKey.clear();
      _newApiAccessToken.clear();
    }
  }

  void _addNewApiSite() {
    final site = QuotaNewApiSite(
      id: 'na_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
    );
    final order = widget.settings.orderedQuotaProviders.toList();
    if (!order.contains(site.providerId)) order.add(site.providerId);
    widget.onSave(
      widget.settings.copyWith(
        quotaNewApiSites: [...widget.settings.quotaNewApiSites, site],
        quotaOrder: order,
      ),
    );
    _selectProvider(site.providerId);
  }

  void _removeNewApiSite(QuotaNewApiSite site) {
    unawaited(_clearSiteSecrets(site.id));
    final order = widget.settings.quotaOrder.toList()
      ..remove(site.providerId);
    final hidden = widget.settings.hiddenQuotaProviders.toList()
      ..remove(site.providerId);
    widget.onSave(
      widget.settings.copyWith(
        quotaNewApiSites: [
          for (final item in widget.settings.quotaNewApiSites)
            if (item.id != site.id) item,
        ],
        quotaOrder: order,
        hiddenQuotaProviders: hidden,
      ),
    );
    _siteNames.remove(site.id)?.dispose();
    _siteBaseUrls.remove(site.id)?.dispose();
    _siteUserIds.remove(site.id)?.dispose();
    _siteRates.remove(site.id)?.dispose();
    if (_selectedProvider == site.providerId) {
      setState(() => _selectedProvider = 'glm');
    } else {
      setState(() {});
    }
  }

  Future<void> _clearSiteSecrets(String siteId) async {
    for (final field in ['apiKey', 'accessToken']) {
      try {
        await quotaChannel.invokeMethod<dynamic>('setSecret', {
          'provider': 'newapi',
          'siteId': siteId,
          'field': field,
          'value': '',
        });
      } catch (error) {
        AppLog.write('[quota] clear newapi secret failed: $error');
      }
    }
  }

  void _saveSiteMeta(QuotaNewApiSite site) {
    final name = _nameController(site).text.trim();
    final baseUrl = _baseUrlController(site).text.trim();
    final userId = _userIdController(site).text.trim();
    final rateText = _rateController(site).text.trim();
    final rate = rateText.isEmpty ? 0.0 : double.tryParse(rateText);
    if (rate == null || rate < 0) {
      setState(() => _status = '换算比例需为正数');
      return;
    }
    widget.onSave(
      widget.settings.copyWith(
        quotaNewApiSites: [
          for (final item in widget.settings.quotaNewApiSites)
            if (item.id == site.id)
              item.copyWith(
                name: name,
                baseUrl: baseUrl,
                userId: userId,
                quotaPerUnit: rate,
              )
            else
              item,
        ],
      ),
    );
    setState(() => _status = '已保存');
    // 站点地址变化后 sidecar 会重新抓取图标，稍后再取一次。
    unawaited(Future<void>.delayed(const Duration(seconds: 4), _loadLogos));
  }

  void _saveKrillBase() {
    widget.onSave(
      widget.settings.copyWith(
        quotaKrillBaseUrl: _krillBaseUrl.text.trim(),
      ),
    );
    setState(() => _status = '已保存');
  }

  void _saveSiteMode(QuotaNewApiSite site, String mode) {
    widget.onSave(
      widget.settings.copyWith(
        quotaNewApiSites: [
          for (final item in widget.settings.quotaNewApiSites)
            if (item.id == site.id) item.copyWith(mode: mode) else item,
        ],
      ),
    );
  }

  void _saveSiteCurrency(QuotaNewApiSite site, String symbol) {
    widget.onSave(
      widget.settings.copyWith(
        quotaNewApiSites: [
          for (final item in widget.settings.quotaNewApiSites)
            if (item.id == site.id)
              item.copyWith(currencySymbol: symbol)
            else
              item,
        ],
      ),
    );
  }

  String _currencyPreset(QuotaNewApiSite site) =>
      site.currencySymbol == '¥' || site.currencySymbol == r'$'
      ? site.currencySymbol
      : '';

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final entries = _providerEntries(settings);
    final selected = _entryFor(entries, _selectedProvider);
    final visible = !settings.hiddenQuotaProviders.contains(selected.id);
    final order = settings.orderedQuotaProviders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('服务'),
        SettingsCard(
          children: [
            SettingsRow(
              leading: QuotaProviderIcon(
                id: selected.id,
                logo: _logos[selected.id],
                fallback: selected.label.substring(0, 1),
                color: _colors.text,
                size: 20,
              ),
              title: '配置服务',
              subtitle: selected.description,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QuotaDropdown<String>(
                    value: selected.id,
                    width: 210,
                    entries: [
                      for (final entry in entries)
                        DropdownMenuEntry(
                          value: entry.id,
                          label: entry.label,
                        ),
                      const DropdownMenuEntry(
                        value: _addNewApiValue,
                        label: '＋ 添加 New API 站点',
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      if (value == _addNewApiValue) {
                        _addNewApiSite();
                      } else {
                        _selectProvider(value);
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  _QuotaStatusBadge(configured: _configured(selected)),
                ],
              ),
            ),
            const SettingsDivider(),
            SettingsSwitchRow(
              title: '在额度面板显示',
              subtitle: visible
                  ? '展开面板与收起态都会显示该服务'
                  : '已隐藏；仍可在上方配置凭据',
              value: visible,
              onChanged: (value) => _setVisible(selected.id, value),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ..._providerSections(settings, selected),
        const SizedBox(height: 18),
        const SettingsSectionLabel('排序'),
        SettingsCard(
          children: [
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorder: _reorder,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: _colors.cardBackground,
                  surfaceTintColor: Colors.transparent,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final id = order[index];
                final entry = _entryFor(entries, id);
                return Column(
                  key: ValueKey(id),
                  children: [
                    SettingsRow(
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                size: 18,
                                color: _colors.muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          QuotaProviderIcon(
                            id: id,
                            logo: _logos[id],
                            fallback: entry.label.substring(0, 1),
                            color: _colors.text,
                            size: 20,
                          ),
                        ],
                      ),
                      title: entry.label,
                      subtitle: entry.description,
                      trailing: _QuotaStatusBadge(
                        configured: _configured(entry),
                      ),
                    ),
                    if (index < order.length - 1) const SettingsDivider(),
                  ],
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '拖动右侧手柄调整额度面板顺序；用上方开关控制每个服务的显隐。',
            style: TextStyle(color: _colors.muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('刷新'),
        SettingsCard(
          children: [
            SettingsRow(
              title: '自动刷新',
              subtitle: 'sidecar 每 5 分钟拉取一次，失败后按设置间隔重试',
              trailing: FilledButton(
                onPressed: _busy ? null : () => unawaited(_refresh()),
                child: const Text('立即刷新'),
              ),
            ),
            if (_status.isNotEmpty) ...[
              const SettingsDivider(),
              SettingsRow(
                title: '状态',
                trailing: Text(
                  _status,
                  style: TextStyle(color: _colors.muted, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '凭据保存在 Windows 凭据管理器，不写入 config.json。'
            'OpenCode Cookie 只用于补充 Zen 余额，也可以只填 API Key。',
            style: TextStyle(color: _colors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  List<Widget> _providerSections(
    AppSettings settings,
    _ProviderEntry entry,
  ) {
    final site = entry.site;
    if (site != null) {
      return [const SettingsSectionLabel('New API'), _newApiCard(site)];
    }
    return switch (entry.id) {
      'glm' => [const SettingsSectionLabel('GLM'), _glmCard(settings)],
      'deepseek' => [
        const SettingsSectionLabel('DeepSeek'),
        _deepseekCard(),
      ],
      'opencode' => [
        const SettingsSectionLabel('OpenCode'),
        _opencodeCard(),
      ],
      'krill' => [const SettingsSectionLabel('Krill Code'), _krillCard()],
      _ => const [],
    };
  }

  Widget _glmCard(AppSettings settings) {
    return SettingsCard(
      children: [
        SettingsRow(
          title: '登录 / 获取凭据',
          subtitle: '登录后在控制台创建 API Key，无需手动抓 Cookie',
          trailing: TextButton(
            onPressed: () => unawaited(_openUrl(_glmUrl)),
            child: const Text('打开登录页'),
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          title: '接口区域',
          subtitle: 'Z.ai 国际站或智谱开放平台',
          trailing: _QuotaDropdown<String>(
            value: settings.quotaGlmRegion,
            width: 150,
            entries: const [
              DropdownMenuEntry(value: 'global', label: 'Z.ai 国际站'),
              DropdownMenuEntry(value: 'bigmodel-cn', label: '智谱开放平台'),
            ],
            onChanged: (value) {
              if (value == null) return;
              widget.onSave(settings.copyWith(quotaGlmRegion: value));
            },
          ),
        ),
        const SettingsDivider(),
        _CredentialField(
          title: 'API Key',
          hint: '粘贴 GLM API Key',
          configured: _glmConfigured,
          controller: _glmKey,
          busy: _busy,
          onSave: () => _saveSecret(
            'glm',
            'apiKey',
            _glmKey,
            (value) => _glmConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaGlmKeyConfigured: value),
            ),
          ),
          onClear: () => _clearSecret(
            'glm',
            'apiKey',
            _glmKey,
            (value) => _glmConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaGlmKeyConfigured: value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _deepseekCard() {
    return SettingsCard(
      children: [
        SettingsRow(
          title: '登录 / 获取凭据',
          subtitle: '登录后在控制台创建 API Key',
          trailing: TextButton(
            onPressed: () => unawaited(
              _openUrl('https://platform.deepseek.com/api_keys'),
            ),
            child: const Text('打开登录页'),
          ),
        ),
        const SettingsDivider(),
        _CredentialField(
          title: 'API Key',
          hint: '粘贴 DeepSeek API Key',
          configured: _deepseekConfigured,
          controller: _deepseekKey,
          busy: _busy,
          onSave: () => _saveSecret(
            'deepseek',
            'apiKey',
            _deepseekKey,
            (value) => _deepseekConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaDeepseekKeyConfigured: value),
            ),
          ),
          onClear: () => _clearSecret(
            'deepseek',
            'apiKey',
            _deepseekKey,
            (value) => _deepseekConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaDeepseekKeyConfigured: value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _opencodeCard() {
    return SettingsCard(
      children: [
        SettingsRow(
          title: '登录 / 获取凭据',
          subtitle: '登录后可在浏览器开发者工具里复制 Cookie',
          trailing: TextButton(
            onPressed: () => unawaited(_openUrl('https://opencode.ai/auth')),
            child: const Text('打开登录页'),
          ),
        ),
        const SettingsDivider(),
        _CredentialField(
          title: 'API Key',
          hint: '用于读取 Go 额度',
          configured: _opencodeKeyConfigured,
          controller: _opencodeKey,
          busy: _busy,
          onSave: () => _saveSecret(
            'opencode',
            'apiKey',
            _opencodeKey,
            (value) => _opencodeKeyConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaOpencodeKeyConfigured: value),
            ),
          ),
          onClear: () => _clearSecret(
            'opencode',
            'apiKey',
            _opencodeKey,
            (value) => _opencodeKeyConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaOpencodeKeyConfigured: value),
            ),
          ),
        ),
        const SettingsDivider(),
        _CredentialField(
          title: 'Cookie',
          hint: '可选；登录后复制浏览器 Cookie，用于读取 Zen 余额',
          configured: _opencodeCookieConfigured,
          controller: _opencodeCookie,
          busy: _busy,
          onSave: () => _saveSecret(
            'opencode',
            'cookie',
            _opencodeCookie,
            (value) => _opencodeCookieConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaOpencodeCookieConfigured: value),
            ),
          ),
          onClear: () => _clearSecret(
            'opencode',
            'cookie',
            _opencodeCookie,
            (value) => _opencodeCookieConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaOpencodeCookieConfigured: value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _krillCard() {
    return SettingsCard(
      children: [
        SettingsRow(
          title: '站点地址',
          subtitle: '默认 https://www.krill-code.com',
          trailing: SizedBox(
            width: 360,
            child: Row(
              children: [
                Expanded(
                  child: _textField(
                    _krillBaseUrl,
                    hint: AppSettings.defaultQuotaKrillBaseUrl,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _busy ? null : _saveKrillBase,
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
        const SettingsDivider(),
        _CredentialField(
          title: 'JWT',
          hint: '浏览器 localStorage 里的 krill_jwt',
          configured: _krillConfigured,
          controller: _krillToken,
          busy: _busy,
          onSave: () => _saveSecret(
            'krill',
            'jwt',
            _krillToken,
            (value) => _krillConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaKrillTokenConfigured: value),
            ),
          ),
          onClear: () => _clearSecret(
            'krill',
            'jwt',
            _krillToken,
            (value) => _krillConfigured = value,
            (value) => widget.onSave(
              widget.settings.copyWith(quotaKrillTokenConfigured: value),
            ),
          ),
        ),
        const SettingsDivider(),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(
              _openUrl('https://www.krill-code.com/'),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 14),
            label: const Text('打开 Krill Code'),
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: _colors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '登录网站后按 F12 → Application → Local Storage，'
                  '复制 krill_jwt。JWT 只用于读取套餐与余额；'
                  '有多个套餐时会逐个显示比例和到期日。',
                  style: TextStyle(
                    color: _colors.muted,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _newApiCard(QuotaNewApiSite site) {
    final accountMode = site.accountMode;
    return SettingsCard(
      children: [
        SettingsRow(
          title: '名称',
          subtitle: '留空则自动使用站点域名',
          trailing: SizedBox(
            width: 360,
            child: _textField(
              _nameController(site),
              hint: _siteLabel(site),
            ),
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          title: '站点地址',
          subtitle: '例如 https://ai.example.com；可带 /v1 或 /api',
          trailing: SizedBox(
            width: 360,
            child: _textField(
              _baseUrlController(site),
              hint: 'https://ai.example.com',
            ),
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          title: '额度换算',
          subtitle: '比例留空自动读取 /api/status；自动失败时使用手填比例和符号',
          trailing: SizedBox(
            width: 360,
            child: Row(
              children: [
                Expanded(
                  child: _textField(
                    _rateController(site),
                    hint: '自动，例如 500000',
                  ),
                ),
                const SizedBox(width: 8),
                _QuotaDropdown<String>(
                  value: _currencyPreset(site),
                  width: 130,
                  entries: const [
                    DropdownMenuEntry(value: '', label: '自动'),
                    DropdownMenuEntry(value: '¥', label: '人民币 ¥'),
                    DropdownMenuEntry(value: r'$', label: r'美元 $'),
                  ],
                  onChanged: (value) {
                    if (value != null) _saveSiteCurrency(site, value);
                  },
                ),
              ],
            ),
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          title: '凭据类型',
          subtitle: accountMode
              ? '系统访问令牌查询账户余额，需要数字用户 ID'
              : 'API 密钥只查询该令牌自己的额度',
          trailing: _QuotaDropdown<String>(
            value: site.mode,
            width: 210,
            entries: const [
              DropdownMenuEntry(value: 'account', label: '系统访问令牌'),
              DropdownMenuEntry(value: 'token', label: 'API 密钥'),
            ],
            onChanged: (value) {
              if (value == null) return;
              _saveSiteMode(site, value);
            },
          ),
        ),
        const SettingsDivider(),
        if (accountMode) ...[
          _CredentialField(
            title: '系统访问令牌',
            hint: '个人设置 → 安全与访问 → 访问令牌',
            configured: _newApiTokensConfigured[site.id] == true,
            controller: _newApiAccessToken,
            busy: _busy,
            onSave: () => _saveSecret(
              'newapi',
              'accessToken',
              _newApiAccessToken,
              (value) => _newApiTokensConfigured[site.id] = value,
              (value) => widget.onSave(
                widget.settings.copyWith(
                  quotaNewApiAccessTokenConfigured: {
                    ...widget.settings.quotaNewApiAccessTokenConfigured,
                    site.id: value,
                  },
                ),
              ),
              siteId: site.id,
            ),
            onClear: () => _clearSecret(
              'newapi',
              'accessToken',
              _newApiAccessToken,
              (value) => _newApiTokensConfigured[site.id] = value,
              (value) => widget.onSave(
                widget.settings.copyWith(
                  quotaNewApiAccessTokenConfigured: {
                    ...widget.settings.quotaNewApiAccessTokenConfigured,
                    site.id: value,
                  },
                ),
              ),
              siteId: site.id,
            ),
          ),
          const SettingsDivider(),
          SettingsRow(
            title: '用户 ID',
            subtitle: '与访问令牌属于同一账号的数字 ID',
            trailing: SizedBox(
              width: 360,
              child: _textField(_userIdController(site), hint: '例如 1'),
            ),
          ),
        ] else
          _CredentialField(
            title: 'API 密钥',
            hint: '粘贴 sk- 开头的令牌',
            configured: _newApiKeysConfigured[site.id] == true,
            controller: _newApiKey,
            busy: _busy,
            onSave: () => _saveSecret(
              'newapi',
              'apiKey',
              _newApiKey,
              (value) => _newApiKeysConfigured[site.id] = value,
              (value) => widget.onSave(
                widget.settings.copyWith(
                  quotaNewApiKeyConfigured: {
                    ...widget.settings.quotaNewApiKeyConfigured,
                    site.id: value,
                  },
                ),
              ),
              siteId: site.id,
            ),
            onClear: () => _clearSecret(
              'newapi',
              'apiKey',
              _newApiKey,
              (value) => _newApiKeysConfigured[site.id] = value,
              (value) => widget.onSave(
                widget.settings.copyWith(
                  quotaNewApiKeyConfigured: {
                    ...widget.settings.quotaNewApiKeyConfigured,
                    site.id: value,
                  },
                ),
              ),
              siteId: site.id,
            ),
          ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => _removeNewApiSite(site),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('删除该站点'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => unawaited(
                  _openUrl('https://docs.newapi.pro/'),
                ),
                child: const Text('接口文档'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : () => _saveSiteMeta(site),
                child: const Text('保存站点信息'),
              ),
            ],
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: _colors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '系统访问令牌不是 sk- 开头的 API 密钥。'
                  '账户模式使用 /api/user/self，令牌模式使用 /api/usage/token；'
                  '后者需要较新的 New API 版本。',
                  style: TextStyle(
                    color: _colors.muted,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _textField(TextEditingController controller, {String? hint}) {
    return TextField(
      controller: controller,
      style: TextStyle(color: _colors.text, fontSize: 12),
      decoration: InputDecoration(hintText: hint),
    );
  }
}

/// 服务列表里的凭据状态：已配置 / 未配置。
class _QuotaStatusBadge extends StatelessWidget {
  const _QuotaStatusBadge({required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final color = configured ? colors.accent : colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        configured ? '已配置' : '未配置',
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}

class _CredentialField extends StatefulWidget {
  const _CredentialField({
    required this.title,
    required this.hint,
    required this.configured,
    required this.controller,
    required this.busy,
    required this.onSave,
    this.onClear,
  });

  final String title;
  final String hint;
  final bool configured;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback? onClear;

  @override
  State<_CredentialField> createState() => _CredentialFieldState();
}

class _CredentialFieldState extends State<_CredentialField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(color: colors.text, fontSize: 13),
                ),
              ),
              if (widget.configured)
                Text(
                  '已配置',
                  style: TextStyle(color: colors.accent, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  obscureText: _obscure,
                  style: TextStyle(color: colors.text, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(color: colors.muted, fontSize: 12),
                    isDense: true,
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                        color: colors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (widget.configured && widget.onClear != null)
                TextButton(
                  onPressed: widget.busy ? null : widget.onClear,
                  child: const Text('清除'),
                ),
              FilledButton(
                onPressed: widget.busy ? null : widget.onSave,
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuotaDropdown<T> extends StatelessWidget {
  const _QuotaDropdown({
    required this.value,
    required this.entries,
    required this.onChanged,
    required this.width,
  });

  final T value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return DropdownMenu<T>(
      // initialSelection 只在初始化时读取，外部值变化时用 key 重建。
      key: ValueKey(value),
      initialSelection: value,
      width: width,
      menuHeight: 320,
      enableFilter: false,
      enableSearch: false,
      textStyle: TextStyle(color: colors.text, fontSize: 12),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.cardBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: colors.sidebarBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.cardStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.cardStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
      dropdownMenuEntries: entries,
      onSelected: onChanged,
    );
  }
}
