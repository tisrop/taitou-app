import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants.dart';
import '../../l10n/s.dart';
import '../../models/chat/chat_channel.dart';
import '../../models/mention_user.dart';
import '../../providers/chat/chat_channel_list_provider.dart';
import '../../providers/core_providers.dart';
import '../common/visual/smart_avatar.dart';

/// 创建直接消息时使用的用户搜索列表。
///
/// 点击候选用户后立即创建（或获取已有的）一对一频道，成功时通过
/// [Navigator.pop] 返回 [ChatChannel]。
class DirectMessageUserPicker extends ConsumerStatefulWidget {
  const DirectMessageUserPicker({super.key});

  @override
  ConsumerState<DirectMessageUserPicker> createState() =>
      _DirectMessageUserPickerState();
}

class _DirectMessageUserPickerState
    extends ConsumerState<DirectMessageUserPicker> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  int _searchGeneration = 0;

  List<MentionUser> _users = const [];
  bool _searching = false;
  bool _hasSearched = false;
  String? _creatingUsername;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
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
      _users = result.users
          .where(
            (user) =>
                currentUsername == null ||
                user.username.toLowerCase() != currentUsername.toLowerCase(),
          )
          .toList();
      _searching = false;
      _hasSearched = true;
    });
  }

  Future<void> _createConversation(MentionUser user) async {
    if (_creatingUsername != null) return;
    setState(() {
      _creatingUsername = user.username;
      _errorMessage = null;
    });

    try {
      final channel = await ref
          .read(chatChannelListProvider.notifier)
          .createDirectMessageChannel([user.username]);
      if (!mounted) return;
      Navigator.of(context).pop<ChatChannel>(channel);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creatingUsername = null;
        _errorMessage = context.l10n.chat_createDirectMessageFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.58;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: _creatingUsername == null,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: context.l10n.chat_searchUsersHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 21),
                suffixIcon:
                    _controller.text.isNotEmpty && _creatingUsername == null
                    ? IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        icon: const Icon(Icons.close_rounded, size: 19),
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_searching && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasSearched) {
      return _PickerHint(
        icon: Icons.person_search_rounded,
        text: context.l10n.chat_searchUsersPrompt,
      );
    }
    if (_users.isEmpty) {
      return _PickerHint(
        icon: Icons.search_off_rounded,
        text: context.l10n.chat_noUsersFound,
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: _users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final user = _users[index];
        final isCreating = _creatingUsername == user.username;
        final displayName = user.name?.trim();
        return ListTile(
          enabled: _creatingUsername == null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
          trailing: isCreating
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
          onTap: () => _createConversation(user),
        );
      },
    );
  }
}

class _PickerHint extends StatelessWidget {
  const _PickerHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 52,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
