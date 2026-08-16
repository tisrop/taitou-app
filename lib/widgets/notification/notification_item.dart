import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:app_icons/app_icons.dart';
import 'package:jovial_svg/jovial_svg.dart';
import '../../models/notification.dart';
import '../common/text/emoji_text.dart';

// discourse-follow 插件的自定义 SVG 图标
const _followNewFollowerSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 33 30">'
    '<path d="M23.1 29.2h1.5c.8 0 1.5-.7 1.5-1.5v-5.3h5.1c.8 0 1.5-.7 1.5-1.5v-1.5c0-.8-.7-1.5-1.5-1.5h-5.1v-5c0-.8-.7-1.5-1.5-1.5h-1.5c-.8 0-1.5.7-1.5 1.5v5h-4.7c-.8 0-1.5.7-1.5 1.5v1.5c0 .8.7 1.5 1.5 1.5h4.7v5.3c0 .8.6 1.5 1.5 1.5zM18.4 29.1v-3.9c0-.1-.1-.1-.1-.1h-2.5c-2.7 0-3.7-2.1-3.7-4V18c0-.2-.2-.2-.2-.2-1.3 0-2.6-.4-4-1h-.5c-4.1 0-7.4 3.3-7.4 7.4v1.9c0 1.7 1.4 3.1 3.1 3.1h15.2c0 .1.1 0 .1-.1z"/>'
    '<circle cx="12.5" cy="7.1" r="7.1"/>'
    '</svg>';

const _followNewTopicSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 33 30">'
    '<path d="M32.6 21.6c-.6-.7-1.8-1.7-1.8-5 0-2.4-1.6-4.3-3.8-4.9-.3-1.6-2.4-1.6-2.7 0-2.2.6-3.9 2.5-3.9 4.9 0 3.3-1.2 4.3-1.8 5-.2.2-.3.5-.3.7 0 .5.4 1 1 1h12.5c.9 0 1.4-1.1.8-1.7zM20.1 29.2h-17c-1.7 0-3.1-1.4-3.1-3.1v-1.9c0-4.3 3.7-7.7 8-7.4 2.6 1.3 6 1.4 8.6.1 0 0 .1-.1.1 0 0 2.4-.5 2.8-1.2 3.5-2 2.1-.7 5.9 2.4 5.7h.8c.1 0 .1.3.1.4.1 1.1.6 1.8 1.3 2.7M25.6 29.2c1.7 0 3-1.3 3-2.9h-6c0 1.5 1.3 2.9 3 2.9zM12.3 14.2c3.9 0 7.1-3.2 7.1-7.1-.3-9.5-14-9.5-14.3 0 0 3.9 3.2 7.1 7.2 7.1z"/>'
    '</svg>';

const _followNewReplySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 33 30">'
    '<path d="M15.2 29.3H3.1c-1.7 0-3.1-1.4-3.1-3.1v-1.8C0 20.3 3.3 17 7.4 17h.5c1.3.6 2.8 1 4.4 1 .2 0 .6 0 1.2-.2 0 0 .3 0 .1.3-.8 1.5-1.1 3.2-1.1 4.8 0 2.5 1 4.7 2.7 6.3 0 0 .2.1 0 .1zM12.3 14.3c4 0 7.2-3.2 7.2-7.2S16.3 0 12.3 0 5.1 3.2 5.1 7.2s3.2 7.1 7.2 7.1zM32.4 17.1 26 11.6c-.6-.5-1.5-.1-1.5.7V15.1c-4.8.5-8.4 2.2-8.4 7.6 0 2.6 1.5 5.1 3.2 6.4.5.4 1.3-.1 1.1-.8-1.4-5 .1-7 4.1-7.5v2.4c0 .7.9 1.1 1.5.7l6.4-5.5c.4-.3.4-1 0-1.3z"/>'
    '</svg>';

/// 通知列表项 widget，快捷面板和历史列表页面共用
class NotificationItem extends StatelessWidget {
  final DiscourseNotification notification;
  final VoidCallback onTap;

  const NotificationItem({
    super.key,
    required this.notification,
    required this.onTap,
  });

  IconData _getNotificationIcon() {
    switch (notification.notificationType) {
      case NotificationType.mentioned:
        return Symbols.alternate_email_rounded;
      case NotificationType.replied:
        return Symbols.reply_rounded;
      case NotificationType.quoted:
        return Symbols.format_quote_rounded;
      case NotificationType.liked:
      case NotificationType.likedConsolidated:
        return Symbols.favorite_rounded;
      case NotificationType.reaction:
        return Symbols.thumb_up_rounded;
      case NotificationType.privateMessage:
      case NotificationType.invitedToPrivateMessage:
        return Symbols.mail_rounded;
      case NotificationType.posted:
        return Symbols.post_add_rounded;
      case NotificationType.grantedBadge:
        return Symbols.military_tech_rounded;
      case NotificationType.linked:
        return Symbols.link_rounded;
      case NotificationType.bookmarkReminder:
        return Symbols.bookmark_rounded;
      case NotificationType.groupMentioned:
        return Symbols.group_rounded;
      case NotificationType.watchingFirstPost:
        return Symbols.visibility_rounded;
      case NotificationType.following:
      case NotificationType.followingCreatedTopic:
      case NotificationType.followingReplied:
        return Symbols.person_add_rounded;
      case NotificationType.watchingCategoryOrTag:
        return Symbols.label_rounded;
      case NotificationType.newFeatures:
        return Symbols.new_releases_rounded;
      case NotificationType.adminProblems:
        return Symbols.warning_rounded;
      case NotificationType.linkedConsolidated:
        return Symbols.link_rounded;
      case NotificationType.chatWatchedThread:
        return Symbols.chat_bubble_rounded;
      case NotificationType.invitedToTopic:
        return Symbols.mail_rounded;
      case NotificationType.inviteeAccepted:
        return Symbols.check_circle_rounded;
      case NotificationType.movedPost:
        return Symbols.drive_file_move_rounded;
      case NotificationType.topicReminder:
        return Symbols.alarm_rounded;
      case NotificationType.eventReminder:
      case NotificationType.eventInvitation:
        return Symbols.event_rounded;
      case NotificationType.chatMention:
      case NotificationType.chatMessage:
      case NotificationType.chatInvitation:
      case NotificationType.chatGroupMention:
      case NotificationType.chatQuotedPost:
        return Symbols.chat_rounded;
      case NotificationType.boost:
        return Symbols.rocket_launch_rounded;
      case NotificationType.assignedTopic:
        return Symbols.assignment_rounded;
      case NotificationType.questionAnswerUserCommented:
        return Symbols.question_answer_rounded;
      case NotificationType.circlesActivity:
        return Symbols.groups_rounded;
      default:
        return Symbols.notifications_rounded;
    }
  }

  /// 与 Discourse 网页通知列表保持一致的 Font Awesome 实心图标。
  FaIconData? _getDiscourseNotificationIcon() {
    switch (notification.notificationType) {
      case NotificationType.replied:
        return FontAwesomeIcons.reply;
      case NotificationType.privateMessage:
      case NotificationType.invitedToPrivateMessage:
      case NotificationType.invitedToTopic:
        return FontAwesomeIcons.solidEnvelope;
      case NotificationType.grantedBadge:
        return FontAwesomeIcons.certificate;
      case NotificationType.chatWatchedThread:
      case NotificationType.chatMention:
      case NotificationType.chatMessage:
      case NotificationType.chatInvitation:
      case NotificationType.chatGroupMention:
      case NotificationType.chatQuotedPost:
        return FontAwesomeIcons.solidComment;
      default:
        return null;
    }
  }

  /// 构建通知类型图标，follow 类型使用 Discourse 插件 SVG。
  Widget _buildNotificationIcon(Color color) {
    String? svgData;
    switch (notification.notificationType) {
      case NotificationType.following:
        svgData = _followNewFollowerSvg;
        break;
      case NotificationType.followingCreatedTopic:
        svgData = _followNewTopicSvg;
        break;
      case NotificationType.followingReplied:
        svgData = _followNewReplySvg;
        break;
      default:
        break;
    }
    if (svgData != null) {
      final si = ScalableImage.fromSvgString(
        svgData,
        warnF: (_) {},
      ).modifyTint(newTintColor: color, newTintMode: BlendMode.srcIn);
      return SizedBox(
        width: 24,
        height: 24,
        child: ScalableImageWidget(si: si),
      );
    }
    final discourseIcon = _getDiscourseNotificationIcon();
    if (discourseIcon != null) {
      return FaIcon(discourseIcon, size: 24, color: color);
    }
    return Icon(_getNotificationIcon(), size: 25, color: color);
  }

  bool get _usesStandaloneTitle {
    switch (notification.notificationType) {
      case NotificationType.grantedBadge:
      case NotificationType.inviteeAccepted:
      case NotificationType.following:
      case NotificationType.likedConsolidated:
      case NotificationType.linkedConsolidated:
      case NotificationType.groupMessageSummary:
      case NotificationType.membershipRequestAccepted:
      case NotificationType.membershipRequestConsolidated:
      case NotificationType.newFeatures:
      case NotificationType.adminProblems:
        return true;
      default:
        return false;
    }
  }

  String get _primaryText {
    if (_usesStandaloneTitle) return notification.title;
    final username = notification.username?.trim() ?? '';
    return username.isEmpty ? notification.title : username;
  }

  String? get _secondaryText {
    if (_usesStandaloneTitle) return null;

    final chatContextDescription = notification.chatContextDescription;
    if (chatContextDescription != null) return chatContextDescription;

    final username = notification.username?.trim() ?? '';
    if (username.isEmpty) {
      final description = notification.description.trim();
      return description == notification.title ? null : description;
    }

    final title = notification.title.trim();
    if (title.isNotEmpty && title != notification.notificationType.label) {
      return title;
    }

    final description = notification.description.trim();
    return description.isEmpty ? null : description;
  }

  String _formatDate(BuildContext context) {
    final date = notification.createdAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    return date.year == DateTime.now().year
        ? localizations.formatShortMonthDay(date)
        : localizations.formatMediumDate(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
    final primaryStyle = theme.textTheme.titleMedium?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: _usesStandaloneTitle ? FontWeight.w400 : FontWeight.w700,
      height: 1.25,
    );
    final secondaryStyle = theme.textTheme.titleMedium?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w400,
      height: 1.3,
    );
    final secondaryText = _secondaryText;
    final backgroundColor = notification.read
        ? colorScheme.surface
        : Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.12),
            colorScheme.surface,
          );

    return Material(
      key: ValueKey('notification-${notification.id}'),
      color: backgroundColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                width: 0.75,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildNotificationIcon(iconColor),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: EmojiText.buildEmojiSpans(
                          context,
                          _primaryText,
                          primaryStyle ?? const TextStyle(),
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: primaryStyle,
                    ),
                    if (secondaryText != null) ...[
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: EmojiText.buildEmojiSpans(
                            context,
                            secondaryText,
                            secondaryStyle ?? const TextStyle(),
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: secondaryStyle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _formatDate(context),
                textAlign: TextAlign.end,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
