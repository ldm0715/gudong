import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';
import 'quota_models.dart';

/// AI 额度状态。sidecar 按设置间隔推送 `quota.updated`，连接后先 `quota.get` 取缓存。
class QuotaController extends ChangeNotifier {
  QuotaController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Map<String, QuotaProvider> _providers = const {};
  bool _loaded = false;

  /// 按 sidecar 推送顺序排列的额度服务。
  List<QuotaProvider> get providers => _providers.values.toList(growable: false);

  QuotaProvider? provider(String id) => _providers[id];

  bool get hasProviders => _providers.isNotEmpty;

  Future<void> refresh({String? provider}) async {
    final params = <String, dynamic>{};
    if (provider != null) params['provider'] = provider;
    try {
      await supervisor.call('quota.refresh', params);
    } catch (error) {
      AppLog.write('[quota] refresh failed: $error');
    }
  }

  void _onSupervisorChanged() {
    if (!supervisor.ready) {
      _loaded = false;
      return;
    }
    if (_loaded) return;
    _loaded = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await supervisor.call('quota.get');
      _apply(result);
      notifyListeners();
    } catch (error) {
      AppLog.write('[quota] load failed: $error');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] != 'quota.updated') return;
    _apply(event);
    notifyListeners();
  }

  void _apply(Map<String, dynamic> payload) {
    final raw = payload['providers'];
    if (raw is! List) return;
    final next = <String, QuotaProvider>{};
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final provider = QuotaProvider.fromJson(item);
        if (provider.id.isNotEmpty) next[provider.id] = provider;
      }
    }
    _providers = next;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
