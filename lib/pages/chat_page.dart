import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../l10n/s.dart';
import '../models/chat/chat_channel.dart';
import '../navigation/nav_action_bus.dart';
import '../providers/chat/chat_channel_list_provider.dart';
import '../providers/core_providers.dart';
import '../services/app_error_handler.dart';
import '../services/toast_service.dart';
import '../widgets/chat/chat_channel_icon.dart';
import '../widgets/chat/chat_channel_switcher_dialog.dart';
import '../widgets/common/misc/error_view.dart';
import '../widgets/desktop_refresh_indicator.dart';
import 'chat_channel_browser_page.dart';
import 'chat_channel_page.dart';
import 'chat_search_page.dart';

/// 频道列表里的最后消息时间：今天显示时间，近 7 天显示星期，其余显示日期。
String formatChatChannelLastMessageTime(
  BuildContext context,
  DateTime? time, {
  DateTime? now,
}) {
  if (time == null) return '';

  final localTime = time.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final messageDate = DateTime(localTime.year, localTime.month, localTime.day);
  final dayDifference = today.difference(messageDate).inDays;

  if (dayDifference == 0) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(localTime),
      alwaysUse24HourFormat:
          MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false,
    );
  }

  final localeName = Localizations.localeOf(context).toLanguageTag();
  if (dayDifference > 0 && dayDifference < 7) {
    return DateFormat.EEEE(localeName).format(localTime);
  }
  return DateFormat.yMd(localeName).format(localTime);
}

/// 聊天首页：展示当前用户可用的频道（公开频道 + 直接消息）。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, this.isActive = true});

  /// 是否为当前活跃的 tab（嵌入底栏时用于决定是否响应 NavActionBus）
  final bool isActive;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final raw = n.metrics.pixels;
    final progress = raw < 0 ? 0.0 : raw;
    final current = ref.read(navScrollProgressProvider(NavEntryIds.chat));
    final atZero = progress == 0 && current != 0;
    final crossed =
        (progress >= navScrollIconThreshold) !=
        (current >= navScrollIconThreshold);
    if (!atZero && !crossed && (progress - current).abs() < 4.0) return false;
    ref.read(navScrollProgressProvider(NavEntryIds.chat).notifier).state =
        progress;
    return false;
  }

  /// 底栏快捷动作：滚动到顶 / 刷新
  void _onNavAction(NavActionEvent? event) {
    if (event == null) return;
    if (event.targetId != NavEntryIds.chat) return;
    if (!widget.isActive) return;
    switch (event.action) {
      case NavAction.scrollToTop:
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        break;
      case NavAction.refresh:
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        ref.read(chatChannelListProvider.notifier).refresh();
        ref.resetNavScrollProgress(NavEntryIds.chat);
        break;
    }
  }

  Future<void> _onRefresh() async {
    await ref.read(chatChannelListProvider.notifier).refresh();
  }

  Future<void> _startDirectMessage() async {
    final channel = await showChatChannelSwitcher(context: context);
    if (!mounted || channel == null) return;

    await _openChannel(channel);
  }

  Future<void> _browseChannels() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChatChannelBrowserPage()));
  }

  Future<void> _openChannelSwitcher() async {
    final channel = await showChatChannelSwitcher(context: context);
    if (!mounted || channel == null) return;
    await _openChannel(channel);
  }

  Future<void> _openChannel(ChatChannel channel) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatChannelPage(
          channelId: channel.id,
          title: channel.title,
          channel: channel,
        ),
      ),
    );
    if (mounted && channel.isDirectMessage) {
      await ref
          .read(chatChannelListProvider.notifier)
          .refreshUntilChannelVisible(channel.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 仅当本 tab 激活时才响应底栏快捷动作
    ref.listen(navActionBusProvider, (_, event) => _onNavAction(event));

    final indexAsync = ref.watch(chatChannelListProvider);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Semantics(
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openChannelSwitcher,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${context.l10n.chat_title} - ${AppConstants.appName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: context.l10n.chat_searchTitle,
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ChatSearchPage())),
              icon: const Icon(Icons.search_rounded, size: 26),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: () =>
                  ref.read(chatChannelListProvider.notifier).refreshSilently(),
              icon: const Icon(Icons.refresh_rounded, size: 28),
            ),
          ],
        ),
        body: indexAsync.when(
          data: (index) => _buildChannelList(context, index),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) =>
              ErrorView(error: e, stackTrace: st, onRetry: _onRefresh),
        ),
      ),
    );
  }

  Widget _buildChannelList(BuildContext context, ChatChannelIndex index) {
    final public = index.publicChannels;
    final direct = index.directMessageChannels;

    return DesktopRefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _SectionHeader(
            title: context.l10n.chat_channels,
            trailing: IconButton(
              tooltip: context.l10n.chat_browseChannels,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 22),
              onPressed: _browseChannels,
            ),
          ),
          for (final c in public) _ChannelTile(channel: c),
          _SectionHeader(
            title: context.l10n.chat_directMessages,
            trailing: IconButton(
              tooltip: context.l10n.chat_newDirectMessage,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded, size: 23),
              onPressed: _startDirectMessage,
            ),
          ),
          if (direct.isEmpty)
            _DirectMessageEmptyState(onStart: _startDirectMessage)
          else
            for (final c in direct) _ChannelTile(channel: c),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _DirectMessageEmptyState extends StatelessWidget {
  const _DirectMessageEmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.48,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 112,
                height: 92,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 60,
                      color: theme.colorScheme.primary,
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                        child: Text(
                          '0',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.l10n.chat_directMessagesEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onStart,
                child: Text(context.l10n.chat_startConversation),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends ConsumerWidget {
  final ChatChannel channel;
  const _ChannelTile({required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = _unreadCount(channel);
    final timestamp = formatChatChannelLastMessageTime(
      context,
      channel.lastMessage?.createdAt,
    );
    final muted = channel.currentUserMembership?.muted == true;
    final description = channel.description?.trim();
    final showDescription =
        channel.title.isNotEmpty && description?.isNotEmpty == true;

    final tile = ListTile(
      leading: ChatChannelIcon(channel: channel),
      title: Text(
        channel.title.isEmpty ? channel.description ?? '' : channel.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: showDescription
          ? Text(description!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: timestamp.isNotEmpty || unread > 0 || muted
          ? _ChannelTrailing(timestamp: timestamp, unread: unread, muted: muted)
          : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatChannelPage(
              channelId: channel.id,
              title: channel.title,
              channel: channel,
            ),
          ),
        );
      },
    );

    if (!channel.isDirectMessage) return tile;
    return Dismissible(
      key: ValueKey('direct-message-${channel.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, ref),
      onDismissed: (_) {
        ref.read(chatChannelListProvider.notifier).removeChannel(channel.id);
      },
      background: _DeleteBackground(
        label: context.l10n.chat_deleteDirectMessage,
      ),
      child: tile,
    );
  }

  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final name = channel.title.trim().isNotEmpty
        ? channel.title.trim()
        : context.l10n.chat_directMessages;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(dialogContext.l10n.chat_deleteDirectMessage),
          content: Text(
            dialogContext.l10n.chat_deleteDirectMessageConfirm(name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.chat_deleteDirectMessage),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return false;

    try {
      await ref.read(discourseServiceProvider).leaveChatChannel(channel.id);
      return context.mounted;
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (context.mounted) {
        ToastService.showError(context.l10n.chat_deleteDirectMessageFailed);
      }
      return false;
    }
  }

  /// 简单未读：以 last_message 与已读位置比较近似统计，首版不精确
  int _unreadCount(ChatChannel channel) {
    final last = channel.lastMessage;
    final lastRead = channel.currentUserMembership?.lastReadMessageId;
    if (last == null || lastRead == null) return 0;
    return last.id > lastRead ? 1 : 0;
  }
}

class _ChannelTrailing extends StatelessWidget {
  const _ChannelTrailing({
    required this.timestamp,
    required this.unread,
    required this.muted,
  });

  final String timestamp;
  final int unread;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasStatus = unread > 0 || muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (timestamp.isNotEmpty)
          Text(
            timestamp,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (timestamp.isNotEmpty && hasStatus) const SizedBox(height: 4),
        if (hasStatus)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    '$unread',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (muted) ...[
                if (unread > 0) const SizedBox(width: 6),
                const Icon(Symbols.notifications_off_rounded, size: 18),
              ],
            ],
          ),
      ],
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: colorScheme.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: colorScheme.onError),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onError,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
