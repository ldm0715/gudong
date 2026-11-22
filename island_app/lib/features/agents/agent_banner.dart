import 'package:flutter/material.dart';

import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_typography.dart';
import '../island/island_layout.dart';
import 'agent_glyph.dart';
import 'agent_models.dart';

/// 回合结束横幅：agent 图标 + 会话标题 + 结束时间 + 一行回复摘要。
class AgentBanner extends StatelessWidget {
  const AgentBanner({super.key, required this.item});

  final AgentFinished item;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final info = AgentCatalog.byId(item.id);
    final label = info?.label ?? item.label;
    final title = item.title.trim().isEmpty ? label : item.title.trim();
    final reply = item.replyPreview?.trim() ?? '';
    final accent = item.aborted ? colors.warning : colors.text;
    return SizedBox(
      width: IslandLayout.bannerSize.width,
      height: IslandLayout.bannerSize.height,
      child: Semantics(
        label: '$label 会话结束：$title',
        child: Padding(
          padding: const EdgeInsets.all(IslandMetrics.space16),
          child: Row(
            children: [
              AgentGlyph(id: item.id, size: 30),
              const SizedBox(width: IslandMetrics.space12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: IslandTypography.subhead.tint(accent),
                          ),
                        ),
                        const SizedBox(width: IslandMetrics.space8),
                        Text(
                          formatAgentClock(item.endedAtMs),
                          style: IslandTypography.caption.tint(colors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: IslandMetrics.space5),
                    Text(
                      reply.isNotEmpty ? reply : _fallback(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.body.tint(colors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fallback() {
    final duration = item.durationMs;
    if (item.aborted) {
      return duration != null && duration > 0
          ? '本轮已中断 · 用时 ${formatAgentDuration(duration)}'
          : '本轮已中断';
    }
    if (duration != null && duration > 0) {
      return '本轮已结束 · 用时 ${formatAgentDuration(duration)}';
    }
    return '本轮已结束';
  }
}
