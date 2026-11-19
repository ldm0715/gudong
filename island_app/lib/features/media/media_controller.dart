import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/ipc/sidecar_supervisor.dart';
import '../../core/log.dart';

class LyricLine {
  const LyricLine({required this.time, required this.text});

  final double time;
  final String text;
}

/// 媒体状态。数据只来自 sidecar 的 `media.changed` 事件与 `media.get` 快照。
/// 播放进度由本地定时器插值，避免依赖高频事件。
class MediaController extends ChangeNotifier {
  MediaController(this.supervisor) {
    supervisor.addListener(_onSupervisorChanged);
    _subscription = supervisor.events.listen(_onEvent);
  }

  final SidecarSupervisor supervisor;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _ticker;
  Timer? _seekTimer;
  double? _seekTarget;
  bool _loaded = false;

  /// 独立的进度时钟：只驱动进度条，不触发岛体外壳重建。
  final ValueNotifier<int> ticks = ValueNotifier(0);

  String? title;
  String? artist;
  String? album;
  String? source;
  String kind = 'unknown';
  bool playing = false;
  bool available = false;
  double position = 0;
  double duration = 0;
  Uint8List? artwork;
  List<LyricLine> lyrics = const [];
  bool lyricsLoading = false;
  DateTime _sampledAt = DateTime.now();

  /// 按采样时刻外推的播放位置。暂停或不可用时返回快照值。
  double get positionNow {
    if (!available) return 0;
    final max = duration > 0 ? duration : double.infinity;
    if (!playing) return position.clamp(0, max).toDouble();
    final elapsed =
        DateTime.now().difference(_sampledAt).inMilliseconds / 1000.0;
    return (position + elapsed).clamp(0, max).toDouble();
  }

  String get sourceLabel {
    final raw = source ?? '';
    if (raw.isEmpty) return '';
    return raw.replaceAll('.exe', '').replaceAll('.EXE', '');
  }

  /// 当前时间点对应的歌词行。尚未开始时返回 -1。
  int get lyricIndex {
    if (!available || lyrics.isEmpty) return -1;
    final seconds = positionNow;
    var low = 0;
    var high = lyrics.length - 1;
    var found = -1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (lyrics[middle].time <= seconds) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }

  /// 当前时间点对应的歌词。没有歌词或尚未开始时返回 `null`。
  String? get currentLyric {
    final index = lyricIndex;
    return index >= 0 ? lyrics[index].text : null;
  }

  Future<void> refresh() async {
    try {
      final result = await supervisor.call('media.get');
      final media = result['media'];
      if (media is Map<String, dynamic>) _apply(media);
      final lyricResult = await supervisor.call('lyrics.get');
      lyrics = _parseLyrics(lyricResult['lyrics']);
      lyricsLoading = lyricResult['pending'] == true;
      notifyListeners();
    } catch (error) {
      AppLog.write('[media] refresh failed: $error');
    }
  }

  Future<void> toggle() async {
    if (!available) return;
    // 先本地切换，事件到达后校正。
    playing = !playing;
    _sampledAt = DateTime.now();
    _syncTicker();
    notifyListeners();
    await _command('toggle');
  }

  Future<void> next() => _command('next');

  Future<void> previous() => _command('previous');

  Future<void> seek(double seconds) async {
    if (!available || duration <= 0) return;
    final target = seconds.clamp(0, duration).toDouble();
    position = target;
    _sampledAt = DateTime.now();
    _seekTarget = target;
    _seekTimer?.cancel();
    // 播放器确认前先保持目标位置。旧进度事件可能比跳转命令晚到，
    // 不能让它把滑块拉回原处；5 秒后仍未确认则接受播放器的真实进度。
    _seekTimer = Timer(const Duration(seconds: 5), () {
      _seekTarget = null;
      _seekTimer = null;
      unawaited(refresh());
    });
    notifyListeners();
    await _command('seek', position: target, refreshOnFailure: false);
  }

  void _clearSeekWait() {
    _seekTimer?.cancel();
    _seekTimer = null;
    _seekTarget = null;
  }

  Future<void> _command(
    String action, {
    double? position,
    bool refreshOnFailure = true,
  }) async {
    try {
      final result = await supervisor.call('media.control', {
        'action': action,
        if (source != null && source!.isNotEmpty) 'source': source,
        'position': ?position,
      });
      if (result['ok'] != true) {
        AppLog.write('[media] $action rejected: ${result['message'] ?? ''}');
        if (refreshOnFailure) await refresh();
      }
    } catch (error) {
      AppLog.write('[media] $action failed: $error');
    }
  }

  void _apply(Map<String, dynamic> media) {
    final wasAvailable = available;
    available = media['available'] == true;
    if (!available) {
      final changed = wasAvailable || title != null;
      _clearSeekWait();
      title = null;
      artist = null;
      album = null;
      source = null;
      kind = 'unknown';
      playing = false;
      position = 0;
      duration = 0;
      artwork = null;
      lyrics = const [];
      lyricsLoading = false;
      _stopTicker();
      if (changed) notifyListeners();
      return;
    }

    final track = media['title']?.toString();
    final trackChanged = track != title;
    if (trackChanged) {
      _clearSeekWait();
      lyrics = const [];
      lyricsLoading = true;
    }
    title = track;
    artist = media['artist']?.toString();
    album = media['album']?.toString();
    source = media['source']?.toString();
    kind = media['kind']?.toString() ?? 'unknown';
    playing = media['playing'] == true;
    duration = (media['duration'] as num?)?.toDouble() ?? 0;
    final incoming = (media['position'] as num?)?.toDouble() ?? 0;
    final target = _seekTarget;
    if (target == null) {
      position = incoming;
      _sampledAt = DateTime.now();
    } else if ((incoming - target).abs() <= 2.0) {
      _clearSeekWait();
      position = incoming;
      _sampledAt = DateTime.now();
    }
    // 等待跳转确认期间保留目标位置，不采用播放器上报的旧进度。
    final rawArtwork = media['artwork'];
    if (rawArtwork is String && rawArtwork.isNotEmpty) {
      artwork = _decodeArtwork(rawArtwork) ?? artwork;
    } else if (trackChanged) {
      artwork = null;
    }
    _syncTicker();
    notifyListeners();
  }

  Uint8List? _decodeArtwork(String dataUri) {
    try {
      final comma = dataUri.indexOf(',');
      final payload = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
      return base64Decode(payload);
    } catch (error) {
      AppLog.write('[media] artwork decode failed: $error');
      return null;
    }
  }

  void _syncTicker() {
    if (available && playing) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        ticks.value++;
      });
    } else {
      _stopTicker();
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onSupervisorChanged() {
    if (!supervisor.ready) {
      _loaded = false;
      available = false;
      _clearSeekWait();
      _stopTicker();
      return;
    }
    if (_loaded) return;
    _loaded = true;
    unawaited(refresh());
  }

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'media.changed':
        final media = event['media'];
        if (media is Map<String, dynamic>) _apply(media);
      case 'media.lyrics':
        lyrics = _parseLyrics(event['lyrics']);
        lyricsLoading = event['pending'] == true;
        notifyListeners();
    }
  }

  List<LyricLine> _parseLyrics(Object? raw) {
    if (raw is! Map) return const [];
    final lines = raw['lines'];
    if (lines is! List) return const [];
    final parsed = <LyricLine>[];
    for (final line in lines) {
      if (line is! Map) continue;
      final time = (line['time'] as num?)?.toDouble();
      final text = line['text']?.toString();
      if (time == null || text == null || text.isEmpty) continue;
      parsed.add(LyricLine(time: time, text: text));
    }
    return parsed;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stopTicker();
    _clearSeekWait();
    ticks.dispose();
    supervisor.removeListener(_onSupervisorChanged);
    super.dispose();
  }
}
