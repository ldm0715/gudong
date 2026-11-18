import 'dart:convert';

import '../../core/settings/app_settings.dart';

/// 设置窗口的启动参数：`{"type":"settings","settings":{...}}`。
/// 主窗口用 arguments 区分多窗口，也用来把当前设置传过去。
class SettingsWindowArguments {
  const SettingsWindowArguments({required this.settings});

  final AppSettings settings;

  String encode() =>
      jsonEncode({'type': 'settings', 'settings': settings.toJson()});

  static SettingsWindowArguments? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['type'] != 'settings') {
        return null;
      }
      final settings = decoded['settings'];
      return SettingsWindowArguments(
        settings: settings is Map<String, dynamic>
            ? AppSettings.fromJson(settings)
            : const AppSettings(),
      );
    } catch (_) {
      return null;
    }
  }
}
