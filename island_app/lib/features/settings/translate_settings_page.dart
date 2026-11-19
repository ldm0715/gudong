import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_motion.dart';
import '../translate/translate_bridge.dart';
import '../translate/translate_languages.dart';
import 'settings_panel.dart';

/// 翻译设置：引擎、目标语言、各服务的 Key 与模型。
class TranslateSettingsPage extends StatefulWidget {
  const TranslateSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  State<TranslateSettingsPage> createState() => _TranslateSettingsPageState();
}

class _TranslateSettingsPageState extends State<TranslateSettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _userPrompt;
  late final TextEditingController _prompt;
  late final TextEditingController _llmKey;
  late final TextEditingController _deeplKey;
  late final TextEditingController _caiyunKey;
  late final TextEditingController _myMemoryEmail;

  late bool _llmConfigured;
  late bool _deeplConfigured;
  late bool _caiyunConfigured;
  bool _fetchingModels = false;
  bool _savingSecret = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _baseUrl = TextEditingController(text: settings.translateBaseUrl);
    _model = TextEditingController(text: settings.translateModel);
    _userPrompt = TextEditingController(text: settings.translateUserPrompt);
    _prompt = TextEditingController(text: settings.translateSystemPrompt);
    _llmKey = TextEditingController();
    _deeplKey = TextEditingController();
    _caiyunKey = TextEditingController();
    _myMemoryEmail = TextEditingController(
      text: settings.translateMyMemoryEmail,
    );
    _llmConfigured = settings.translateLlmKeyConfigured;
    _deeplConfigured = settings.translateDeeplKeyConfigured;
    _caiyunConfigured = settings.translateCaiyunKeyConfigured;
  }

  @override
  void dispose() {
    for (final controller in [
      _baseUrl,
      _model,
      _userPrompt,
      _prompt,
      _llmKey,
      _deeplKey,
      _caiyunKey,
      _myMemoryEmail,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  IslandColors get _colors => context.islandColors;

  void _apply(AppSettings next) => widget.onSave(next);

  Future<void> _saveLlm() async {
    final key = _llmKey.text.trim();
    if (key.isNotEmpty) {
      if (!await _writeSecret('llm', key)) return;
      _llmConfigured = true;
      _llmKey.clear();
      if (mounted) setState(() {});
    }
    _apply(
      widget.settings.copyWith(
        translateBaseUrl: _baseUrl.text.trim(),
        translateModel: _model.text.trim(),
      ),
    );
  }

  Future<void> _clearLlmKey() async {
    if (!await _writeSecret('llm', '')) return;
    _llmConfigured = false;
    _llmKey.clear();
    if (mounted) setState(() {});
  }

  void _saveUserPrompt() {
    _apply(
      widget.settings.copyWith(translateUserPrompt: _userPrompt.text.trim()),
    );
  }

  void _savePrompt() {
    _apply(
      widget.settings.copyWith(translateSystemPrompt: _prompt.text.trim()),
    );
  }

  void _saveMyMemory() {
    _apply(
      widget.settings.copyWith(
        translateMyMemoryEmail: _myMemoryEmail.text.trim(),
      ),
    );
  }

  Future<bool> _writeSecret(String provider, String key) async {
    setState(() => _savingSecret = true);
    try {
      await translateChannel.invokeMethod<dynamic>('setSecret', {
        'provider': provider,
        'key': key,
      });
      return true;
    } catch (error) {
      _showError('保存密钥失败：$error');
      return false;
    } finally {
      if (mounted) setState(() => _savingSecret = false);
    }
  }

  Future<void> _saveSecret(
    String provider,
    TextEditingController controller,
    void Function(bool configured) update,
  ) async {
    final key = controller.text.trim();
    if (!await _writeSecret(provider, key)) return;
    update(key.isNotEmpty);
    controller.clear();
    if (mounted) setState(() {});
  }

  Future<void> _fetchModels() async {
    setState(() => _fetchingModels = true);
    try {
      final result = await translateChannel.invokeMethod<dynamic>('models', {
        'baseUrl': _baseUrl.text.trim(),
        'apiKey': _llmKey.text.trim(),
      });
      final raw = result is Map ? result['models'] : null;
      final models = raw is List
          ? raw.map((value) => value.toString()).toList(growable: false)
          : const <String>[];
      if (models.isEmpty) {
        throw StateError('服务端没有返回模型');
      }
      if (!mounted) return;
      final selected = await _pickModel(models);
      if (selected != null) {
        _model.text = selected;
        await _saveLlm();
      }
    } catch (error) {
      _showError('获取模型失败：$error');
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Future<String?> _pickModel(List<String> models) {
    final colors = _colors;
    return showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(
            '选择模型',
            style: TextStyle(
              color: colors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            SizedBox(
              width: 420,
              height: 420,
              child: ListView.builder(
                itemCount: models.length,
                itemBuilder: (context, index) {
                  final model = models[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(model),
                    onTap: () => Navigator.of(context).pop(model),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      await translateChannel.invokeMethod<dynamic>('openUrl', {'url': url});
    } catch (error) {
      _showError('打开链接失败：$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _llmReady => _llmConfigured && _model.text.trim().isNotEmpty;

  ({String label, bool ok}) _engineStatus(String id) {
    return switch (id) {
      'llm' => _llmReady ? (label: '已配置', ok: true) : (label: '未配置', ok: false),
      'deepl' =>
        _deeplConfigured ? (label: '已配置', ok: true) : (label: '未配置', ok: false),
      'caiyun' =>
        _caiyunConfigured ? (label: '已配置', ok: true) : (label: '免密钥', ok: true),
      'microsoftFree' => (label: '免密钥', ok: true),
      'mymemory' => (label: '免密钥', ok: true),
      _ => (label: '自动', ok: true),
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final provider = translateProviders.firstWhere(
      (item) => item.id == settings.translateProvider,
      orElse: () => translateProviders.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('翻译引擎'),
        SettingsCard(
          children: [
            SettingsRow(
              title: '引擎',
              subtitle: provider.detail,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dropdown<String>(
                    value: provider.id,
                    width: 200,
                    entries: [
                      for (final item in translateProviders)
                        DropdownMenuEntry(value: item.id, label: item.label),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _apply(settings.copyWith(translateProvider: value));
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  _statusBadge(_engineStatus(provider.id)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SettingsSectionLabel('语言'),
        _languageCard(settings),
        const SizedBox(height: 18),
        ..._engineSections(settings),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Key 保存在 Windows 凭据管理器，不写入 config.json。',
            style: TextStyle(color: _colors.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(({String label, bool ok}) status) {
    final colors = _colors;
    final color = status.ok ? colors.accent : colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _languageCard(AppSettings settings) {
    final source =
        translateSourceLanguages.any(
          (item) => item.code == settings.translateSource,
        )
        ? settings.translateSource
        : 'auto';
    final target =
        translateLanguages.any((item) => item.code == settings.translateTarget)
        ? settings.translateTarget
        : translateLanguages.first.code;
    return SettingsCard(
      children: [
        SettingsRow(
          title: '目标语言',
          subtitle: '岛体翻译页默认使用这个语言',
          trailing: _Dropdown<String>(
            value: target,
            width: 220,
            entries: [
              for (final item in translateLanguages)
                DropdownMenuEntry(value: item.code, label: item.label),
            ],
            onChanged: (value) {
              if (value != null) {
                _apply(settings.copyWith(translateTarget: value));
              }
            },
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          title: '源语言',
          subtitle: '自动识别不可用时由 sidecar 推断',
          trailing: _Dropdown<String>(
            value: source,
            width: 220,
            entries: [
              for (final item in translateSourceLanguages)
                DropdownMenuEntry(value: item.code, label: item.label),
            ],
            onChanged: (value) {
              if (value != null) {
                _apply(settings.copyWith(translateSource: value));
              }
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _engineSections(AppSettings settings) {
    return switch (settings.translateProvider) {
      'llm' => [
        const SettingsSectionLabel('大模型配置'),
        _llmCard(),
        const SizedBox(height: 18),
        const SettingsSectionLabel('额外要求'),
        _userPromptCard(),
        const SizedBox(height: 18),
        const SettingsSectionLabel('系统提示词'),
        _promptCard(),
      ],
      'deepl' => [const SettingsSectionLabel('DeepL 配置'), _deeplCard()],
      'caiyun' => [const SettingsSectionLabel('彩云小译配置'), _caiyunCard()],
      'microsoftFree' => [
        const SettingsSectionLabel('微软免密钥'),
        _microsoftFreeCard(),
      ],
      'mymemory' => [
        const SettingsSectionLabel('MyMemory 配置'),
        _myMemoryCard(),
      ],
      _ => [const SettingsSectionLabel('自动选择'), _autoCard(settings)],
    };
  }

  Widget _autoCard(AppSettings settings) {
    final order = settings.translateAutoOrder;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '拖动右侧手柄调整优先级，自动模式从上到下选择第一个可用引擎。'
            '微软免密钥是 Edge 内部接口，失败时会自动回退 MyMemory。',
            style: TextStyle(color: _colors.muted, fontSize: 11, height: 1.5),
          ),
        ),
        const SettingsDivider(),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: order.length,
          onReorder: (oldIndex, newIndex) =>
              _reorderAuto(settings, oldIndex, newIndex),
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
            final option = translateProviders.firstWhere(
              (item) => item.id == id,
              orElse: () => translateProviders.first,
            );
            return Container(
              key: ValueKey(id),
              child: SettingsRow(
                leading: Tooltip(
                  message: '拖动排序',
                  waitDuration: IslandMotion.tooltipDelay,
                  child: ReorderableDragStartListener(
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
                ),
                title: option.label,
                subtitle: option.detail,
                trailing: _statusBadge(_engineStatus(id)),
              ),
            );
          },
        ),
      ],
    );
  }

  void _reorderAuto(AppSettings settings, int oldIndex, int newIndex) {
    final order = settings.translateAutoOrder.toList();
    if (oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= order.length) return;
    final id = order.removeAt(oldIndex);
    order.insert(newIndex, id);
    _apply(settings.copyWith(translateAutoOrder: order));
  }

  Widget _llmCard() {
    return SettingsCard(
      children: [
        _fieldRow(
          title: 'Base URL',
          subtitle: '例如 https://api.openai.com/v1',
          controller: _baseUrl,
          hint: 'https://api.openai.com/v1',
        ),
        const SettingsDivider(),
        SettingsRow(
          title: 'API Key',
          subtitle: _llmConfigured ? '已保存到 Windows 凭据管理器' : '未配置',
          trailing: SizedBox(
            width: 360,
            child: Row(
              children: [
                Expanded(
                  child: _textField(
                    _llmKey,
                    hint: _llmConfigured ? '输入新 Key 会覆盖' : '粘贴 Key',
                    obscure: true,
                  ),
                ),
                if (_llmConfigured) ...[
                  const SizedBox(width: 8),
                  _button(label: '清除', onTap: () => unawaited(_clearLlmKey())),
                ],
              ],
            ),
          ),
        ),
        const SettingsDivider(),
        SettingsRow(
          title: '模型',
          subtitle: '可手动填写，或从服务端获取后选择',
          trailing: SizedBox(
            width: 360,
            child: Row(
              children: [
                Expanded(child: _textField(_model, hint: '例如 deepseek-chat')),
                const SizedBox(width: 8),
                _button(
                  label: _fetchingModels ? '获取中…' : '获取模型',
                  busy: _fetchingModels,
                  onTap: _fetchModels,
                ),
              ],
            ),
          ),
        ),
        const SettingsDivider(),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _button(label: '保存', onTap: () => unawaited(_saveLlm())),
          ),
        ),
      ],
    );
  }

  Widget _userPromptCard() {
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: TextField(
            controller: _userPrompt,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: _colors.text, fontSize: 12),
            decoration: const InputDecoration(
              hintText: '例如：保留代码不翻译、术语按……；留空使用默认翻译指令',
            ),
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '直接写自然语言要求即可；懂模板时仍可用 {{to}} 和 {{text}}。',
                  style: TextStyle(color: _colors.muted, fontSize: 11),
                ),
              ),
              _button(label: '保存用户提示词', onTap: _saveUserPrompt),
            ],
          ),
        ),
      ],
    );
  }

  Widget _promptCard() {
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: TextField(
            controller: _prompt,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(color: _colors.text, fontSize: 12),
            decoration: const InputDecoration(
              hintText: '留空使用内置模板，{{to}} 会替换为目标语言名',
            ),
          ),
        ),
        const SettingsDivider(),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _button(label: '保存提示词', onTap: _savePrompt),
          ),
        ),
      ],
    );
  }

  Widget _deeplCard() {
    return SettingsCard(
      children: [
        _keyRow(
          title: 'DeepL API Key',
          subtitle: _deeplConfigured
              ? '已保存；免费版 Key 以 :fx 结尾时自动使用 api-free'
              : '未配置；免费版 Key 以 :fx 结尾',
          controller: _deeplKey,
          hint: _deeplConfigured ? '输入新 Key 可覆盖' : '粘贴 Key',
          provider: 'deepl',
          onConfigured: (value) => _deeplConfigured = value,
        ),
        const SettingsDivider(),
        _linkRow(
          label: '打开 DeepL 密钥页（需海外账号）',
          url: 'https://www.deepl.com/your-account/keys',
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
                color: _colors.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'DeepL 不向中国大陆开放 API 订阅，也没有中国区端点。'
                  '没有海外账号或支付方式时无法获取 Key；国内建议使用大模型'
                  '（如 DeepSeek、硅基流动）或 MyMemory。',
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

  Widget _caiyunCard() {
    return SettingsCard(
      children: [
        _keyRow(
          title: '彩云小译 Token',
          subtitle: _caiyunConfigured ? '已保存个人 Token' : '未配置，使用官方公开测试 Token',
          controller: _caiyunKey,
          hint: _caiyunConfigured ? '输入新 Token 可覆盖' : '可选，粘贴自己的 Token',
          provider: 'caiyun',
          onConfigured: (value) => _caiyunConfigured = value,
        ),
        const SettingsDivider(),
        _linkRow(label: '申请彩云小译 Token', url: 'https://platform.caiyunapp.com/'),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: _colors.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '不填 Token 时使用官方公开测试 Token，可能被限流或随时失效；'
                  '长期使用建议在开放平台申请自己的 Token。'
                  '彩云目前支持译为中文、繁体中文，以及中文译为英/日/韩。',
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

  Widget _microsoftFreeCard() {
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.science_outlined, size: 16, color: _colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '使用 Edge 的内部翻译接口，无需账号和 Key，支持自动识别源语言。'
                  '该接口没有官方文档和 SLA，可能随时失效；失效时自动模式会回退到 MyMemory。',
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

  Widget _myMemoryCard() {
    return SettingsCard(
      children: [
        _fieldRow(
          title: '联系邮箱',
          subtitle: '可选；填写后额度从 5000 字符/天提高到 50000',
          controller: _myMemoryEmail,
          hint: 'you@example.com',
        ),
        const SettingsDivider(),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _button(label: '保存邮箱', onTap: _saveMyMemory),
          ),
        ),
        const SettingsDivider(),
        _linkRow(
          label: '查看 MyMemory 额度说明',
          url: 'https://mymemory.translated.net/doc/usagelimits.php',
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: _colors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'MyMemory 是免费公共服务。匿名请求按 IP 限制在约 5000 字符/天；'
                  '填写邮箱后会作为 de 参数随翻译请求发送给 MyMemory，'
                  '额度提高到约 50000 字符/天。邮箱只用于联系和识别用量，'
                  '不是账号也不是密钥；不想提供可以留空。',
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

  Widget _fieldRow({
    required String title,
    String? subtitle,
    required TextEditingController controller,
    String? hint,
  }) {
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: SizedBox(width: 360, child: _textField(controller, hint: hint)),
    );
  }

  Widget _keyRow({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    required String provider,
    required void Function(bool) onConfigured,
  }) {
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: SizedBox(
        width: 360,
        child: Row(
          children: [
            Expanded(child: _textField(controller, hint: hint, obscure: true)),
            const SizedBox(width: 8),
            _button(
              label: _savingSecret ? '保存中…' : '保存密钥',
              busy: _savingSecret,
              onTap: () =>
                  unawaited(_saveSecret(provider, controller, onConfigured)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: _colors.text, fontSize: 12),
      decoration: InputDecoration(hintText: hint),
    );
  }

  Widget _linkRow({required String label, required String url}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextButton.icon(
          onPressed: () => unawaited(_openUrl(url)),
          icon: const Icon(Icons.open_in_new_rounded, size: 14),
          label: Text(label),
        ),
      ),
    );
  }

  Widget _button({
    required String label,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return TextButton(
      onPressed: busy ? null : onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
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
