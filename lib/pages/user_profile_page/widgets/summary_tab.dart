import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../../models/user.dart';
import '../../../l10n/s.dart';
import '../../../widgets/user/user_profile_skeleton.dart';
import 'summary_items.dart';

/// 用户主页「总结」tab 的纯展示组件。
///
/// 数据(UserSummary)随用户信息一起从 [UserProfilePage] 加载,本组件无任何
/// state / 网络依赖,只渲染热门话题/回复/链接/用户/类别/徽章等小节。
class SummaryTab extends StatelessWidget {
  const SummaryTab({super.key, required this.summary});

  final UserSummary? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null) {
      return const UserActionListSkeleton();
    }

    final theme = Theme.of(context);
    final s = summary!;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 热门话题
        if (s.topics.isNotEmpty) ...[
          SummaryItems.sectionHeader(theme, Symbols.article_rounded, context.l10n.userProfile_topTopics),
          const SizedBox(height: 8),
          ...s.topics.map((topic) => SummaryItems.summaryTopicItem(context, theme, topic)),
          const SizedBox(height: 20),
        ],

        // 热门回复
        if (s.replies.isNotEmpty) ...[
          SummaryItems.sectionHeader(theme, Symbols.chat_bubble_rounded, context.l10n.userProfile_topReplies),
          const SizedBox(height: 8),
          ...s.replies.map((reply) => SummaryItems.summaryReplyItem(context, theme, reply)),
          const SizedBox(height: 20),
        ],

        // 热门链接
        if (s.links.isNotEmpty) ...[
          SummaryItems.sectionHeader(theme, Symbols.link_rounded, context.l10n.userProfile_topLinks),
          const SizedBox(height: 8),
          ...s.links.map((link) => SummaryItems.summaryLinkItem(context, theme, link)),
          const SizedBox(height: 20),
        ],

        // 最多回复至
        if (s.mostRepliedToUsers.isNotEmpty) ...[
          SummaryItems.sectionHeader(theme, Symbols.reply_rounded, context.l10n.userProfile_mostRepliedTo),
          const SizedBox(height: 8),
          SummaryItems.userChips(context, theme, s.mostRepliedToUsers),
          const SizedBox(height: 20),
        ],

        // 被谁赞的最多
        if (s.mostLikedByUsers.isNotEmpty) ...[
          SummaryItems.sectionHeader(theme, Symbols.favorite_rounded, context.l10n.userProfile_mostLikedBy),
          const SizedBox(height: 8),
          SummaryItems.userChips(context, theme, s.mostLikedByUsers),
          const SizedBox(height: 20),
        ],

        // 赞最多
        if (s.mostLikedUsers.isNotEmpty) ...[
          SummaryItems.sectionHeader(theme, Symbols.thumb_up_rounded, context.l10n.userProfile_mostLiked),
          const SizedBox(height: 8),
          SummaryItems.userChips(context, theme, s.mostLikedUsers),
          const SizedBox(height: 20),
        ],

        // 热门类别
        if (s.topCategories.isNotEmpty) ...[
          SummaryItems.sectionHeader(theme, Symbols.category_rounded, context.l10n.userProfile_topCategories),
          const SizedBox(height: 8),
          ...s.topCategories.map((cat) => SummaryItems.summaryCategoryItem(context, theme, cat)),
          const SizedBox(height: 20),
        ],

        // 热门徽章
        if (s.badges.isNotEmpty) ...[
          SummaryItems.sectionHeader(theme, Symbols.military_tech_rounded, context.l10n.userProfile_topBadges),
          const SizedBox(height: 8),
          SummaryItems.badgeChips(context, theme, s.badges),
          const SizedBox(height: 20),
        ],

        // 若所有列表都为空
        if (s.topics.isEmpty &&
            s.replies.isEmpty &&
            s.links.isEmpty &&
            s.mostRepliedToUsers.isEmpty &&
            s.mostLikedUsers.isEmpty &&
            s.mostLikedUsers.isEmpty &&
            s.topCategories.isEmpty &&
            s.badges.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Column(
                children: [
                  Icon(Symbols.summarize_rounded, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(context.l10n.userProfile_noSummary, style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
