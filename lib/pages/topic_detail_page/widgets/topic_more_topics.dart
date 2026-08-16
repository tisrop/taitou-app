import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/s.dart';
import '../../../models/topic.dart';
import '../../../providers/preferences_provider.dart';
import '../../../utils/time_utils.dart';
import '../topic_detail_page.dart';

/// 帖子流末尾的推荐区。
///
/// related_topics 来自语义相关能力，suggested_topics 来自 Discourse 的
/// 常规推荐。私信使用另一套 related_messages 协议，因此这里不展示。
class MoreTopicsSection extends ConsumerStatefulWidget {
  const MoreTopicsSection({super.key, required this.detail});

  final TopicDetail detail;

  @override
  ConsumerState<MoreTopicsSection> createState() => _MoreTopicsSectionState();
}

class _MoreTopicsSectionState extends ConsumerState<MoreTopicsSection> {
  bool? _preferRelated;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      preferencesProvider.select((prefs) => prefs.showSuggestedTopics),
    );
    if (!enabled || widget.detail.isPrivateMessage) {
      return const SizedBox.shrink();
    }

    final related = widget.detail.relatedTopics;
    final suggested = widget.detail.suggestedTopics;
    if (related.isEmpty && suggested.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasTabs = related.isNotEmpty && suggested.isNotEmpty;
    final showRelated = related.isNotEmpty && (_preferRelated ?? true);
    final topics = showRelated ? related : suggested;
    final l10n = context.l10n;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        key: const ValueKey('more-topics-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: hasTabs
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TopicGroupChip(
                        key: const ValueKey('more-topics-related-tab'),
                        label: l10n.topicDetail_relatedTopics,
                        icon: Symbols.auto_awesome_rounded,
                        selected: showRelated,
                        onTap: () => setState(() => _preferRelated = true),
                      ),
                      _TopicGroupChip(
                        key: const ValueKey('more-topics-suggested-tab'),
                        label: l10n.topicDetail_suggestedTopics,
                        selected: !showRelated,
                        onTap: () => setState(() => _preferRelated = false),
                      ),
                    ],
                  )
                : _SingleGroupTitle(
                    label: showRelated
                        ? l10n.topicDetail_relatedTopics
                        : l10n.topicDetail_suggestedTopics,
                    showSparkle: showRelated,
                  ),
          ),
          for (final topic in topics)
            _MoreTopicTile(
              key: ValueKey('more-topic-${topic.id}'),
              topic: topic,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TopicDetailPage(
                    topicId: topic.id,
                    initialTitle: topic.title,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SingleGroupTitle extends StatelessWidget {
  const _SingleGroupTitle({required this.label, required this.showSparkle});

  final String label;
  final bool showSparkle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (showSparkle) ...[
          Icon(
            Symbols.auto_awesome_rounded,
            size: 17,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TopicGroupChip extends StatelessWidget {
  const _TopicGroupChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    return Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: selected ? null : onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: foreground),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreTopicTile extends StatelessWidget {
  const _MoreTopicTile({super.key, required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metaColor = theme.colorScheme.onSurfaceVariant;
    final excerpt = topic.excerpt?.trim();
    final replyCount = topic.replyCount > 0
        ? topic.replyCount
        : (topic.postsCount - 1).clamp(0, 999999);
    final activityAt = topic.lastPostedAt ?? topic.createdAt;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              topic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (excerpt != null && excerpt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: metaColor),
              ),
            ],
            if (replyCount > 0 || activityAt != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (replyCount > 0) ...[
                    Icon(
                      Symbols.chat_bubble_rounded,
                      size: 14,
                      color: metaColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$replyCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: metaColor,
                      ),
                    ),
                  ],
                  if (replyCount > 0 && activityAt != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('·', style: TextStyle(color: metaColor)),
                    ),
                  if (activityAt != null)
                    Text(
                      TimeUtils.formatRelativeTime(activityAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: metaColor,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
