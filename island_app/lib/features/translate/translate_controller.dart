import 'package:flutter/widgets.dart';

import '../../core/ipc/json_rpc_client.dart';
import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';

/// 翻译页状态。请求走 sidecar，进度与结果只在本页展示。
class TranslateController extends ChangeNotifier {
  TranslateController(this.supervisor) {
    input.addListener(_onInputChanged);
  }

  final SidecarSupervisor supervisor;

  /// 放在 controller 里，切换 tab 后输入内容不会丢。
  final TextEditingController input = TextEditingController();

  /// 输入清空时，译文和错误一起清掉，避免残留上一次结果。
  void _onInputChanged() {
    if (input.text.trim().isNotEmpty) return;
    if (_result.isEmpty && _error.isEmpty && _provider.isEmpty && !_pending) {
      return;
    }
    clearResult();
  }

  String _result = '';
  String _error = '';
  String _provider = '';
  bool _pending = false;
  int _sequence = 0;

  String get result => _result;
  String get error => _error;
  String get provider => _provider;
  bool get pending => _pending;

  Future<void> translate(
    String text, {
    required String to,
    String provider = 'auto',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _pending) return;
    final sequence = ++_sequence;
    _pending = true;
    _error = '';
    notifyListeners();
    try {
      final payload = await supervisor.call(
        'translate.run',
        {'text': trimmed, 'to': to, 'provider': provider},
        const Duration(seconds: 90),
      );
      if (sequence != _sequence) return;
      _result = payload['text']?.toString() ?? '';
      _provider = payload['provider']?.toString() ?? '';
      _error = '';
    } catch (error) {
      if (sequence != _sequence) return;
      _result = '';
      _provider = '';
      _error = error is RpcException ? error.message : '$error';
      AppLog.write('[translate] run failed: $error');
    } finally {
      if (sequence == _sequence) {
        _pending = false;
        notifyListeners();
      }
    }
  }

  void clearResult() {
    _sequence++;
    _result = '';
    _error = '';
    _provider = '';
    _pending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    input.removeListener(_onInputChanged);
    input.dispose();
    super.dispose();
  }
}
