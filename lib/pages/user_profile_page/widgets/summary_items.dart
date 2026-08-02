import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/user.dart';
import '../../../models/badge.dart' as badge_model;
import '../../../widgets/common/visual/smart_avatar.dart';
import '../../../widgets/badge/badge_ui_utils.dart';
import '../../../l10n/s.dart';
import '../../topic_detail_page/topic_detail_page.dart';
import '../../badge_page.dart';
import '../user_profile_page.dart';

/// 用户主页「总结」tab 内的纯展示 item builder 集合。
///
/// 这些方法只接 model + theme,导航用全局 Navigator,无任何 state/ref 依赖,
/// 从 _UserProfilePageState 抽出以降低主文件体积。
class SummaryItems {
  SummaryItems._();

  static Widget sectionHeader(ThemeData theme, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  static Widget summaryTopicItem(
    BuildContext context,
    ThemeData theme,
    SummaryTopic topic,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TopicDetailPage(topicId: topic.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  topic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (topic.likeCount > 0) ...[
                const SizedBox(width: 8),
                Icon(Symbols.favorite_rounded, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 2),
                Text(
                  '${topic.likeCount}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget summaryReplyItem(
    BuildContext context,
    ThemeData theme,
    SummaryReply reply,
  ) {
    final topic = reply.topic;
    final targetTopicId = topic?.id ?? reply.topicId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: targetTopicId != null
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TopicDetailPage(
                      topicId: targetTopicId,
                      scrollToPostNumber: reply.postNumber,
                    ),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  topic?.title ?? context.l10n.userProfile_topicHash(targetTopicId.toString()),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (reply.likeCount > 0) ...[
                const SizedBox(width: 8),
                Icon(Symbols.favorite_rounded, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 2),
                Text(
                  '${reply.likeCount}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget summaryLinkItem(
    BuildContext context,
    ThemeData theme,
    SummaryLink link,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (link.topic != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TopicDetailPage(
                  topicId: link.topic!.id,
                  scrollToPostNumber: link.postNumber,
                ),
              ),
            );
          } else {
            launchUrl(Uri.parse(link.url));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Symbols.open_in_new_rounded, size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title ?? link.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (link.topic != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        link.topic!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (link.clicks > 0) ...[
                const SizedBox(width: 8),
                Text(
                  context.l10n.userProfile_linkClicks(link.clicks),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget userChips(
    BuildContext context,
    ThemeData theme,
    List<SummaryUserWithCount> users,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: users.map((user) => InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfilePage(username: user.username),
          ),
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmartAvatar(
                imageUrl: user.getAvatarUrl(size: 48),
                radius: 12,
                fallbackText: user.username,
              ),
              const SizedBox(width: 6),
              Text(
                user.name?.isNotEmpty == true ? user.name! : user.username,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${user.count}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      )).toList(),
    );
  }

  static Widget summaryCategoryItem(
    BuildContext context,
    ThemeData theme,
    SummaryCategory cat,
  ) {
    final color = cat.color != null
        ? Color(int.parse('FF${cat.color}', radix: 16))
        : theme.colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cat.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              context.l10n.userProfile_catTopicCount(cat.topicCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              context.l10n.userProfile_catPostCount(cat.postCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget badgeChips(
    BuildContext context,
    ThemeData theme,
    List<badge_model.Badge> badges,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: badges.map((badge) {
        final badgeType = badge.badgeType;
        final color = BadgeUIUtils.getBadgeColor(context, badgeType);

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BadgePage(badgeId: badge.id),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: BadgeUIUtils.getBadgeGradient(context, badgeType),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(
                  BadgeUIUtils.getBadgeIcon(badgeType),
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  badge.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
