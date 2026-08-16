import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;

import '../l10n/s.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_thread.dart';
import '../providers/discourse_providers.dart';
import '../utils/time_utils.dart';
import '../widgets/common/visual/smart_avatar.dart';

/// 当前频道内的消息串列表。
class ChatThreadsPage extends ConsumerStatefulWidget {
  const ChatThreadsPage({
    super.key,
    required this.channelId,
    this.channelTitle = '',
  });

  final int channelId;
  final String channelTitle;

  @override
  ConsumerState<ChatThreadsPage> createState() => _ChatThreadsPageState();
}

class _ChatThreadsPageState extends ConsumerState<ChatThreadsPage> {
  static const _pageSize = chatThreadsMaxPageSize;

  final _scrollController = ScrollController();
  List<ChatThread> _threads = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 280) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
      });
    } else {
      if (_loading || _loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final offset = reset ? 0 : _threads.length;
      final page = await ref
          .read(discourseServiceProvider)
          .getChatThreads(widget.channelId, offset: offset, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        final seen = reset ? <int>{} : _threads.map((item) => item.id).toSet();
        final incoming = page.threads.where((item) => seen.add(item.id));
        _threads = reset ? incoming.toList() : [..._threads, ...incoming];
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) _error = error;
      });
    }
  }

  Future<void> _openThread(ChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatThreadPage(channelId: widget.channelId, thread: thread),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.chat_threadsTitle)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _threads.isEmpty) {
      return _ThreadStatus(
        icon: Icons.forum_outlined,
        text: context.l10n.chat_threadsFailed,
        action: TextButton.icon(
          onPressed: () => _load(reset: true),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.l10n.chat_retry),
        ),
      );
    }
    if (_threads.isEmpty) {
      return _ThreadStatus(
        icon: Icons.forum_outlined,
        text: context.l10n.chat_threadsEmpty,
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        itemCount: _threads.length + 1,
        separatorBuilder: (_, index) => index < _threads.length - 1
            ? const Divider(height: 1, indent: 76)
            : const SizedBox.shrink(),
        itemBuilder: (context, index) {
          if (index == _threads.length) {
            return _loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                : const SizedBox(height: 20);
          }
          final thread = _threads[index];
          return _ChatThreadTile(
            thread: thread,
            onTap: () => _openThread(thread),
          );
        },
      ),
    );
  }
}

/// 单个消息串的只读查看页。
class ChatThreadPage extends ConsumerStatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.channelId,
    required this.thread,
  });

  final int channelId;
  final ChatThread thread;

  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> {
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(discourseServiceProvider)
          .getChatThreadMessages(widget.channelId, widget.thread.id);
      if (!mounted) return;
      setState(() {
        _messages = page.messages
            .where((message) => message.id != widget.thread.originalMessage?.id)
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.thread.title?.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title?.isNotEmpty == true ? title! : context.l10n.chat_thread,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ThreadStatus(
        icon: Icons.forum_outlined,
        text: context.l10n.chat_threadsFailed,
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.l10n.chat_retry),
        ),
      );
    }

    final original = widget.thread.originalMessage;
    if (original == null && _messages.isEmpty) {
      return _ThreadStatus(
        icon: Icons.forum_outlined,
        text: context.l10n.chat_threadMessagesEmpty,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _messages.length + (original == null ? 0 : 1),
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          if (original != null && index == 0) {
            return _ThreadMessageTile(message: original, original: true);
          }
          final messageIndex = index - (original == null ? 0 : 1);
          return _ThreadMessageTile(message: _messages[messageIndex]);
        },
      ),
    );
  }
}

class _ChatThreadTile extends StatelessWidget {
  const _ChatThreadTile({required this.thread, required this.onTap});

  final ChatThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final original = thread.originalMessage;
    final user = original?.user ?? thread.preview?.lastReplyUser;
    final explicitTitle = thread.title?.trim() ?? '';
    final originalPreview = _plainText(
      original?.excerpt ?? original?.message ?? '',
    );
    final title = explicitTitle.isNotEmpty ? explicitTitle : originalPreview;
    final lastReply = _plainText(thread.preview?.lastReplyExcerpt ?? '');
    final replies = thread.replyCount > 0
        ? thread.replyCount
        : thread.preview?.replyCount ?? 0;
    final time = TimeUtils.formatRelativeTime(
      thread.preview?.lastReplyCreatedAt ?? original?.createdAt,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SmartAvatar(
              imageUrl: user?.getAvatarUrl(size: 88),
              radius: 22,
              fallbackText: user?.username,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? context.l10n.chat_thread : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (time.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (lastReply.isNotEmpty && lastReply != title) ...[
                    const SizedBox(height: 5),
                    Text(
                      lastReply,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 17,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        context.l10n.chat_threadReplies(replies),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadMessageTile extends StatelessWidget {
  const _ThreadMessageTile({required this.message, this.original = false});

  final ChatMessage message;
  final bool original;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = _plainText(
      message.excerpt ?? message.cooked ?? message.message,
    );
    final time = TimeUtils.formatRelativeTime(message.createdAt);

    return ColoredBox(
      color: original
          ? theme.colorScheme.surfaceContainerLow
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SmartAvatar(
              imageUrl: message.user.getAvatarUrl(size: 80),
              radius: 20,
              fallbackText: message.user.username,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          message.user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadStatus extends StatelessWidget {
  const _ThreadStatus({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: theme.colorScheme.outline),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      ),
    );
  }
}

String _plainText(String value) {
  final text = value.contains('<')
      ? (html_parser.parseFragment(value).text ?? '')
      : value;
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
