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

const List<_QuotaProviderMeta> _providers = [
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
];

/// AI - 额度设置：显示开关、服务顺序 / 显隐、凭据与刷新。
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

  late bool _glmConfigured = widget.settings.quotaGlmKeyConfigured;
  late bool _deepseekConfigured =
      widget.settings.quotaDeepseekKeyConfigured;
  late bool _opencodeKeyConfigured =
      widget.settings.quotaOpencodeKeyConfigured;
  late bool _opencodeCookieConfigured =
      widget.settings.quotaOpencodeCookieConfigured;
  String _status = '';
  bool _busy = false;

  IslandColors get _colors => context.islandColors;

  @override
  void dispose() {
    for (final controller in [
      _glmKey,
      _deepseekKey,
      _opencodeKey,
      _opencodeCookie,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveSecret(
    String provider,
    String field,
    TextEditingController controller,
    void Function(bool configured) apply,
    void Function(bool configured) markSettings,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await quotaChannel.invokeMethod<dynamic>('setSecret', {
        'provider': provider,
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
    void Function(bool configured) markSettings,
  ) {
    controller.clear();
    unawaited(
      _saveSecret(provider, field, controller, apply, markSettings),
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

  ButtonStyle get _entryStyle => ButtonStyle(
    textStyle: WidgetStatePropertyAll(
      TextStyle(color: _colors.text, fontSize: 12),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  /// 服务是否至少有一个可用凭据。OpenCode 的 API Key 与 Cookie 任一存在即可。
  bool _configured(String id) => switch (id) {
    'glm' => _glmConfigured,
    'deepseek' => _deepseekConfigured,
    'opencode' => _opencodeKeyConfigured || _opencodeCookieConfigured,
    _ => false,
  };

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

  @override
  Widget build(BuildContext context) {
    final order = widget.settings.orderedQuotaProviders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('服务'),
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
                final meta = _providers.firstWhere((item) => item.id == id);
                final visible = !widget.settings.hiddenQuotaProviders
                    .contains(id);
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
                            fallback: meta.label.substring(0, 1),
                            color: _colors.text,
                            size: 20,
                          ),
                        ],
                      ),
                      title: meta.label,
                      subtitle: meta.description,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _QuotaStatusBadge(configured: _configured(id)),
                          const SizedBox(width: 10),
                          Switch(
                            value: visible,
                            onChanged: (value) => _setVisible(id, value),
                          ),
                        ],
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
            '拖动右侧手柄调整顺序，关闭开关后该服务不会出现在额度面板和收起态。',
            style: TextStyle(color: _colors.muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('GLM'),
        SettingsCard(
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
              trailing: DropdownMenu<String>(
                initialSelection: widget.settings.quotaGlmRegion,
                width: 150,
                requestFocusOnTap: false,
                textStyle: TextStyle(color: _colors.text, fontSize: 12),
                inputDecorationTheme: InputDecorationTheme(
                  isDense: true,
                  filled: true,
                  fillColor: _colors.sidebarBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _colors.cardStroke),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _colors.cardStroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _colors.accent),
                  ),
                ),
                menuStyle: MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    _colors.cardBackground,
                  ),
                  surfaceTintColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                    value: 'global',
                    label: 'Z.ai 国际站',
                    style: _entryStyle,
                  ),
                  DropdownMenuEntry(
                    value: 'bigmodel-cn',
                    label: '智谱开放平台',
                    style: _entryStyle,
                  ),
                ],
                onSelected: (value) {
                  if (value == null) return;
                  widget.onSave(
                    widget.settings.copyWith(quotaGlmRegion: value),
                  );
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
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('DeepSeek'),
        SettingsCard(
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
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('OpenCode'),
        SettingsCard(
          children: [
            SettingsRow(
              title: '登录 / 获取凭据',
              subtitle: '登录后可在浏览器开发者工具里复制 Cookie',
              trailing: TextButton(
                onPressed: () => unawaited(
                  _openUrl('https://opencode.ai/auth'),
                ),
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
                  widget.settings.copyWith(
                    quotaOpencodeCookieConfigured: value,
                  ),
                ),
              ),
              onClear: () => _clearSecret(
                'opencode',
                'cookie',
                _opencodeCookie,
                (value) => _opencodeCookieConfigured = value,
                (value) => widget.onSave(
                  widget.settings.copyWith(
                    quotaOpencodeCookieConfigured: value,
                  ),
                ),
              ),
            ),
          ],
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
