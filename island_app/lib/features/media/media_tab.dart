import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import 'media_controller.dart';

/// 媒体页：左栏曲目与控制，右栏歌词，底部通栏进度。
class MediaTab extends StatefulWidget {
  const MediaTab({super.key, required this.controller});

  final MediaController controller;

  @override
  State<MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends State<MediaTab> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final media = widget.controller;
    if (!media.available) return _EmptyMedia(colors: colors);

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 132,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Artwork(bytes: media.artwork, colors: colors),
                    const SizedBox(height: IslandMetrics.space6),
                    Text(
                      media.title ?? '未知曲目',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: IslandTypography.bodyStrong.tint(colors.text),
                    ),
                    const SizedBox(height: IslandMetrics.space2),
                    Text(
                      [
                        media.artist?.isNotEmpty == true
                            ? media.artist!
                            : '未知艺术家',
                        if (media.sourceLabel.isNotEmpty) media.sourceLabel,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: IslandTypography.micro.tint(colors.muted),
                    ),
                    const SizedBox(height: IslandMetrics.space8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ControlButton(
                          icon: Icons.skip_previous_rounded,
                          tooltip: '上一首',
                          onTap: media.previous,
                        ),
                        const SizedBox(width: IslandMetrics.space8),
                        _PlayButton(
                          playing: media.playing,
                          onTap: media.toggle,
                        ),
                        const SizedBox(width: IslandMetrics.space8),
                        _ControlButton(
                          icon: Icons.skip_next_rounded,
                          tooltip: '下一首',
                          onTap: media.next,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: colors.divider,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _LyricsView(media: media, colors: colors),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: IslandMetrics.space2),
        ValueListenableBuilder<int>(
          valueListenable: media.ticks,
          builder: (context, _, _) {
            final max = media.duration > 0 ? media.duration : 1.0;
            final current = (_dragPosition ?? media.positionNow)
                .clamp(0, max)
                .toDouble();
            return Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    _time(current),
                    style: IslandTypography.micro.copyWith(
                      color: colors.muted,
                      fontFeatures: IslandTypography.tabularFigures,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: colors.accent,
                      inactiveTrackColor: colors.chip,
                      thumbColor: colors.accent,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 4.5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 9,
                      ),
                      overlayColor: colors.accent.withValues(alpha: 0.12),
                    ),
                    child: SizedBox(
                      height: 16,
                      child: Slider(
                        value: current,
                        max: max,
                        onChanged: media.duration > 0
                            ? (value) => setState(() => _dragPosition = value)
                            : null,
                        onChangeEnd: media.duration > 0
                            ? (value) {
                                setState(() => _dragPosition = null);
                                media.seek(value);
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    media.duration > 0 ? _time(media.duration) : '--:--',
                    textAlign: TextAlign.right,
                    style: IslandTypography.micro.copyWith(
                      color: colors.muted,
                      fontFeatures: IslandTypography.tabularFigures,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _time(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
    final minutes = total ~/ 60;
    final rest = total % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

/// 右栏歌词：当前行居中，切行时整列缓动滚动。
class _LyricsView extends StatefulWidget {
  const _LyricsView({required this.media, required this.colors});

  final MediaController media;
  final IslandColors colors;

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView>
    with SingleTickerProviderStateMixin {
  static const double _rowHeight = 17;
  static const int _visibleRows = 7;
  static const double _viewportHeight = _rowHeight * _visibleRows;
  static const double _centerOffset = _viewportHeight / 2 - _rowHeight / 2;

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: IslandMotion.progress,
    value: 1,
  );
  List<LyricLine>? _lastLyrics;
  int _lastIndex = -2;
  double _from = 0;
  double _to = 0;

  double get _position {
    final t = IslandMotion.standard.transform(_animation.value);
    return _from + (_to - _from) * t;
  }

  @override
  void initState() {
    super.initState();
    widget.media.addListener(_sync);
    widget.media.ticks.addListener(_sync);
    _reset(widget.media.lyrics);
  }

  @override
  void dispose() {
    widget.media.removeListener(_sync);
    widget.media.ticks.removeListener(_sync);
    _animation.dispose();
    super.dispose();
  }

  void _reset(List<LyricLine> lyrics) {
    _lastLyrics = lyrics;
    _lastIndex = widget.media.lyricIndex;
    _to = _from = _lastIndex < 0 ? 0 : _lastIndex.toDouble();
    _animation.value = 1;
  }

  void _sync() {
    final lyrics = widget.media.lyrics;
    if (!identical(lyrics, _lastLyrics)) {
      _reset(lyrics);
      if (mounted) setState(() {});
      return;
    }
    final index = widget.media.lyricIndex;
    if (index == _lastIndex) return;
    _from = _position;
    _to = index < 0 ? 0 : index.toDouble();
    _lastIndex = index;
    _animation.forward(from: 0);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final colors = widget.colors;
    final lines = media.lyrics;
    if (lines.isEmpty) {
      return Center(
        child: Text(
          media.lyricsLoading ? '歌词加载中…' : '暂无歌词',
          style: IslandTypography.caption.tint(colors.muted),
        ),
      );
    }
    final index = media.lyricIndex;
    final rows = <Widget>[
      for (var line = 0; line < lines.length; line++)
        _LyricRow(
          text: lines[line].text,
          highlighted: line == index,
          distance: index < 0 ? 2 : (line - index).abs(),
          colors: colors,
        ),
    ];
    return Center(
      child: SizedBox(
        height: _viewportHeight,
        width: double.infinity,
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: _animation,
              // 歌词总高度远超可视区，必须解除纵向约束，否则 Column 会报溢出。
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
              builder: (context, child) => Transform.translate(
                offset: Offset(0, _centerOffset - _position * _rowHeight),
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: constraints.maxWidth,
                  maxWidth: constraints.maxWidth,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    required this.text,
    required this.highlighted,
    required this.distance,
    required this.colors,
  });

  final String text;
  final bool highlighted;
  final int distance;
  final IslandColors colors;

  @override
  Widget build(BuildContext context) {
    final alpha = highlighted ? 1.0 : (distance <= 1 ? 0.7 : 0.42);
    return SizedBox(
      height: 17,
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style:
              (highlighted ? IslandTypography.caption : IslandTypography.micro)
                  .copyWith(
                    color: highlighted
                        ? colors.accent
                        : colors.muted.withValues(alpha: alpha),
                    fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
                    height: 1.25,
                  ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.bytes, required this.colors});

  final Uint8List? bytes;
  final IslandColors colors;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
      child: Container(
        width: 52,
        height: 52,
        color: colors.chip,
        child: image == null
            ? Icon(
                Icons.music_note_rounded,
                size: IslandMetrics.iconXL,
                color: colors.muted,
              )
            : Image.memory(
                image,
                width: 52,
                height: 52,
                // 封面原图常有 640–1000px，按显示尺寸解码，避免图片缓存常驻几十 MB。
                cacheWidth: 104,
                cacheHeight: 104,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Tooltip(
      message: playing ? '暂停' : '播放',
      waitDuration: IslandMotion.tooltipDelay,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: IslandMetrics.iconLG,
            color: colors.background,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Tooltip(
      message: tooltip,
      waitDuration: IslandMotion.tooltipDelay,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusCover),
        child: Padding(
          padding: const EdgeInsets.all(IslandMetrics.space5),
          child: Icon(icon, size: IslandMetrics.iconLG, color: colors.text),
        ),
      ),
    );
  }
}

class _EmptyMedia extends StatelessWidget {
  const _EmptyMedia({required this.colors});

  final IslandColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note_rounded,
            size: IslandMetrics.icon2XL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space8),
          Text('暂无正在播放的媒体', style: IslandTypography.subhead.tint(colors.text)),
          const SizedBox(height: IslandMetrics.space4),
          Text(
            '用任意播放器播放音乐后，这里会显示曲目与控制',
            style: IslandTypography.caption.tint(colors.muted),
          ),
        ],
      ),
    );
  }
}
