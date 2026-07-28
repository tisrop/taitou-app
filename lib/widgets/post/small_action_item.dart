import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import '../../l10n/s.dart';
import '../../models/topic.dart';
import '../common/relative_time_text.dart';
import '../common/smart_avatar.dart';
import 'post_item/widgets/post_segment_frame.dart';

/// 帖子类型常量
class PostTypes {
  static const int regular = 1;
  static const int moderatorAction = 2;
  static const int smallAction = 3;
  static const int whisper = 4;
}

/// action_code 对应的图标映射
const Map<String, IconData> _actionCodeIcons = {
  'closed.enabled': Symbols.lock_rounded,
  'closed.disabled': Symbols.lock_open_rounded,
  'autoclosed.enabled': Symbols.lock_rounded,
  'autoclosed.disabled': Symbols.lock_open_rounded,
  'archived.enabled': Symbols.folder_rounded,
  'archived.disabled': Symbols.folder_open_rounded,
  'pinned.enabled': Symbols.push_pin_rounded,
  'pinned.disabled': Symbols.push_pin_rounded,
  'pinned_globally.enabled': Symbols.push_pin_rounded,
  'pinned_globally.disabled': Symbols.push_pin_rounded,
  'banner.enabled': Symbols.push_pin_rounded,
  'banner.disabled': Symbols.push_pin_rounded,
  'visible.enabled': Symbols.visibility_rounded,
  'visible.disabled': Symbols.visibility_off_rounded,
  'split_topic': Symbols.call_split_rounded,
  'invited_user': Symbols.person_add_rounded,
  'invited_group': Symbols.group_add_rounded,
  'user_left': Symbols.person_remove_rounded,
  'removed_user': Symbols.person_remove_rounded,
  'removed_group': Symbols.group_remove_rounded,
  'public_topic': Symbols.forum_rounded,
  'open_topic': Symbols.forum_rounded,
  'private_topic': Symbols.mail_rounded,
  'autobumped': Symbols.arrow_upward_rounded,
  'tags_changed': Symbols.label_rounded,
  'category_changed': Symbols.category_rounded,
};

/// action_code 对应的本地化描述
Map<String, String> _getActionCodeDescriptions() {
  final l10n = S.current;
  return {
    'closed.enabled': l10n.smallAction_closedEnabled,
    'closed.disabled': l10n.smallAction_closedDisabled,
    'autoclosed.enabled': l10n.smallAction_autoclosedEnabled,
    'autoclosed.disabled': l10n.smallAction_autoclosedDisabled,
    'archived.enabled': l10n.smallAction_archivedEnabled,
    'archived.disabled': l10n.smallAction_archivedDisabled,
    'pinned.enabled': l10n.smallAction_pinnedEnabled,
    'pinned.disabled': l10n.smallAction_pinnedDisabled,
    'pinned_globally.enabled': l10n.smallAction_pinnedGloballyEnabled,
    'pinned_globally.disabled': l10n.smallAction_pinnedGloballyDisabled,
    'banner.enabled': l10n.smallAction_bannerEnabled,
    'banner.disabled': l10n.smallAction_bannerDisabled,
    'visible.enabled': l10n.smallAction_visibleEnabled,
    'visible.disabled': l10n.smallAction_visibleDisabled,
    'split_topic': l10n.smallAction_splitTopic,
    'invited_user': l10n.smallAction_invitedUser,
    'invited_group': l10n.smallAction_invitedGroup,
    'user_left': l10n.smallAction_userLeft,
    'removed_user': l10n.smallAction_removedUser,
    'removed_group': l10n.smallAction_removedGroup,
    'public_topic': l10n.smallAction_publicTopic,
    'open_topic': l10n.smallAction_openTopic,
    'private_topic': l10n.smallAction_privateTopic,
    'autobumped': l10n.smallAction_autobumped,
    'tags_changed': l10n.smallAction_tagsChanged,
    'category_changed': l10n.smallAction_categoryChanged,
    'forwarded': l10n.smallAction_forwarded,
  };
}

/// 系统操作帖子组件（small_action）
/// 用于显示置顶、关闭、邀请等系统操作
class SmallActionItem extends StatelessWidget {
  final Post post;
  final bool selected;
  final VoidCallback? onTap;

  const SmallActionItem({
    super.key,
    required this.post,
    this.selected = false,
    this.onTap,
  });

  IconData get _icon {
    final code = post.actionCode ?? '';
    return _actionCodeIcons[code] ?? Symbols.info_rounded;
  }

  String get _description {
    final code = post.actionCode ?? '';
    final who = post.actionCodeWho;
    String base = _getActionCodeDescriptions()[code] ?? code;

    // 如果有操作者信息，且描述需要包含操作者
    if (who != null && who.isNotEmpty) {
      if (code == 'invited_user' ||
          code == 'invited_group' ||
          code == 'removed_user' ||
          code == 'removed_group') {
        base = '$base @$who';
      } else if (code == 'user_left') {
        base = '@$who $base';
      }
    }

    return base;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = post.getAvatarUrl(size: 60);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              // 描述和时间
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RelativeTimeText(
                      dateTime: post.createdAt,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 头像
              SmartAvatar(
                imageUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                radius: 14,
                fallbackText: post.username,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
        if (selected)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: buildPostSelectionIndicatorColor(theme),
                ),
                child: const SizedBox(width: 3),
              ),
            ),
          ),
      ],
    );
  }
}
