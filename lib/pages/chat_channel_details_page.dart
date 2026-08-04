import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../l10n/s.dart';
import '../models/chat/chat_channel.dart';
import '../models/chat/chat_message.dart';
import '../providers/chat/chat_channel_list_provider.dart';
import '../providers/core_providers.dart';
import '../services/app_error_handler.dart';
import '../services/toast_service.dart';
import '../widgets/chat/chat_channel_icon.dart';
import '../widgets/common/visual/smart_avatar.dart';
import 'user_profile_page/user_profile_page.dart';

/// 频道详情与当前用户的频道偏好设置。
class ChatChannelDetailsPage extends ConsumerStatefulWidget {
  const ChatChannelDetailsPage({
    super.key,
    required this.channel,
    this.onChannelChanged,
  });

  final ChatChannel channel;
  final ValueChanged<ChatChannel>? onChannelChanged;

  @override
  ConsumerState<ChatChannelDetailsPage> createState() =>
      _ChatChannelDetailsPageState();
}

class _ChatChannelDetailsPageState
    extends ConsumerState<ChatChannelDetailsPage> {
  late ChatChannel _channel;
  bool _updatingStarred = false;
  bool _updatingMuted = false;
  bool _updatingNotificationLevel = false;
  bool _updatingThreading = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
  }

  ChatChannelMembership get _membership =>
      _channel.currentUserMembership ??
      const ChatChannelMembership(following: true, muted: false);

  void _applyChannel(ChatChannel channel) {
    setState(() => _channel = channel);
    ref.read(chatChannelListProvider.notifier).upsertChannel(channel);
    widget.onChannelChanged?.call(channel);
  }

  Future<void> _toggleStarred() async {
    if (_updatingStarred) return;
    final target = !_channel.isStarred;
    setState(() => _updatingStarred = true);
    try {
      final membership = await ref
          .read(discourseServiceProvider)
          .setChatChannelStarred(_channel.id, starred: target);
      if (!mounted) return;
      _applyChannel(_channel.copyWith(currentUserMembership: membership));
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_channelSettingsUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingStarred = false);
    }
  }

  Future<void> _setMuted(bool muted) async {
    if (_updatingMuted) return;
    setState(() => _updatingMuted = true);
    try {
      final membership = await ref
          .read(discourseServiceProvider)
          .updateChatChannelNotificationSettings(_channel.id, muted: muted);
      if (!mounted) return;
      _applyChannel(_channel.copyWith(currentUserMembership: membership));
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_channelSettingsUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingMuted = false);
    }
  }

  Future<void> _setNotificationLevel(ChatChannelNotificationLevel level) async {
    if (_updatingNotificationLevel || level == _membership.notificationLevel) {
      return;
    }
    setState(() => _updatingNotificationLevel = true);
    try {
      final membership = await ref
          .read(discourseServiceProvider)
          .updateChatChannelNotificationSettings(
            _channel.id,
            notificationLevel: level,
          );
      if (!mounted) return;
      _applyChannel(_channel.copyWith(currentUserMembership: membership));
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_channelSettingsUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingNotificationLevel = false);
    }
  }

  Future<void> _setThreadingEnabled(bool enabled) async {
    if (_updatingThreading) return;
    setState(() => _updatingThreading = true);
    try {
      final updated = await ref
          .read(discourseServiceProvider)
          .setChatChannelThreadingEnabled(_channel.id, enabled: enabled);
      if (!mounted) return;
      _applyChannel(
        _channel.copyWith(
          threadingEnabled: updated.threadingEnabled,
          currentUserMembership:
              updated.currentUserMembership ?? _channel.currentUserMembership,
        ),
      );
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_channelSettingsUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingThreading = false);
    }
  }

  Future<void> _confirmLeave() async {
    if (_leaving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _channel.isDirectMessage
              ? dialogContext.l10n.chat_deleteDirectMessage
              : dialogContext.l10n.chat_leaveChannel,
        ),
        content: Text(
          _channel.isDirectMessage
              ? dialogContext.l10n.chat_deleteDirectMessageConfirm(
                  _channel.title,
                )
              : dialogContext.l10n.chat_leaveChannelConfirm(_channel.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: Text(
              _channel.isDirectMessage
                  ? dialogContext.l10n.chat_deleteDirectMessage
                  : dialogContext.l10n.chat_leaveChannel,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);
    try {
      await ref.read(discourseServiceProvider).leaveChatChannel(_channel.id);
      ref.read(chatChannelListProvider.notifier).removeChannel(_channel.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(
          _channel.isDirectMessage
              ? context.l10n.chat_deleteDirectMessageFailed
              : context.l10n.chat_leaveChannelFailed,
        );
        setState(() => _leaving = false);
      }
    }
  }

  void _openMembers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatChannelMembersPage(channel: _channel),
      ),
    );
  }

  String _notificationLevelLabel(
    BuildContext context,
    ChatChannelNotificationLevel level,
  ) {
    return switch (level) {
      ChatChannelNotificationLevel.never => context.l10n.chat_notificationNever,
      ChatChannelNotificationLevel.mention =>
        context.l10n.chat_notificationMentions,
      ChatChannelNotificationLevel.always => context.l10n.chat_notificationAll,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ChatChannelIcon(channel: _channel, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _channel.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: _channel.isStarred
                  ? context.l10n.chat_unstarChannel
                  : context.l10n.chat_starChannel,
              onPressed: _updatingStarred ? null : _toggleStarred,
              icon: _updatingStarred
                  ? const SizedBox.square(
                      dimension: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Symbols.star_rounded,
                      fill: _channel.isStarred ? 1 : 0,
                    ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _SectionTitle(label: context.l10n.chat_channelTitleSection),
          const SizedBox(height: 10),
          SegmentedCardGroup(
            children: [
              ListTile(
                minTileHeight: 64,
                leading: const Icon(Symbols.title_rounded),
                title: Text(
                  _channel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                key: const ValueKey('chat-channel-members-entry'),
                minTileHeight: 64,
                leading: const Icon(Symbols.group_rounded),
                title: Text(context.l10n.chat_membersTitle),
                subtitle: _channel.membershipsCount > 0
                    ? Text(
                        context.l10n.chat_channelMembers(
                          _channel.membershipsCount,
                        ),
                      )
                    : null,
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: _openMembers,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle(label: context.l10n.chat_channelSettingsSection),
          const SizedBox(height: 10),
          SegmentedCardGroup(
            children: [
              SwitchListTile(
                key: const ValueKey('chat-channel-muted-switch'),
                secondary: const Icon(Symbols.notifications_off_rounded),
                title: Text(context.l10n.chat_channelMute),
                value: _membership.muted,
                onChanged: _updatingMuted ? null : _setMuted,
              ),
              ListTile(
                minTileHeight: 72,
                leading: const Icon(Symbols.notifications_rounded),
                title: Text(context.l10n.chat_pushNotifications),
                trailing: _updatingNotificationLevel
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<ChatChannelNotificationLevel>(
                        key: const ValueKey('chat-channel-notification-level'),
                        initialValue: _membership.notificationLevel,
                        onSelected: _setNotificationLevel,
                        itemBuilder: (context) => [
                          for (final level
                              in ChatChannelNotificationLevel.values)
                            PopupMenuItem(
                              value: level,
                              child: Text(
                                _notificationLevelLabel(context, level),
                              ),
                            ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _notificationLevelLabel(
                                  context,
                                  _membership.notificationLevel,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Symbols.keyboard_arrow_down_rounded,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              SwitchListTile(
                key: const ValueKey('chat-channel-threading-switch'),
                secondary: const Icon(Symbols.forum_rounded),
                title: Text(context.l10n.chat_enableThreads),
                subtitle: Text(context.l10n.chat_enableThreadsDescription),
                value: _channel.threadingEnabled,
                onChanged: _updatingThreading ? null : _setThreadingEnabled,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionTitle(label: context.l10n.chat_channelInfoSection),
          const SizedBox(height: 10),
          SegmentedCardGroup(
            children: [
              ListTile(
                minTileHeight: 64,
                leading: const Icon(Symbols.history_rounded),
                title: Text(context.l10n.chat_channelHistory),
                trailing: Text(
                  context.l10n.chat_channelHistoryForever,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('chat-channel-leave-button'),
              onPressed: _leaving ? null : _confirmLeave,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                disabledBackgroundColor: theme.colorScheme.errorContainer,
                disabledForegroundColor: theme.colorScheme.onErrorContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              icon: _leaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.logout_rounded),
              label: Text(
                _channel.isDirectMessage
                    ? context.l10n.chat_deleteDirectMessage
                    : context.l10n.chat_leaveChannel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class ChatChannelMembersPage extends ConsumerWidget {
  const ChatChannelMembersPage({super.key, required this.channel});

  final ChatChannel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = [...channel.directMessageUsers];
    final currentUser = ref.watch(currentUserProvider).value;
    if (currentUser != null &&
        !users.any(
          (user) =>
              user.id == currentUser.id ||
              user.username.toLowerCase() == currentUser.username.toLowerCase(),
        )) {
      users.insert(
        0,
        ChatMessageUser(
          id: currentUser.id,
          username: currentUser.username,
          name: currentUser.name ?? '',
          avatarTemplate: currentUser.avatarTemplate ?? '',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.chat_membersTitle)),
      body: users.isEmpty
          ? Center(child: Text(context.l10n.chat_membersEmpty))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: users.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final user = users[index];
                final displayName = user.displayName;
                return ListTile(
                  key: ValueKey('chat-channel-member-${user.username}'),
                  leading: SmartAvatar(
                    imageUrl: user.avatarTemplate.isEmpty
                        ? null
                        : user.getAvatarUrl(size: 96),
                    radius: 22,
                    fallbackText: displayName,
                  ),
                  title: Text(displayName),
                  subtitle: user.username.isEmpty
                      ? null
                      : Text('@${user.username}'),
                  onTap: user.username.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            settings: RouteSettings(
                              name: '/u/${user.username}',
                              arguments: user.username,
                            ),
                            builder: (_) =>
                                UserProfilePage(username: user.username),
                          ),
                        ),
                );
              },
            ),
    );
  }
}
