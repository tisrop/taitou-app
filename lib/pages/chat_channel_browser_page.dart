import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../models/chat/chat_channel.dart';
import '../providers/chat/chat_channel_list_provider.dart';
import '../providers/core_providers.dart';
import '../services/toast_service.dart';
import '../widgets/chat/chat_channel_icon.dart';
import '../widgets/chat/create_chat_channel_sheet.dart';
import '../widgets/common/misc/error_view.dart';
import 'chat_channel_page.dart';

enum _ChannelStatusFilter { all, open, closed }

enum _JoinedFilter { all, joined, notJoined }

class ChatChannelBrowserPage extends ConsumerStatefulWidget {
  const ChatChannelBrowserPage({super.key});

  @override
  ConsumerState<ChatChannelBrowserPage> createState() =>
      _ChatChannelBrowserPageState();
}

class _ChatChannelBrowserPageState
    extends ConsumerState<ChatChannelBrowserPage> {
  static const _pageSize = 50;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;
  _ChannelStatusFilter _status = _ChannelStatusFilter.open;
  _JoinedFilter _joined = _JoinedFilter.all;
  List<ChatChannel> _channels = const [];
  Object? _error;
  StackTrace? _stackTrace;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _loadGeneration = 0;
  final Set<int> _joiningIds = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadChannels());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _statusValue => switch (_status) {
    _ChannelStatusFilter.all => null,
    _ChannelStatusFilter.open => 'open',
    _ChannelStatusFilter.closed => 'closed',
  };

  List<ChatChannel> get _visibleChannels => switch (_joined) {
    _JoinedFilter.all => _channels,
    _JoinedFilter.joined =>
      _channels.where((channel) => channel.isFollowing).toList(),
    _JoinedFilter.notJoined =>
      _channels.where((channel) => !channel.isFollowing).toList(),
  };

  void _onScroll() {
    if (_scrollController.position.extentAfter < 360) {
      unawaited(_loadMore());
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_loadChannels()),
    );
  }

  Future<void> _loadChannels() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _stackTrace = null;
    });
    try {
      final page = await ref
          .read(discourseServiceProvider)
          .getChatChannelDirectory(
            filter: _searchController.text,
            status: _statusValue,
            limit: _pageSize,
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _channels = page.channels;
        _hasMore = page.channels.length >= _pageSize;
        _loading = false;
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error;
        _stackTrace = stackTrace;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final generation = _loadGeneration;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(discourseServiceProvider)
          .getChatChannelDirectory(
            filter: _searchController.text,
            status: _statusValue,
            offset: _channels.length,
            limit: _pageSize,
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        final ids = _channels.map((channel) => channel.id).toSet();
        _channels = [
          ..._channels,
          ...page.channels.where((channel) => ids.add(channel.id)),
        ];
        _hasMore = page.channels.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _selectStatus(_ChannelStatusFilter status) {
    if (_status == status) return;
    setState(() => _status = status);
    unawaited(_loadChannels());
  }

  Future<void> _openChannel(ChatChannel channel) async {
    var target = channel;
    if (!channel.isFollowing) {
      if (!channel.isJoinable) {
        ToastService.showError(context.l10n.chat_closedChannelUnavailable);
        return;
      }
      if (_joiningIds.contains(channel.id)) return;
      setState(() => _joiningIds.add(channel.id));
      try {
        final membership = await ref
            .read(discourseServiceProvider)
            .joinChatChannel(channel.id);
        target = channel.copyWith(currentUserMembership: membership);
        if (!mounted) return;
        setState(() {
          _joiningIds.remove(channel.id);
          _channels = [
            for (final item in _channels)
              if (item.id == channel.id) target else item,
          ];
        });
        ref.read(chatChannelListProvider.notifier).upsertChannel(target);
        unawaited(ref.read(chatChannelListProvider.notifier).refreshSilently());
      } catch (_) {
        if (!mounted) return;
        setState(() => _joiningIds.remove(channel.id));
        ToastService.showError(context.l10n.chat_joinChannelFailed);
        return;
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatChannelPage(
          channelId: target.id,
          title: target.title,
          channel: target,
        ),
      ),
    );
  }

  Future<void> _createChannel() async {
    final channel = await showCreateChatChannelSheet(context);
    if (channel == null || !mounted) return;
    ref.read(chatChannelListProvider.notifier).upsertChannel(channel);
    unawaited(ref.read(chatChannelListProvider.notifier).refreshSilently());
    await _loadChannels();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatChannelPage(
          channelId: channel.id,
          title: channel.title,
          channel: channel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).value;
    final canCreate =
        currentUser?.admin == true || currentUser?.moderator == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.chat_channels),
        actions: [
          if (canCreate)
            IconButton(
              tooltip: context.l10n.chat_createChannel,
              onPressed: _createChannel,
              icon: const Icon(Icons.add_rounded, size: 29),
            ),
        ],
      ),
      body: Column(
        children: [
          _StatusTabs(selected: _status, onSelected: _selectStatus),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              children: [
                DropdownButtonFormField<_JoinedFilter>(
                  initialValue: _joined,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.filter_list_rounded),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: _JoinedFilter.all,
                      child: Text(context.l10n.chat_channelJoinedAll),
                    ),
                    DropdownMenuItem(
                      value: _JoinedFilter.joined,
                      child: Text(context.l10n.chat_channelJoined),
                    ),
                    DropdownMenuItem(
                      value: _JoinedFilter.notJoined,
                      child: Text(context.l10n.chat_channelNotJoined),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _joined = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: context.l10n.chat_searchChannelsHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              unawaited(_loadChannels());
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorView(
        error: _error!,
        stackTrace: _stackTrace,
        onRetry: _loadChannels,
      );
    }

    final channels = _visibleChannels;
    if (channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.l10n.chat_noChannelsFound,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadChannels,
      child: ListView.separated(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: channels.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == channels.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final channel = channels[index];
          return _ChannelCard(
            channel: channel,
            joining: _joiningIds.contains(channel.id),
            onTap: () => _openChannel(channel),
          );
        },
      ),
    );
  }
}

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.selected, required this.onSelected});

  final _ChannelStatusFilter selected;
  final ValueChanged<_ChannelStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          _tab(
            context,
            _ChannelStatusFilter.all,
            context.l10n.chat_channelStatusAll,
          ),
          _tab(
            context,
            _ChannelStatusFilter.open,
            context.l10n.chat_channelStatusOpen,
          ),
          _tab(
            context,
            _ChannelStatusFilter.closed,
            context.l10n.chat_channelStatusClosed,
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, _ChannelStatusFilter value, String label) {
    final active = value == selected;
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: () => onSelected(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? colors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: active ? colors.primary : colors.onSurface,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.channel,
    required this.joining,
    required this.onTap,
  });

  final ChatChannel channel;
  final bool joining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final borderColor =
        _parseColor(channel.chatableColor) ?? colors.outlineVariant;

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: 1.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChatChannelIcon(channel: channel, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.chat_channelMembers(
                        channel.membershipsCount,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (channel.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      Text(
                        channel.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (joining)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else if (channel.isFollowing)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                )
              else if (channel.isJoinable)
                FilledButton.tonal(
                  onPressed: onTap,
                  child: Text(context.l10n.chat_joinChannel),
                )
              else
                Text(
                  context.l10n.chat_channelStatusClosed,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color? _parseColor(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }
}
