import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import 'quota_controller.dart';
import 'quota_icons.dart';
import 'quota_models.dart';

/// 展开态额度面板：服务按设置顺序纵向排列，内容超出时滚动。
class QuotaTab extends StatefulWidget {
  const QuotaTab({super.key, required this.controller, required this.settings});

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
      separatorBuilder: (_, _) => const SizedBox(height: IslandMetrics.space6),
      itemBuilder: (context, index) => QuotaProviderCard(
        provider: providers[index],
        onRefresh: () => widget.controller.refresh(
          provider: providers[index].id,
        ),
      ),
    );
  }

  QuotaProvider _placeholder(String id) {
    final label = switch (id) {
      'glm' => 'GLM',
      'deepseek' => 'DeepSeek',
      'opencode' => 'OpenCode',
      _ when id.startsWith('newapi:') => 'New API',
      _ => id,
    };
    return QuotaProvider(id: id, label: label, status: 'loading');
  }
}

/// 单个服务的额度卡片：标题、最近刷新时间、手动刷新与各窗口图表。
class QuotaProviderCard extends StatefulWidget {
  const QuotaProviderCard({super.key, required this.provider, this.onRefresh});

  final QuotaProvider provider;
  final Future<void> Function()? onRefresh;

  @override
  State<QuotaProviderCard> createState() => _QuotaProviderCardState();
}

class _QuotaProviderCardState extends State<QuotaProviderCard> {
  Timer? _timeout;
  bool _refreshing = false;

  @override
  void didUpdateWidget(covariant QuotaProviderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新快照到达后停止转圈；无变化或失败时由超时兜底。
    if (_refreshing &&
        oldWidget.provider.updatedAtMs != widget.provider.updatedAtMs) {
      _stopRefreshing();
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final onRefresh = widget.onRefresh;
    if (_refreshing || onRefresh == null) return;
    setState(() => _refreshing = true);
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 20), _stopRefreshing);
    await onRefresh();
  }

  void _stopRefreshing() {
    _timeout?.cancel();
    _timeout = null;
    if (mounted && _refreshing) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final provider = widget.provider;
    final primary = provider.sessionWindow ?? provider.secondaryWindow;
    final tone = quotaTone(colors, primary?.usedPercent);
    final updated = formatUpdatedAt(provider.updatedAtMs);
    final subtitle = [
      provider.plan?.isNotEmpty == true
          ? provider.plan!
          : provider.ok
          ? '已连接'
          : provider.statusLabel,
      if (updated.isNotEmpty) updated,
    ].join(' · ');
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
                logo: provider.logo,
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
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.micro.tint(colors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: IslandMetrics.space8),
              _RefreshButton(
                label: provider.label,
                refreshing: _refreshing,
                onTap: _refresh,
              ),
              if (primary?.hasMeter == true) ...[
                const SizedBox(width: IslandMetrics.space4),
                QuotaRing(
                  value: primary!.remainingValue,
                  color: tone,
                  label: formatPercent(primary.effectiveRemainingPercent),
                ),
              ] else if (!provider.ok) ...[
                const SizedBox(width: IslandMetrics.space8),
                Text(
                  provider.statusLabel,
                  style: IslandTypography.micro.tint(colors.muted),
                ),
              ],
            ],
          ),
          if (provider.ok && provider.windows.isNotEmpty) ...[
            const SizedBox(height: IslandMetrics.space4),
            for (final window in provider.windows)
              _QuotaWindowRow(
                window: window,
                color: quotaTone(colors, window.usedPercent),
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
        ],
      ),
    );
  }
}

/// 自绘刷新按钮，带 hover / focus 与刷新中状态。
class _RefreshButton extends StatefulWidget {
  const _RefreshButton({
    required this.label,
    required this.refreshing,
    required this.onTap,
  });

  final String label;
  final bool refreshing;
  final VoidCallback onTap;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final highlighted = _hover || _focus;
    return Tooltip(
      message: '刷新 ${widget.label}',
      waitDuration: IslandMotion.tooltipDelay,
      child: Semantics(
        button: true,
        label: '刷新 ${widget.label}',
        child: FocusableActionDetector(
          enabled: !widget.refreshing,
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (value) => setState(() => _hover = value),
          onShowFocusHighlight: (value) => setState(() => _focus = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.refreshing ? null : widget.onTap,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: highlighted && !widget.refreshing
                    ? colors.chip
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
              ),
              child: Center(
                child: widget.refreshing
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: colors.muted,
                        ),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        size: 16,
                        color: highlighted ? colors.text : colors.muted,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuotaWindowRow extends StatelessWidget {
  const _QuotaWindowRow({required this.window, required this.color});

  final QuotaWindow window;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    if (!window.hasMeter) {
      return Padding(
        padding: const EdgeInsets.only(top: IslandMetrics.space6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                quotaWindowLabel(window),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IslandTypography.micro.tint(colors.muted),
              ),
            ),
            const SizedBox(width: IslandMetrics.space8),
            Text(
              formatBalance(window),
              style: IslandTypography.bodyStrong.tint(colors.text),
            ),
          ],
        ),
      );
    }
    final reset = formatReset(window.resetsAt);
    return Padding(
      padding: const EdgeInsets.only(top: IslandMetrics.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quotaWindowLabel(window),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IslandTypography.micro.tint(colors.muted),
                ),
              ),
              const SizedBox(width: IslandMetrics.space8),
              if (reset.isNotEmpty) ...[
                Text(
                  '$reset后重置',
                  style: IslandTypography.micro.tint(colors.muted),
                ),
                const SizedBox(width: IslandMetrics.space8),
              ],
              Text(
                formatPercent(window.effectiveRemainingPercent),
                style: IslandTypography.microStrong.tint(color),
              ),
            ],
          ),
          const SizedBox(height: IslandMetrics.space4),
          LinearQuotaMeter(
            value: window.remainingValue,
            color: color,
            thickness: IslandMetrics.space6,
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
          painter: _RingPainter(value: value, color: color, track: colors.chip),
          child: Center(
            child: Text(label, style: IslandTypography.microStrong.tint(color)),
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

/// 横向比例条，按剩余额度填充。
class LinearQuotaMeter extends StatelessWidget {
  const LinearQuotaMeter({
    super.key,
    required this.value,
    required this.color,
    this.thickness = IslandMetrics.space4,
  });

  final double value;
  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final ratio = value.clamp(0.0, 1.0);
    final filled = (ratio * 1000).round();
    final rest = 1000 - filled;
    return ClipRRect(
      borderRadius: BorderRadius.circular(IslandMetrics.pill(thickness)),
      child: SizedBox(
        height: thickness,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (filled > 0)
              Expanded(
                flex: filled,
                child: ColoredBox(color: color),
              ),
            if (rest > 0)
              Expanded(
                flex: rest,
                child: ColoredBox(color: colors.chip),
              ),
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
  'billing' =>
    window.label == 'Balance'
        ? (window.currency != null ? '余额' : window.label)
        : window.label,
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
            '在设置 → AI → 额度中添加并启用',
            style: IslandTypography.caption.tint(colors.muted),
          ),
        ],
      ),
    );
  }
}
