import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import 'quota_controller.dart';
import 'quota_icons.dart';
import 'quota_models.dart';

/// 展开态额度面板：服务按设置顺序纵向排列，内容超出时滚动。
class QuotaTab extends StatefulWidget {
  const QuotaTab({
    super.key,
    required this.controller,
    required this.settings,
  });

  final QuotaController controller;
  final AppSettings settings;

  @override
  State<QuotaTab> createState() => _QuotaTabState();
}

class _QuotaTabState extends State<QuotaTab> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // 重置倒计时每分钟刷新一次，只在展开态运行。
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.settings.visibleQuotaProviders;
    if (ids.isEmpty) return _EmptyQuota(colors: context.islandColors);
    final providers = [
      for (final id in ids) widget.controller.provider(id) ?? _placeholder(id),
    ];
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: providers.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: IslandMetrics.space6),
      itemBuilder: (context, index) =>
          QuotaProviderCard(provider: providers[index]),
    );
  }

  QuotaProvider _placeholder(String id) {
    final label = switch (id) {
      'glm' => 'GLM',
      'deepseek' => 'DeepSeek',
      'opencode' => 'OpenCode',
      _ => id,
    };
    return QuotaProvider(id: id, label: label, status: 'loading');
  }
}

/// 单个服务的额度卡片：标题、每个窗口的图表与余额。
class QuotaProviderCard extends StatelessWidget {
  const QuotaProviderCard({super.key, required this.provider});

  final QuotaProvider provider;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final primary = provider.sessionWindow ?? provider.secondaryWindow;
    final tone = quotaTone(colors, primary?.usedPercent);
    final reset = formatReset(primary?.resetsAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        IslandMetrics.space10,
        IslandMetrics.space8,
        IslandMetrics.space10,
        IslandMetrics.space8,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              QuotaProviderIcon(
                id: provider.id,
                fallback: provider.shortLabel,
                color: tone,
                size: IslandMetrics.iconXL,
              ),
              const SizedBox(width: IslandMetrics.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      provider.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.bodyStrong.tint(colors.text),
                    ),
                    Text(
                      provider.plan?.isNotEmpty == true
                          ? provider.plan!
                          : provider.ok
                          ? '已连接'
                          : provider.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.micro.tint(colors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: IslandMetrics.space8),
              if (primary?.hasMeter == true)
                QuotaRing(
                  value: primary!.meterValue,
                  color: tone,
                  label: formatPercent(primary.usedPercent),
                )
              else if (!provider.ok)
                Text(
                  provider.statusLabel,
                  style: IslandTypography.micro.tint(colors.muted),
                ),
            ],
          ),
          if (provider.ok && provider.windows.isNotEmpty) ...[
            const SizedBox(height: IslandMetrics.space7),
            for (final window in provider.windows)
              _QuotaWindowRow(
                window: window,
                color: quotaTone(colors, window.usedPercent),
                showReset: !identical(window, primary),
              ),
          ] else if (!provider.ok) ...[
            const SizedBox(height: IslandMetrics.space6),
            Text(
              provider.message?.isNotEmpty == true
                  ? provider.message!
                  : provider.statusLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IslandTypography.micro.tint(colors.muted),
            ),
          ],
          if (reset.isNotEmpty) ...[
            const SizedBox(height: IslandMetrics.space4),
            Text(
              '$reset后重置',
              textAlign: TextAlign.right,
              style: IslandTypography.micro.tint(colors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuotaWindowRow extends StatelessWidget {
  const _QuotaWindowRow({
    required this.window,
    required this.color,
    required this.showReset,
  });

  final QuotaWindow window;
  final Color color;
  final bool showReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    if (!window.hasMeter) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: IslandMetrics.space3),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                quotaWindowLabel(window),
                style: IslandTypography.micro.tint(colors.muted),
              ),
            ),
            Expanded(
              child: Text(
                '可用余额',
                style: IslandTypography.micro.tint(colors.muted),
              ),
            ),
            Text(
              formatBalance(window),
              style: IslandTypography.bodyStrong.tint(colors.text),
            ),
          ],
        ),
      );
    }
    final reset = showReset ? formatReset(window.resetsAt) : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IslandMetrics.space2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              quotaWindowLabel(window),
              style: IslandTypography.micro.tint(colors.muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearQuotaMeter(value: window.meterValue, color: color),
                const SizedBox(height: IslandMetrics.space2),
                Row(
                  children: [
                    Text(
                      '剩余 ${formatPercent(window.remainingPercent)}',
                      style: IslandTypography.micro.tint(colors.muted),
                    ),
                    if (reset.isNotEmpty) ...[
                      const Spacer(),
                      Text(
                        '$reset后重置',
                        style: IslandTypography.micro.tint(colors.muted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: IslandMetrics.space6),
          SizedBox(
            width: 32,
            child: Text(
              formatPercent(window.usedPercent),
              textAlign: TextAlign.right,
              style: IslandTypography.microStrong.tint(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 环形图表，用于主窗口的已用比例。
class QuotaRing extends StatelessWidget {
  const QuotaRing({
    super.key,
    required this.value,
    required this.color,
    required this.label,
  });

  final double value;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return RepaintBoundary(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CustomPaint(
          painter: _RingPainter(value: value, color: color, track: colors.divider),
          child: Center(
            child: Text(
              label,
              style: IslandTypography.microStrong.tint(color),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = IslandMetrics.space3;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// 横向比例条。
class LinearQuotaMeter extends StatelessWidget {
  const LinearQuotaMeter({
    super.key,
    required this.value,
    required this.color,
  });

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final filled = (value * 100).round().clamp(1, 100);
    final rest = 100 - filled;
    return ClipRRect(
      borderRadius: BorderRadius.circular(IslandMetrics.radiusBar),
      child: SizedBox(
        height: IslandMetrics.space3,
        child: Row(
          children: [
            Expanded(flex: filled, child: ColoredBox(color: color)),
            if (rest > 0)
              Expanded(flex: rest, child: ColoredBox(color: colors.divider)),
          ],
        ),
      ),
    );
  }
}

String quotaWindowLabel(QuotaWindow window) => switch (window.kind) {
  'session' => '5小时',
  'weekly' => '本周',
  'monthly' => '本月',
  'billing' => window.currency != null ? '余额' : window.label,
  _ => window.label,
};

Color quotaTone(IslandColors colors, double? used) {
  if (used == null) return colors.muted;
  if (used >= 85) return colors.warning;
  if (used >= 60) return colors.accent;
  return colors.text;
}

class _EmptyQuota extends StatelessWidget {
  const _EmptyQuota({required this.colors});

  final IslandColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: IslandMetrics.icon2XL,
            color: colors.muted,
          ),
          const SizedBox(height: IslandMetrics.space8),
          Text('未启用额度服务', style: IslandTypography.subhead.tint(colors.text)),
          const SizedBox(height: IslandMetrics.space4),
          Text(
            '在设置 → AI 额度中添加并启用',
            style: IslandTypography.caption.tint(colors.muted),
          ),
        ],
      ),
    );
  }
}
