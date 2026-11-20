import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../mail/mail_bridge.dart';
import '../mail/mail_models.dart';
import '../mail/mail_provider_badge.dart';
import '../translate/translate_languages.dart';
import 'settings_panel.dart';

class _ProviderOption {
  const _ProviderOption({
    required this.id,
    required this.label,
    required this.steps,
    this.linkLabel,
    this.linkUrl,
  });

  final String id;
  final String label;
  final String steps;
  final String? linkLabel;
  final String? linkUrl;

  /// 密码框标题：QQ/163 叫授权码，Gmail/iCloud 叫应用专用密码。
  String get secretLabel => switch (id) {
    'qq' || '163' || '126' => '授权码',
    'gmail' || 'icloud' => '应用专用密码',
    'exmail' => '密码 / 客户端专用密码',
    _ => '密码',
  };

  String get secretPlaceholder => switch (id) {
    'qq' || '163' || '126' => '粘贴邮箱生成的授权码',
    'gmail' || 'icloud' => '粘贴应用专用密码',
    'exmail' => '输入登录密码或客户端专用密码',
    _ => '输入邮箱密码',
  };

  String get secretHint => switch (id) {
    'qq' || '163' || '126' => '在邮箱网页版生成，不是登录密码',
    'gmail' => '开启两步验证后生成的 16 位密码',
    'icloud' => '在 Apple 账户生成的 App 专用密码',
    'exmail' => '学校或企业邮箱的登录密码，或管理员提供的专用密码',
    _ => '邮箱登录密码或客户端专用密码',
  };
}

const List<_ProviderOption> _providers = [
  _ProviderOption(
    id: 'qq',
    label: 'QQ 邮箱',
    steps: '1. 打开 QQ 邮箱网页版\n'
        '2. 设置 → 账号与安全 → 安全设置\n'
        '3. 开启 POP3/IMAP/SMTP 服务\n'
        '4. 生成授权码并粘贴到下方',
    linkLabel: '打开 QQ 邮箱',
    linkUrl: 'https://mail.qq.com/',
  ),
  _ProviderOption(
    id: '163',
    label: '163 邮箱',
    steps: '1. 打开网易邮箱网页版\n'
        '2. 设置 → POP3/SMTP/IMAP\n'
        '3. 开启 IMAP 服务\n'
        '4. 新增客户端授权密码并粘贴到下方',
    linkLabel: '打开 163 邮箱',
    linkUrl: 'https://mail.163.com/',
  ),
  _ProviderOption(
    id: '126',
    label: '126 邮箱',
    steps: '1. 打开网易邮箱网页版\n'
        '2. 设置 → POP3/SMTP/IMAP\n'
        '3. 开启 IMAP 服务\n'
        '4. 新增客户端授权密码并粘贴到下方',
    linkLabel: '打开 126 邮箱',
    linkUrl: 'https://mail.126.com/',
  ),
  _ProviderOption(
    id: 'exmail',
    label: '腾讯企业邮 / 学校邮箱',
    steps: '1. 打开腾讯企业邮网页版，确认 IMAP 已开启\n'
        '2. 咨询管理员是否需要客户端专用密码\n'
        '3. 有的学校邮箱可以直接使用登录密码\n'
        '4. 填写完整邮箱地址和密码',
    linkLabel: '打开腾讯企业邮',
    linkUrl: 'https://exmail.qq.com/',
  ),
  _ProviderOption(
    id: 'icloud',
    label: 'iCloud 邮箱',
    steps: '1. 用 Apple ID 登录 Apple 账户\n'
        '2. 登录与安全 → App 专用密码\n'
        '3. 按提示生成密码\n'
        '4. 账号必须是 @icloud.com、@me.com 或 @mac.com',
    linkLabel: '打开 Apple 账户',
    linkUrl: 'https://account.apple.com/account/manage',
  ),
  _ProviderOption(
    id: 'gmail',
    label: 'Gmail',
    steps: '1. 在浏览器打开下面的地址\n'
        '2. 登录 Google 账号；没有“应用专用密码”时先开启两步验证\n'
        '3. 生成 16 位应用专用密码\n'
        '4. 粘贴到下方；不能使用 Google 登录密码',
    linkLabel: '打开应用专用密码页',
    linkUrl: 'https://myaccount.google.com/apppasswords',
  ),
  _ProviderOption(
    id: 'custom',
    label: '自定义 IMAP',
    steps: '1. 向管理员确认 IMAP 主机和端口\n'
        '2. 确认服务器支持连接即加密的 TLS（通常 993）\n'
        '3. 填写邮箱、服务器和密码\n'
        '4. 不支持明文和 STARTTLS',
  ),
];

/// 邮箱账号管理：添加、删除账号与轮询间隔。
class MailSettingsPage extends StatefulWidget {
  const MailSettingsPage({
    super.key,
    required this.settings,
    required this.onSave,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;

  @override
  State<MailSettingsPage> createState() => _MailSettingsPageState();
}

class _MailSettingsPageState extends State<MailSettingsPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _label = TextEditingController();
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '993');
  final TextEditingController _username = TextEditingController();

  String _provider = 'qq';
  List<MailAccount> _accounts = const [];
  bool _loading = true;
  bool _loadingAccounts = false;
  bool _adding = false;
  bool _showPassword = false;
  String _error = '';
  String _status = '';
  bool _statusError = false;
  String? _lastAddedId;
  Timer? _timer;

  IslandColors get _colors => context.islandColors;

  _ProviderOption get _selected {
    return _providers.firstWhere(
      (option) => option.id == _provider,
      orElse: () => _providers.first,
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_load(silent: true)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [
      _email,
      _password,
      _label,
      _host,
      _port,
      _username,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadingAccounts) return;
    _loadingAccounts = true;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final result = await mailChannel.invokeMethod<dynamic>('accounts.list');
      final raw = _asMap(result);
      final list = raw?['accounts'];
      final accounts = <MailAccount>[];
      if (list is List) {
        for (final value in list) {
          final map = _asMap(value);
          if (map == null) continue;
          final account = MailAccount.fromJson(map);
          if (account.id.isNotEmpty) accounts.add(account);
        }
      }
      if (!mounted) return;
      setState(() {
        _accounts = List.unmodifiable(accounts);
        _error = '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
      if (!silent) AppLog.write('[mail-settings] load failed: $error');
    } finally {
      _loadingAccounts = false;
    }
  }

  Future<void> _add() async {
    if (_adding) return;
    final email = _email.text.trim();
    final password = _password.text.trim();
    if (!email.contains('@')) {
      _setStatus('请填写完整的邮箱地址', error: true);
      return;
    }
    if (_provider == 'icloud' && !_isAppleMail(email)) {
      _setStatus(
        'iCloud 只支持 @icloud.com、@me.com 或 @mac.com 邮箱；'
        'Gmail 地址请选择 Gmail。',
        error: true,
      );
      return;
    }
    if (password.isEmpty) {
      _setStatus('请填写授权码或应用专用密码', error: true);
      return;
    }
    final custom = <String, dynamic>{};
    if (_provider == 'custom') {
      final host = _host.text.trim();
      final port = int.tryParse(_port.text.trim());
      if (host.isEmpty || port == null) {
        _setStatus('请填写 IMAP 服务器和端口', error: true);
        return;
      }
      custom['host'] = host;
      custom['port'] = port;
      custom['username'] = _username.text.trim();
    }
    setState(() {
      _adding = true;
      _status = '正在添加 $email…';
      _statusError = false;
    });
    try {
      final result = await mailChannel
          .invokeMethod<dynamic>('accounts.add', {
            'provider': _provider,
            'email': email,
            'password': password,
            if (_label.text.trim().isNotEmpty) 'label': _label.text.trim(),
            if (_provider == 'custom') 'custom': custom,
          })
          .timeout(const Duration(seconds: 20));
      final raw = _asMap(result);
      final accountRaw = _asMap(raw?['account']);
      MailAccount? added;
      if (accountRaw != null) {
        added = MailAccount.fromJson(accountRaw);
        if (added.id.isNotEmpty) _upsertAccount(added);
      }
      _lastAddedId = added?.id;
      _password.clear();
      setState(() {
        _showPassword = false;
        _status = added == null
            ? '已添加 $email，正在读取账号状态…'
            : '已添加 $email，正在连接…';
        _statusError = false;
      });
      await _load(silent: true);
    } catch (error) {
      _setStatus('添加失败：${_message(error)}', error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// 切换邮箱类型时清空上一个服务商的输入内容和状态提示。
  void _selectProvider(String? value) {
    if (value == null || value == _provider) return;
    setState(() {
      _provider = value;
      _email.clear();
      _password.clear();
      _label.clear();
      _host.clear();
      _port.text = '993';
      _username.clear();
      _showPassword = false;
      _status = '';
      _statusError = false;
      _lastAddedId = null;
    });
  }

  bool _isAppleMail(String email) {
    final lower = email.toLowerCase();
    return lower.endsWith('@icloud.com') ||
        lower.endsWith('@me.com') ||
        lower.endsWith('@mac.com');
  }

  void _setStatus(String message, {required bool error}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusError = error;
    });
    if (error) _showError(message);
  }

  /// 平台通道返回的嵌套 Map 通常是 `Map<Object?, Object?>`，不能直接当成
  /// `Map<String, dynamic>`；统一转成字符串键。
  Map<String, dynamic>? _asMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  MailAccount? _findAccount(String? id) {
    if (id == null) return null;
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  void _upsertAccount(MailAccount account) {
    final next = _accounts.toList();
    final index = next.indexWhere((item) => item.id == account.id);
    if (index >= 0) {
      next[index] = account;
    } else {
      next.add(account);
    }
    _accounts = List.unmodifiable(next);
  }

  Future<void> _editLabel(MailAccount account) async {
    final controller = TextEditingController(text: account.label ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑邮箱别名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：工作邮箱；留空则显示邮箱地址',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      await mailChannel.invokeMethod<dynamic>('accounts.update', {
        'id': account.id,
        'label': result.trim(),
      });
      await _load(silent: true);
    } catch (error) {
      _showError('保存别名失败：${_message(error)}');
    }
  }

  Future<void> _remove(MailAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除邮箱'),
        content: Text('删除 ${account.email}？已保存的授权码也会从凭据管理器移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await mailChannel.invokeMethod<dynamic>('accounts.remove', {
        'id': account.id,
      });
      await _load(silent: true);
    } catch (error) {
      _showError('删除失败：${_message(error)}');
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await mailChannel.invokeMethod<dynamic>('openUrl', {'url': url});
    } catch (error) {
      _showError('打开链接失败：${_message(error)}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _message(Object error) {
    if (error is PlatformException) {
      return error.message?.trim().isNotEmpty == true
          ? error.message!
          : error.code;
    }
    return '$error';
  }

  @override
  Widget build(BuildContext context) {
    final option = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('已连接邮箱'),
        _accountsCard(),
        const SizedBox(height: 18),
        const SettingsSectionLabel('添加邮箱'),
        _addCard(option),
        const SizedBox(height: 18),
        const SettingsSectionLabel('同步'),
        _syncCard(),
        const SizedBox(height: 18),
        const SettingsSectionLabel('邮件翻译'),
        _translateCard(),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Outlook / Microsoft 365 需要 OAuth 授权，当前版本暂未开放。',
            style: TextStyle(color: _colors.muted, fontSize: 11, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _accountsCard() {
    if (_loading && _accounts.isEmpty) {
      return const SettingsCard(
        children: [
          SettingsRow(title: '正在读取账号', subtitle: '请稍候'),
        ],
      );
    }
    return SettingsCard(
      children: [
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: _colors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error,
                    style: TextStyle(color: _colors.warning, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(_load()),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        if (_accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              '还没有添加邮箱。添加后，岛体「邮箱」页会显示最近 20 封邮件。',
              style: TextStyle(color: _colors.muted, fontSize: 12, height: 1.5),
            ),
          ),
        for (var index = 0; index < _accounts.length; index++) ...[
          if (index > 0) const SettingsDivider(),
          _accountRow(_accounts[index]),
        ],
      ],
    );
  }

  Color _providerColor(String provider) => switch (provider) {
    'qq' => const Color(0xFF12B7F5),
    '163' => const Color(0xFFD9342B),
    '126' => const Color(0xFFE64A19),
    'gmail' => const Color(0xFFEA4335),
    'icloud' => const Color(0xFF3693F3),
    'exmail' => const Color(0xFF2B7DE9),
    _ => _colors.muted,
  };

  Widget _accountRow(MailAccount account) {
    final color = account.ready
        ? _colors.accent
        : (account.needsAttention ? _colors.warning : _colors.muted);
    final detail = [
      account.providerLabel,
      if (account.label != null) account.label!,
      account.stateLabel,
      if (account.message.isNotEmpty) account.message,
    ].join(' · ');
    return SettingsRow(
      leading: MailProviderBadge(
        provider: account.provider,
        email: account.email,
        color: _providerColor(account.provider),
      ),
      title: account.email,
      subtitle: detail,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              account.stateLabel,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '编辑别名',
            onPressed: () => unawaited(_editLabel(account)),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除账号',
            onPressed: () => unawaited(_remove(account)),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _addCard(_ProviderOption option) {
    return SettingsCard(
      children: [
        SettingsRow(
          title: '邮箱类型',
          subtitle: '服务器和端口由预设决定',
          trailing: _ProviderDropdown(
            value: _provider,
            onChanged: _selectProvider,
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _guideCard(option),
        ),
        const SettingsDivider(),
        _fieldRow(
          title: '邮箱地址',
          subtitle: '完整地址，例如 name@qq.com',
          controller: _email,
          hint: 'name@example.com',
          paste: true,
        ),
        const SettingsDivider(),
        _secretRow(
          title: option.secretLabel,
          subtitle: option.secretHint,
          hint: option.secretPlaceholder,
        ),
        if (_provider == 'custom') ...[
          const SettingsDivider(),
          _fieldRow(
            title: 'IMAP 服务器',
            subtitle: '例如 imap.example.com',
            controller: _host,
            hint: 'imap.example.com',
          ),
          const SettingsDivider(),
          _fieldRow(
            title: '端口',
            subtitle: '仅支持 TLS，通常是 993',
            controller: _port,
            hint: '993',
          ),
          const SettingsDivider(),
          _fieldRow(
            title: '用户名',
            subtitle: '留空时使用邮箱地址',
            controller: _username,
            hint: '通常与邮箱地址相同',
          ),
        ],
        const SettingsDivider(),
        _fieldRow(
          title: '备注',
          subtitle: '可选，用于区分多个邮箱',
          controller: _label,
          hint: '例如：工作邮箱',
        ),
        const SettingsDivider(),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextButton(
              onPressed: _adding ? null : () => unawaited(_add()),
              child: Text(
                _adding ? '添加中…' : '添加账号',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        _addStatus(),
      ],
    );
  }

  Widget _guideCard(_ProviderOption option) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: _colors.sidebarBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _colors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, size: 15, color: _colors.accent),
              const SizedBox(width: 6),
              Text(
                '如何获取授权码',
                style: TextStyle(
                  color: _colors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            option.steps,
            style: TextStyle(
              color: _colors.muted,
              fontSize: 11,
              height: 1.6,
            ),
          ),
          if (option.id == 'gmail' && option.linkUrl != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              option.linkUrl!,
              style: TextStyle(
                color: _colors.accent,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
          if (option.id == 'exmail' || option.id == 'custom') ...[
            const SizedBox(height: 6),
            Text(
              '学校或企业邮箱可能使用登录密码，也可能要求客户端专用密码；'
              '以管理员设置为准。服务器地址不确定时，可以向学校网络中心确认。',
              style: TextStyle(
                color: _colors.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
          if (option.id == 'custom') ...[
            const SizedBox(height: 6),
            Text(
              '如果服务商有主账号/子账号体系（例如 2925 无限邮），'
              'IMAP 可能只能看到主账号的邮件，请先用主账号确认网页收件箱里有内容。',
              style: TextStyle(
                color: _colors.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
          if (option.id == 'gmail') ...[
            const SizedBox(height: 6),
            Text(
              '找不到“应用专用密码”时：确认两步验证已开启；'
              '工作/学校账号、仅使用安全密钥或加入高级保护计划的账号可能没有此选项。'
              '修改 Google 密码后，已有应用专用密码会被撤销，需要重新生成。',
              style: TextStyle(
                color: _colors.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '授权码只写入 Windows 凭据管理器，保存后不会回显；'
            '需要更换时，用同一邮箱重新添加即可覆盖。',
            style: TextStyle(
              color: _colors.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          if (option.linkLabel != null && option.linkUrl != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => unawaited(_openUrl(option.linkUrl!)),
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                label: Text(option.linkLabel!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _addStatus() {
    final added = _findAccount(_lastAddedId);
    final String text;
    final Color color;
    final IconData icon;
    if (_adding) {
      text = _status.isEmpty ? '正在添加…' : _status;
      color = _colors.muted;
      icon = Icons.sync_rounded;
    } else if (added != null) {
      text =
          '${added.email} · ${added.stateLabel}'
          '${added.message.isNotEmpty ? ' · ${added.message}' : ''}';
      color = added.ready
          ? _colors.accent
          : (added.needsAttention ? _colors.warning : _colors.muted);
      icon = added.needsAttention
          ? Icons.warning_amber_rounded
          : Icons.check_circle_outline_rounded;
    } else if (_lastAddedId != null) {
      text = _status.isEmpty ? '已添加，正在读取账号状态…' : _status;
      color = _colors.muted;
      icon = Icons.sync_rounded;
    } else if (_status.isNotEmpty) {
      text = _status;
      color = _statusError ? _colors.warning : _colors.muted;
      icon = _statusError
          ? Icons.warning_amber_rounded
          : Icons.info_outline_rounded;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secretRow({
    required String title,
    required String subtitle,
    required String hint,
  }) {
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: SizedBox(
        width: 320,
        child: TextField(
          controller: _password,
          obscureText: !_showPassword,
          style: TextStyle(color: _colors.text, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '从剪贴板粘贴',
                  onPressed: () => unawaited(_pasteSecret()),
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                ),
                IconButton(
                  tooltip: _showPassword ? '隐藏授权码' : '显示授权码',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pasteSecret() =>
      _pasteInto(_password, reveal: true);

  Future<void> _pasteInto(
    TextEditingController controller, {
    bool reveal = false,
  }) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        _setStatus('剪贴板里没有可粘贴的文本', error: true);
        return;
      }
      controller.text = text;
      controller.selection = TextSelection.collapsed(offset: text.length);
      if (reveal) setState(() => _showPassword = true);
      _setStatus('已从剪贴板粘贴', error: false);
    } catch (error) {
      _setStatus('读取剪贴板失败：$error', error: true);
    }
  }

  Widget _syncCard() {
    final seconds = widget.settings.mailPollSeconds;
    return SettingsCard(
      children: [
        SettingsRow(
          title: '轮询间隔',
          subtitle: '每隔多久检查一次新邮件；收起态不会主动弹窗',
          trailing: _IntervalDropdown(
            value: seconds,
            onChanged: (value) {
              if (value != null) {
                widget.onSave(
                  widget.settings.copyWith(mailPollSeconds: value),
                );
              }
            },
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '打开单封邮件会自动标为已读；收件箱顶部也可以一键标记当前筛选范围。'
            '每封邮件只在内存中保留纯文本正文，最多 20 封；不下载附件，也不加载远程图片。',
            style: TextStyle(color: _colors.muted, fontSize: 11, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _translateCard() {
    final value = widget.settings.mailTranslateProvider;
    final option = translateProviders.firstWhere(
      (item) => item.id == value,
      orElse: () => translateProviders.first,
    );
    return SettingsCard(
      children: [
        SettingsRow(
          title: '翻译服务',
          subtitle: option.detail,
          trailing: _TranslateProviderDropdown(
            value: value,
            onChanged: (id) {
              if (id != null) {
                widget.onSave(
                  widget.settings.copyWith(mailTranslateProvider: id),
                );
              }
            },
          ),
        ),
        const SettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '只列出翻译页里的服务；目标语言沿用翻译设置，'
            '也可以在邮件详情右下角临时切换。',
            style: TextStyle(color: _colors.muted, fontSize: 11, height: 1.5),
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
    bool paste = false,
  }) {
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      trailing: SizedBox(
        width: 320,
        child: TextField(
          controller: controller,
          style: TextStyle(color: _colors.text, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: paste
                ? IconButton(
                    tooltip: '从剪贴板粘贴',
                    onPressed: () => unawaited(_pasteInto(controller)),
                    icon: const Icon(Icons.content_paste_rounded, size: 16),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _ProviderDropdown extends StatelessWidget {
  const _ProviderDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return DropdownMenu<String>(
      key: ValueKey(value),
      initialSelection: value,
      width: 200,
      enableFilter: false,
      enableSearch: false,
      textStyle: TextStyle(color: colors.text, fontSize: 12),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.cardBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      dropdownMenuEntries: [
        for (final option in _providers)
          DropdownMenuEntry(value: option.id, label: option.label),
      ],
      onSelected: onChanged,
    );
  }
}

class _TranslateProviderDropdown extends StatelessWidget {
  const _TranslateProviderDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final selected = translateProviders.any((item) => item.id == value)
        ? value
        : 'auto';
    return DropdownMenu<String>(
      key: ValueKey(selected),
      initialSelection: selected,
      width: 180,
      enableFilter: false,
      enableSearch: false,
      textStyle: TextStyle(color: colors.text, fontSize: 12),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.cardBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      dropdownMenuEntries: [
        for (final provider in translateProviders)
          DropdownMenuEntry(value: provider.id, label: provider.label),
      ],
      onSelected: onChanged,
    );
  }
}

class _IntervalDropdown extends StatelessWidget {
  const _IntervalDropdown({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int?> onChanged;

  static const _options = <int, String>{
    60: '1 分钟',
    120: '2 分钟',
    180: '3 分钟',
    300: '5 分钟',
    600: '10 分钟',
    900: '15 分钟',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final selected = _options.containsKey(value) ? value : 180;
    return DropdownMenu<int>(
      key: ValueKey(selected),
      initialSelection: selected,
      width: 140,
      enableFilter: false,
      enableSearch: false,
      textStyle: TextStyle(color: colors.text, fontSize: 12),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.cardBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      dropdownMenuEntries: [
        for (final entry in _options.entries)
          DropdownMenuEntry(value: entry.key, label: entry.value),
      ],
      onSelected: onChanged,
    );
  }
}
