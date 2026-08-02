import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../../models/user_action.dart';
import '../../../services/emoji_handler.dart';
import '../../../services/discourse_cache_manager.dart';
import '../../../widgets/common/text/relative_time_text.dart';
import '../../../widgets/post/post_boost/boost_content.dart';
import '../../../l10n/s.dart';
import '../../topic_detail_page/topic_detail_page.dart';

/// 用户主页各 tab 列表的 item builder(纯展示)与动作类型映射函数。
///
/// 从 _UserProfilePageState 抽出,无 state/ref 依赖。
class UserProfileItems {
  UserProfileItems._();

  /// 获取 emoji 图片 URL（未加载完成时返回空字符串，由 errorBuilder 处理）
  static String getEmojiUrl(String emojiName) {
    return EmojiHandler().getEmojiUrl(emojiName);
  }

  static Widget boostItem(BuildContext context, UserBoost boost) {
    final theme = Theme.of(context);
    final boostText = BoostContentParser.parse(boost.cooked).displayText;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TopicDetailPage(
              topicId: boost.topicId,
              scrollToPostNumber: boost.postNumber,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：Boost 内容和时间
              Row(
                children: [
                  Icon(
                    Symbols.rocket_launch_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      boostText.isNotEmpty ? boostText : context.l10n.userProfile_boosted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (boost.createdAt != null) ...[
                    const SizedBox(width: 8),
                    RelativeTimeText(
                      dateTime: boost.createdAt,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // 话题标题
              if (boost.topicTitle != null && boost.topicTitle!.isNotEmpty)
                Text(
                  boost.topicTitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),

              // 帖子内容摘要
              if (boost.excerpt != null && boost.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  boost.excerpt!.replaceAll(RegExp(r'<[^>]*>'), ''),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget solvedItem(BuildContext context, SolvedPost post) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TopicDetailPage(
              topicId: post.topicId,
              scrollToPostNumber: post.postNumber,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：已解决标记和时间
              Row(
                children: [
                  Icon(
                    Symbols.check_circle_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.userProfile_solvedLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (post.createdAt != null)
                    RelativeTimeText(
                      dateTime: post.createdAt,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 话题标题
              if (post.topicTitle != null && post.topicTitle!.isNotEmpty)
                Text(
                  post.topicTitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),

              // 被采纳回答摘要
              if (post.excerpt != null && post.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  post.excerpt!.replaceAll(RegExp(r'<[^>]*>'), ''),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget actionItem(BuildContext context, UserAction action) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TopicDetailPage(
              topicId: action.topicId,
              scrollToPostNumber: action.postNumber,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：动作类型和时间
              Row(
                children: [
                  Icon(
                    actionIcon(action.actionType),
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    actionLabel(action.actionType),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (action.actingAt != null)
                    RelativeTimeText(
                      dateTime: action.actingAt,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 标题
              Text(
                action.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),

              // 摘要
              if (action.excerpt != null && action.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  action.excerpt!.replaceAll(RegExp(r'<[^>]*>'), ''),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget reactionItem(BuildContext context, UserReaction reaction) {
    final theme = Theme.of(context);
    final emojiUrl = reaction.reactionValue != null
        ? getEmojiUrl(reaction.reactionValue!)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TopicDetailPage(
              topicId: reaction.topicId,
              scrollToPostNumber: reaction.postNumber,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：回应 emoji 和时间
              Row(
                children: [
                  if (emojiUrl != null)
                    Image(
                      image: emojiImageProvider(emojiUrl),
                      width: 20,
                      height: 20,
                      errorBuilder: (_, _, _) => const Icon(Symbols.emoji_emotions_rounded, size: 20),
                    )
                  else
                    const Icon(Symbols.emoji_emotions_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.userProfile_reacted,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (reaction.createdAt != null)
                    RelativeTimeText(
                      dateTime: reaction.createdAt,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 话题标题
              if (reaction.topicTitle != null && reaction.topicTitle!.isNotEmpty)
                Text(
                  reaction.topicTitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),

              // 帖子内容摘要
              if (reaction.excerpt != null && reaction.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  reaction.excerpt!.replaceAll(RegExp(r'<[^>]*>'), ''),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static IconData actionIcon(int? type) {
    switch (type) {
      case UserActionType.like:
        return Symbols.favorite_rounded;
      case UserActionType.wasLiked:
        return Symbols.favorite_border_rounded;
      case UserActionType.newTopic:
        return Symbols.article_rounded;
      case UserActionType.reply:
        return Symbols.chat_bubble_rounded;
      default:
        return Symbols.history_rounded;
    }
  }

  static String actionLabel(int? type) {
    switch (type) {
      case UserActionType.like:
        return S.current.userProfile_actionLike;
      case UserActionType.wasLiked:
        return S.current.userProfile_actionLiked;
      case UserActionType.newTopic:
        return S.current.userProfile_actionCreatedTopic;
      case UserActionType.reply:
        return S.current.userProfile_actionReplied;
      default:
        return S.current.userProfile_actionDefault;
    }
  }
}
