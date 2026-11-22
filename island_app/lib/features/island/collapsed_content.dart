import '../../core/settings/settings_controller.dart';
import '../agents/agent_controller.dart';
import '../ime/ime_controller.dart';
import '../mail/mail_controller.dart';
import '../media/media_controller.dart';
import '../messages/messages_controller.dart';
import '../schedule/schedule_controller.dart';
import '../weather/weather_controller.dart';
import 'island_layout.dart';

/// 收集收起态实际会显示的元素，供岛体尺寸与点击命中区共用。
CollapsedContent collapsedContentOf({
  required SettingsController settings,
  required MessagesController messages,
  required MailController mail,
  required WeatherController weather,
  required MediaController media,
  required ImeController ime,
  required ScheduleController schedule,
  required AgentController agents,
  DateTime? now,
}) {
  final config = settings.settings;
  final current = now ?? DateTime.now();
  final runningAgents = config.showAgentIndicator
      ? agents.runningAgentIds.length
      : 0;
  final visibleAgents = runningAgents > 2 ? 2 : runningAgents;
  // 收起态只显示第一封未读邮件的服务商图标，且必须能匹配到账号。
  var hasMailBadge = false;
  for (final item in mail.items) {
    if (!item.unread) continue;
    hasMailBadge = mail.accountFor(item.accountId) != null;
    break;
  }
  return CollapsedContent(
    schedule: config.showScheduleIndicator && schedule.hasPendingOn(current),
    weather: config.showWeather && weather.snapshot != null,
    metricCount: config.islandMetrics.length,
    agentCount: visibleAgents,
    extraAgents: runningAgents - visibleAgents,
    ime: config.showImeIndicator && ime.mode != null,
    wechat: messages.hasWechat,
    qq: messages.hasQq,
    mail: hasMailBadge,
    playing: config.showPlayingIndicator && media.available && media.playing,
  );
}
