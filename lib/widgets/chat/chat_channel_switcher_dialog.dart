import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../l10n/s.dart';
import '../../models/chat/chat_channel.dart';
import '../../models/mention_user.dart';
import '../../providers/chat/chat_channel_list_provider.dart';
import '../../providers/core_providers.dart';
import '../../utils/dialog_utils.dart';
import '../common/visual/smart_avatar.dart';
import 'chat_channel_icon.dart';

const _maxGroupMembers = 20;

enum DirectMessageConversationType { oneToOne, group }

DirectMessageConversationType? directMessageConversationTypeFor(
  int selectedRecipientCount,
) {
  if (selectedRecipientCount < 1) return null;
  return selectedRecipientCount == 1
      ? DirectMessageConversationType.oneToOne
      : DirectMessageConversationType.group;
}

/// 从页面顶部展开频道切换器；创建群聊时会在同一个面板内切换为成员选择表单。
Future<ChatChannel?> showChatChannelSwitcher({required BuildContext context}) {
  return showAppGeneralDialog<ChatChannel>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    blur: false,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) => const Align(
      alignment: Alignment.topCenter,
      child: _ChatChannelSwitcherDialog(),
    ),
  );
}

enum _SwitcherMode { channels, createGroup }

class _ChatChannelSwitcherDialog extends ConsumerStatefulWidget {
  const _ChatChannelSwitcherDialog();

  @override
  ConsumerState<_ChatChannelSwitcherDialog> createState() =>
      _ChatChannelSwitcherDialogState();
}

class _ChatChannelSwitcherDialogState
    extends ConsumerState<_ChatChannelSwitcherDialog> {
  final TextEditingController _filterController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _memberSearchController = TextEditingController();
  final FocusNode _filterFocusNode = FocusNode();
  final FocusNode _memberSearchFocusNode = FocusNode();
  final Map<String, MentionUser> _selectedUsers = {};

  Timer? _debounce;
  int _searchGeneration = 0;
  _SwitcherMode _mode = _SwitcherMode.channels;
  List<MentionUser> _users = const [];
  bool _searching = false;
  bool _hasSearched = false;
  bool _refreshing = false;
  bool _creating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _filterFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _filterController.dispose();
    _groupNameController.dispose();
    _memberSearchController.dispose();
    _filterFocusNode.dispose();
    _memberSearchFocusNode.dispose();
    super.dispose();
  }

  void _openGroupForm() {
    setState(() {
      _mode = _SwitcherMode.createGroup;
      _errorMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _memberSearchFocusNode.requestFocus();
    });
  }

  Future<void> _refreshChannels() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await ref.read(chatChannelListProvider.notifier).refreshSilently();
    if (mounted) setState(() => _refreshing = false);
  }

  void _onMemberQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _searchGeneration++;
      setState(() {
        _users = const [];
        _searching = false;
        _hasSearched = false;
        _errorMessage = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _errorMessage = null;
    });

    final result = await ref
        .read(discourseServiceProvider)
        .searchUsers(term: query, includeGroups: false, limit: 20);
    if (!mounted || generation != _searchGeneration) return;

    final currentUsername = ref.read(currentUserProvider).value?.username;
    setState(() {
      _users = result.users.where((user) {
        return currentUsername == null ||
            user.username.toLowerCase() != currentUsername.toLowerCase();
      }).toList();
      _searching = false;
      _hasSearched = true;
    });
  }

  void _toggleUser(MentionUser user) {
    if (_creating) return;
    final key = user.username.toLowerCase();
    setState(() {
      if (_selectedUsers.containsKey(key)) {
        _selectedUsers.remove(key);
      } else if (_selectedUsers.length >= _maxGroupMembers) {
        _errorMessage = context.l10n.chat_groupMemberLimit;
      } else {
        _selectedUsers[key] = user;
        _errorMessage = null;
      }
    });
  }

  Future<void> _createConversation() async {
    if (_creating) return;
    final conversationType = directMessageConversationTypeFor(
      _selectedUsers.length,
    );
    if (conversationType == null) {
      setState(() => _errorMessage = context.l10n.chat_groupNeedsMembers);
      return;
    }

    setState(() {
      _creating = true;
      _errorMessage = null;
    });
    try {
      final channel = await ref
          .read(chatChannelListProvider.notifier)
          .createDirectMessageChannel(
            _selectedUsers.values.map((user) => user.username).toList(),
            name: conversationType == DirectMessageConversationType.group
                ? _groupNameController.text
                : null,
            upsert: conversationType == DirectMessageConversationType.oneToOne,
          );
      if (!mounted) return;
      Navigator.of(context).pop<ChatChannel>(channel);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _errorMessage =
            conversationType == DirectMessageConversationType.oneToOne
            ? context.l10n.chat_createDirectMessageFailed
            : context.l10n.chat_createGroupFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    final panelHeight = _panelHeight(availableHeight);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 10,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          width: double.infinity,
          height: panelHeight,
          child: Column(
            children: [
              _buildHeader(context),
              if (_mode == _SwitcherMode.channels)
                Expanded(child: _buildChannelMode(context))
              else
                Expanded(child: _buildGroupMode(context)),
            ],
          ),
        ),
      ),
    );
  }

  double _panelHeight(double availableHeight) {
    if (_mode == _SwitcherMode.channels) {
      final channelCount =
          ref.read(chatChannelListProvider).value?.allChannels.length ?? 0;
      final desired = 150.0 + 58.0 + math.min(channelCount, 5) * 58.0;
      return math.min(availableHeight, math.max(266.0, desired));
    }

    final selectedRows = _selectedUsers.isEmpty ? 0.0 : 58.0;
    final resultRows = _hasSearched ? math.min(_users.length, 4) * 64.0 : 0.0;
    final actionRows = _selectedUsers.isEmpty ? 0.0 : 70.0;
    final desired = 218.0 + selectedRows + resultRows + actionRows;
    return math.min(availableHeight, math.max(218.0, desired));
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 31,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '${context.l10n.chat_title} - ${AppConstants.appName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _refreshing ? null : _refreshChannels,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 23,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 31),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelMode(BuildContext context) {
    final theme = Theme.of(context);
    final indexAsync = ref.watch(chatChannelListProvider);
    final query = _filterController.text.trim().toLowerCase();
    final channels =
        indexAsync.value?.allChannels.where((channel) {
          if (query.isEmpty) return true;
          final users = channel.directMessageUsers
              .map((user) => '${user.username} ${user.name}')
              .join(' ');
          return '${channel.title} ${channel.description ?? ''} $users'
              .toLowerCase()
              .contains(query);
        }).toList() ??
        const <ChatChannel>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: TextField(
            controller: _filterController,
            focusNode: _filterFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: context.l10n.chat_filterChannels,
              prefixIcon: const Icon(Icons.search_rounded, size: 27),
              suffixIcon: IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                onPressed: () {
                  _filterController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded, size: 24),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ),
        Material(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
          child: ListTile(
            minTileHeight: 58,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.group_rounded,
                size: 23,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            title: Text(
              context.l10n.chat_createGroupChat,
              style: theme.textTheme.titleMedium,
            ),
            onTap: _openGroupForm,
          ),
        ),
        Expanded(
          child: indexAsync.isLoading && indexAsync.value == null
              ? const Center(child: CircularProgressIndicator())
              : channels.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.chat_noChannelsFound,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.zero,
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    return ListTile(
                      minTileHeight: 58,
                      leading: ChatChannelIcon(channel: channel, size: 38),
                      title: Text(
                        channel.title.isEmpty
                            ? channel.description ?? ''
                            : channel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      onTap: () =>
                          Navigator.of(context).pop<ChatChannel>(channel),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGroupMode(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    enabled: !_creating,
                    maxLength: 100,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: context.l10n.chat_groupNameOptional,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  context.l10n.chat_memberCount(
                    _selectedUsers.length,
                    _maxGroupMembers,
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        if (_selectedUsers.isNotEmpty) _buildSelectedUsers(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: TextField(
            controller: _memberSearchController,
            focusNode: _memberSearchFocusNode,
            enabled: !_creating,
            textInputAction: TextInputAction.search,
            onChanged: _onMemberQueryChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: context.l10n.chat_addMoreMembers,
              prefixIcon: const Icon(Icons.search_rounded, size: 27),
              suffixIcon: IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                onPressed: _creating
                    ? null
                    : () {
                        _memberSearchController.clear();
                        _onMemberQueryChanged('');
                      },
                icon: const Icon(Icons.close_rounded, size: 24),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(child: _buildMemberResults(context)),
        if (_selectedUsers.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _creating ? null : _createConversation,
                  child: _creating
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _selectedUsers.length == 1
                              ? context.l10n.chat_startConversation
                              : context.l10n.chat_createGroupChat,
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSelectedUsers(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: _selectedUsers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final user = _selectedUsers.values.elementAt(index);
          return InputChip(
            avatar: SmartAvatar(
              imageUrl: user.getAvatarUrl(AppConstants.baseUrl, size: 64),
              radius: 14,
              fallbackText: user.username,
            ),
            label: Text(
              user.name?.trim().isNotEmpty == true
                  ? user.name!.trim()
                  : user.username,
            ),
            onDeleted: _creating ? null : () => _toggleUser(user),
          );
        },
      ),
    );
  }

  Widget _buildMemberResults(BuildContext context) {
    final theme = Theme.of(context);
    if (_searching && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasSearched) return const SizedBox.shrink();
    if (_users.isEmpty) {
      return Center(
        child: Text(
          context.l10n.chat_noUsersFound,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        final selected = _selectedUsers.containsKey(
          user.username.toLowerCase(),
        );
        final displayName = user.name?.trim();
        return ListTile(
          enabled: !_creating,
          minTileHeight: 64,
          leading: SmartAvatar(
            imageUrl: user.getAvatarUrl(AppConstants.baseUrl, size: 96),
            radius: 22,
            fallbackText: user.username,
          ),
          title: Text(
            displayName?.isNotEmpty == true ? displayName! : user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: displayName?.isNotEmpty == true
              ? Text(
                  '@${user.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.add_circle_outline_rounded,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          onTap: () => _toggleUser(user),
        );
      },
    );
  }
}
