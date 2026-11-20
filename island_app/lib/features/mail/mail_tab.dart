import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/settings/settings_controller.dart';
import '../../core/theme/island_colors.dart';
import '../../core/theme/island_metrics.dart';
import '../../core/theme/island_motion.dart';
import '../../core/theme/island_typography.dart';
import '../translate/translate_languages.dart';
import 'mail_controller.dart';
import 'mail_models.dart';
import 'mail_provider_badge.dart';

/// 岛体邮箱页：收件箱列表与紧凑的纯文本详情。
class MailTab extends StatelessWidget {
  const MailTab({
    super.key,
    required this.controller,
    required this.settings,
    required this.onOpenSettings,
  });

  final MailController controller;
  final SettingsController settings;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final detail = controller.detail;
    if (detail != null) {
      return _MailDetailView(
        controller: controller,
        detail: detail,
        target: settings.settings.translateTarget,
        provider: settings.settings.mailTranslateProvider,
        onTargetChanged: (code) => unawaited(
          settings.save(
            settings.settings.copyWith(translateTarget: code),
          ),
        ),
      );
    }
    return _MailListView(
      controller: controller,
      onOpenSettings: onOpenSettings,
    );
  }
}

class _MailListView extends StatelessWidget {
  const _MailListView({
    required this.controller,
    required this.onOpenSettings,
  });

  final MailController controller;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final items = controller.visibleItems;
    final accounts = controller.accounts;
    final unread = controller.visibleUnreadCount;
    final attention = accounts.where((account) => account.needsAttention);
    return Column(
      children: [
        Row(
          children: [
            Text('收件箱', style: IslandTypography.bodyStrong.tint(colors.text)),
            if (unread > 0) ...[
              const SizedBox(width: IslandMetrics.space5),
              Text(
                '$unread 未读',
                style: IslandTypography.micro.tint(colors.accent),
              ),
            ],
            const Spacer(),
            if (accounts.length > 1) ...[
              const SizedBox(width: IslandMetrics.space4),
              _AccountFilterButton(controller: controller),
            ],
            if (unread > 0)
              _IconTap(
                icon: Icons.done_all_rounded,
                tooltip: controller.accountFilter == null
                    ? '全部标为已读'
                    : '将当前邮箱标为已读',
                busy: controller.markingRead,
                onTap: () => unawaited(controller.markAllRead()),
              ),
            if (attention.isNotEmpty)
              Tooltip(
                message:
                    '${attention.first.displayName}：${attention.first.message.isEmpty ? attention.first.stateLabel : attention.first.message}',
                waitDuration: IslandMotion.tooltipDelay,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IslandMetrics.space2,
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: IslandMetrics.iconXS,
                    color: colors.warning,
                  ),
                ),
              ),
            _IconTap(
              icon: Icons.refresh_rounded,
              tooltip: '刷新收件箱',
              busy: controller.refreshing,
              onTap: () => unawaited(controller.refresh()),
            ),
          ],
        ),
        if (controller.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: IslandMetrics.space2),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: IslandMetrics.iconXS,
                  color: colors.warning,
                ),
                const SizedBox(width: IslandMetrics.space4),
                Expanded(
                  child: Text(
                    controller.error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.micro.tint(colors.warning),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: IslandMetrics.space2),
        Expanded(
          child: items.isEmpty
              ? (controller.accountFilter != null
                    ? _EmptyState(
                        icon: Icons.inbox_outlined,
                        title: '这个邮箱没有邮件',
                        detail: '当前只显示所选账号的邮件',
                        action: '查看全部',
                        onAction: () => controller.setAccountFilter(null),
                      )
                    : _EmptyInbox(
                        accounts: accounts,
                        onOpenSettings: onOpenSettings,
                      ))
              : RepaintBoundary(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: colors.divider),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _MailRow(
                        item: item,
                        account: controller.accountFor(item.accountId),
                        opening: controller.openingId == item.id,
                        onTap: () => unawaited(controller.open(item)),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _AccountFilterButton extends StatefulWidget {
  const _AccountFilterButton({required this.controller});

  final MailController controller;

  @override
  State<_AccountFilterButton> createState() => _AccountFilterButtonState();
}

class _AccountFilterButtonState extends State<_AccountFilterButton> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final selected = widget.controller.accountFilter;
    final account = selected == null
        ? null
        : widget.controller.accountFor(selected);
    final label = account == null ? '全部' : _filterLabel(account);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _portal.hide,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, IslandMetrics.space4),
            child: _AccountFilterMenu(
              controller: widget.controller,
              onClose: _portal.hide,
            ),
          ),
        ],
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: Semantics(
          button: true,
          label: '筛选邮箱：$label',
          child: Tooltip(
            message: account == null ? '筛选邮箱：全部' : '筛选邮箱：${account.email}',
            waitDuration: IslandMotion.tooltipDelay,
            child: InkWell(
              borderRadius: BorderRadius.circular(IslandMetrics.radiusPill),
              onTap: () => _portal.isShowing ? _portal.hide() : _portal.show(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: IslandMetrics.space6,
                  vertical: IslandMetrics.space2,
                ),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(IslandMetrics.radiusPill),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (account != null)
                      MailProviderBadge(
                        provider: account.provider,
                        email: account.email,
                        size: IslandMetrics.iconSM,
                        color: colors.muted,
                      )
                    else
                      Icon(
                        Icons.all_inbox_rounded,
                        size: IslandMetrics.iconXS,
                        color: colors.muted,
                      ),
                    const SizedBox(width: IslandMetrics.space4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IslandTypography.micro.tint(colors.muted),
                      ),
                    ),
                    const SizedBox(width: IslandMetrics.space2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: IslandMetrics.iconSM,
                      color: colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountFilterMenu extends StatelessWidget {
  const _AccountFilterMenu({required this.controller, required this.onClose});

  final MailController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final selected = controller.accountFilter;
    return Container(
      width: 184,
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.all(IslandMetrics.space4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusPanel),
        border: Border.all(color: colors.stroke),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          _AccountFilterEntry(
            label: '全部邮箱',
            selected: selected == null,
            icon: Icons.all_inbox_rounded,
            onTap: () {
              controller.setAccountFilter(null);
              onClose();
            },
          ),
          for (final account in controller.accounts)
            _AccountFilterEntry(
              label: _filterLabel(account),
              tooltip: '${account.providerLabel} · ${account.email}',
              selected: selected == account.id,
              account: account,
              onTap: () {
                controller.setAccountFilter(account.id);
                onClose();
              },
            ),
        ],
      ),
    );
  }
}

class _AccountFilterEntry extends StatelessWidget {
  const _AccountFilterEntry({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.account,
    this.tooltip,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final MailAccount? account;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final entry = InkWell(
      borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: IslandMetrics.space6,
          vertical: IslandMetrics.space4,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
        ),
        child: Row(
          children: [
            if (account != null)
              MailProviderBadge(
                provider: account!.provider,
                email: account!.email,
                size: IslandMetrics.iconMD,
                color: selected ? colors.accent : colors.muted,
              )
            else
              Icon(
                icon ?? Icons.all_inbox_rounded,
                size: IslandMetrics.iconSM,
                color: selected ? colors.accent : colors.muted,
              ),
            const SizedBox(width: IslandMetrics.space6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IslandTypography.micro.copyWith(
                  color: selected ? colors.accent : colors.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: IslandMetrics.iconSM,
                color: colors.accent,
              ),
          ],
        ),
      ),
    );
    if (tooltip == null) return entry;
    return Tooltip(
      message: tooltip!,
      waitDuration: IslandMotion.tooltipDelay,
      child: entry,
    );
  }
}

String _emailLocalPart(MailAccount account) {
  final at = account.email.indexOf('@');
  return at > 0 ? account.email.substring(0, at) : account.email;
}

String _filterLabel(MailAccount account) {
  final local = _emailLocalPart(account);
  final label = account.label?.trim() ?? '';
  return label.isEmpty ? local : '$label（$local）';
}

class _MailRow extends StatelessWidget {
  const _MailRow({
    required this.item,
    required this.account,
    required this.opening,
    required this.onTap,
  });

  final MailSummary item;
  final MailAccount? account;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final accountName = account?.displayName ?? '';
    return Tooltip(
      message: accountName.isEmpty
          ? item.fromAddress
          : '$accountName\n${item.fromAddress}',
      waitDuration: IslandMotion.tooltipDelay,
      child: InkWell(
        borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: item.unread ? colors.accent : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: IslandMetrics.space8),
              MailProviderBadge(
                provider: account?.provider ?? 'custom',
                email: account?.email,
                size: IslandMetrics.iconMD,
                color: item.unread ? colors.accent : colors.muted,
              ),
              const SizedBox(width: IslandMetrics.space6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.from,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: IslandTypography.bodyStrong.tint(
                              colors.text,
                            ),
                          ),
                        ),
                        if (item.hasAttachments) ...[
                          Icon(
                            Icons.attach_file_rounded,
                            size: IslandMetrics.iconXS,
                            color: colors.muted,
                          ),
                          const SizedBox(width: IslandMetrics.space3),
                        ],
                        if (opening)
                          SizedBox(
                            width: IslandMetrics.iconXS,
                            height: IslandMetrics.iconXS,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: colors.accent,
                            ),
                          )
                        else
                          Text(
                            item.timeLabel,
                            style: IslandTypography.micro
                                .tint(colors.muted)
                                .copyWith(
                                  fontFeatures:
                                      IslandTypography.tabularFigures,
                                ),
                          ),
                      ],
                    ),
                    const SizedBox(height: IslandMetrics.space2),
                    Text(
                      item.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IslandTypography.caption.tint(colors.muted),
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
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({
    required this.accounts,
    required this.onOpenSettings,
  });

  final List<MailAccount> accounts;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return _EmptyState(
        icon: Icons.mark_email_unread_outlined,
        title: '未添加邮箱',
        detail: '在设置 → 邮箱中添加账号',
        action: '打开设置',
        onAction: onOpenSettings,
      );
    }
    final pending = accounts.where((account) => !account.ready).toList();
    if (pending.isNotEmpty) {
      final account = pending.first;
      return _EmptyState(
        icon: account.needsAttention
            ? Icons.error_outline_rounded
            : Icons.sync_rounded,
        title: '${account.displayName} ${account.stateLabel}',
        detail: account.message.isNotEmpty
            ? account.message
            : '正在读取最近 20 封邮件',
        action: pending.length > 1 ? '还有 ${pending.length - 1} 个账号' : null,
        onAction: onOpenSettings,
      );
    }
    return _EmptyState(
      icon: Icons.inbox_outlined,
      title: '收件箱为空',
      detail: '最近没有新邮件',
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: IslandMetrics.iconXL, color: colors.muted),
          const SizedBox(height: IslandMetrics.space6),
          Text(title, style: IslandTypography.subhead.tint(colors.text)),
          const SizedBox(height: IslandMetrics.space3),
          Text(
            detail,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: IslandTypography.caption.tint(colors.muted),
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(height: IslandMetrics.space8),
            InkWell(
              borderRadius: BorderRadius.circular(IslandMetrics.radiusControl),
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: IslandMetrics.space10,
                  vertical: IslandMetrics.space4,
                ),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                    IslandMetrics.radiusControl,
                  ),
                ),
                child: Text(
                  action!,
                  style: IslandTypography.caption.tint(colors.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TranslationTargetButton extends StatefulWidget {
  const _TranslationTargetButton({
    required this.target,
    required this.onChanged,
  });

  final String target;
  final ValueChanged<String> onChanged;

  @override
  State<_TranslationTargetButton> createState() =>
      _TranslationTargetButtonState();
}

class _TranslationTargetButtonState extends State<_TranslationTargetButton> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final label = translateLanguageLabel(widget.target);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _portal.hide,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, IslandMetrics.space4),
            child: _TranslationTargetMenu(
              target: widget.target,
              onSelected: (code) {
                widget.onChanged(code);
                _portal.hide();
              },
            ),
          ),
        ],
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: Semantics(
          button: true,
          label: '翻译目标语言：$label',
          child: Tooltip(
            message: '翻译目标语言：$label',
            waitDuration: IslandMotion.tooltipDelay,
            child: InkWell(
              borderRadius: BorderRadius.circular(IslandMetrics.radiusPill),
              onTap: () => _portal.isShowing ? _portal.hide() : _portal.show(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: IslandMetrics.space5,
                  vertical: IslandMetrics.space2,
                ),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(IslandMetrics.radiusPill),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.translate_rounded,
                      size: IslandMetrics.iconXS,
                      color: colors.muted,
                    ),
                    const SizedBox(width: IslandMetrics.space3),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 70),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IslandTypography.micro.tint(colors.muted),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: IslandMetrics.iconSM,
                      color: colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TranslationTargetMenu extends StatelessWidget {
  const _TranslationTargetMenu({
    required this.target,
    required this.onSelected,
  });

  final String target;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Container(
      width: 150,
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.all(IslandMetrics.space4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(IslandMetrics.radiusPanel),
        border: Border.all(color: colors.stroke),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final language in translateLanguages)
            _TranslationTargetEntry(
              label: language.label,
              selected: language.code == target,
              onTap: () => onSelected(language.code),
            ),
        ],
      ),
    );
  }
}

class _TranslationTargetEntry extends StatelessWidget {
  const _TranslationTargetEntry({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return InkWell(
      borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: IslandMetrics.space6,
          vertical: IslandMetrics.space4,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IslandTypography.micro.copyWith(
                  color: selected ? colors.accent : colors.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: IslandMetrics.iconSM,
                color: colors.accent,
              ),
          ],
        ),
      ),
    );
  }
}

class _MailDetailView extends StatelessWidget {
  const _MailDetailView({
    required this.controller,
    required this.detail,
    required this.target,
    required this.provider,
    required this.onTargetChanged,
  });

  final MailController controller;
  final MailDetail detail;
  final String target;
  final String provider;
  final ValueChanged<String> onTargetChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    final account = controller.accountFor(detail.summary.accountId);
    final hasTranslation = controller.hasTranslationFor(target, provider);
    final showTranslation = controller.showTranslation && hasTranslation;
    final body = showTranslation ? controller.translation : detail.text;
    final openWebmail = account != null && account.webmailUrl.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _IconTap(
              icon: Icons.arrow_back_rounded,
              tooltip: '返回收件箱',
              onTap: controller.closeDetail,
            ),
            const SizedBox(width: IslandMetrics.space4),
            Expanded(
              child: Text(
                detail.summary.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IslandTypography.subhead.tint(colors.text),
              ),
            ),
            if (detail.summary.hasAttachments)
              Icon(
                Icons.attach_file_rounded,
                size: IslandMetrics.iconXS,
                color: colors.muted,
              ),
            _IconTap(
              icon: Icons.translate_rounded,
              tooltip: controller.translating
                  ? '取消翻译'
                  : (hasTranslation
                        ? (showTranslation ? '显示原文' : '显示译文')
                        : '翻译为${translateLanguageLabel(target)}'),
              busy: controller.translating,
              onTap: () => unawaited(
                controller.translate(to: target, provider: provider),
              ),
              onBusyTap: controller.cancelTranslation,
            ),
            if (openWebmail)
              _IconTap(
                icon: Icons.open_in_new_rounded,
                tooltip: '在网页邮箱打开',
                onTap: () => unawaited(controller.openWebmail(account)),
              ),
          ],
        ),
        const SizedBox(height: IslandMetrics.space2),
        Row(
          children: [
            Expanded(
              child: Text(
                '${detail.summary.from} · ${account?.displayName ?? detail.summary.fromAddress} · ${detail.summary.timeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IslandTypography.micro.tint(colors.muted),
              ),
            ),
            const SizedBox(width: IslandMetrics.space4),
            _TranslationTargetButton(
              target: target,
              onChanged: onTargetChanged,
            ),
          ],
        ),
        if (controller.translating)
          Padding(
            padding: const EdgeInsets.only(top: IslandMetrics.space2),
            child: Row(
              children: [
                Icon(
                  Icons.sync_rounded,
                  size: IslandMetrics.iconXS,
                  color: colors.muted,
                ),
                const SizedBox(width: IslandMetrics.space4),
                Expanded(
                  child: Text(
                    '正在翻译，再次点击翻译按钮可取消',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.micro.tint(colors.muted),
                  ),
                ),
              ],
            ),
          )
        else if (controller.translationError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: IslandMetrics.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: IslandMetrics.iconXS,
                  color: colors.warning,
                ),
                const SizedBox(width: IslandMetrics.space4),
                Expanded(
                  child: Text(
                    controller.translationError,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IslandTypography.micro.tint(colors.warning),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: IslandMetrics.space4),
        Expanded(
          child: RepaintBoundary(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(
                right: IslandMetrics.space6,
                bottom: IslandMetrics.space6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showTranslation)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: IslandMetrics.space4,
                      ),
                      child: Text(
                        '译文 · ${translateLanguageLabel(target)}',
                        style: IslandTypography.microStrong.tint(colors.accent),
                      ),
                    ),
                  Text(
                    body.isEmpty ? '（这封邮件没有正文）' : body,
                    style: IslandTypography.body
                        .tint(colors.text)
                        .copyWith(height: 1.45),
                  ),
                  if (detail.truncated) ...[
                    const SizedBox(height: IslandMetrics.space6),
                    Text(
                      '正文过长，已截断',
                      style: IslandTypography.micro.tint(colors.muted),
                    ),
                  ],
                  if (detail.links.isNotEmpty) ...[
                    const SizedBox(height: IslandMetrics.space8),
                    Divider(height: 1, color: colors.divider),
                    const SizedBox(height: IslandMetrics.space4),
                    Text(
                      '邮件中的链接',
                      style: IslandTypography.microStrong.tint(colors.muted),
                    ),
                    for (final link in detail.links.take(3))
                      _MailLinkRow(
                        link: link,
                        onTap: () => unawaited(controller.openLink(link.url)),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MailLinkRow extends StatelessWidget {
  const _MailLinkRow({required this.link, required this.onTap});

  final MailLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Tooltip(
      message: link.url,
      waitDuration: IslandMotion.tooltipDelay,
      child: InkWell(
        borderRadius: BorderRadius.circular(IslandMetrics.radiusTag),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: IslandMetrics.space3),
          child: Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: IslandMetrics.iconXS,
                color: colors.accent,
              ),
              const SizedBox(width: IslandMetrics.space4),
              Expanded(
                child: Text(
                  link.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IslandTypography.micro.tint(colors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
    this.onBusyTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool busy;
  final VoidCallback? onBusyTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.islandColors;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        waitDuration: IslandMotion.tooltipDelay,
        child: InkWell(
          borderRadius: BorderRadius.circular(IslandMetrics.radiusChip),
          onTap: busy ? onBusyTap : onTap,
          child: SizedBox(
            width: IslandMetrics.hitTargetMin,
            height: IslandMetrics.hitTargetMin,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: IslandMetrics.iconSM,
                      height: IslandMetrics.iconSM,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: colors.accent,
                      ),
                    )
                  : Icon(icon, size: IslandMetrics.iconSM, color: colors.muted),
            ),
          ),
        ),
      ),
    );
  }
}
