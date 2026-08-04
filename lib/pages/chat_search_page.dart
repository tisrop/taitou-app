import 'dart:async';

import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import '../l10n/s.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_message_search.dart';
import '../providers/discourse_providers.dart';
import '../services/emoji_handler.dart';
import '../utils/time_utils.dart';
import '../utils/fluxdo_render_callbacks.dart';
import '../widgets/chat/chat_channel_icon.dart';
import '../widgets/common/visual/smart_avatar.dart';
import 'chat_channel_page.dart';

/// 跨所有可见频道的公共聊天消息搜索。
class ChatSearchPage extends ConsumerStatefulWidget {
  const ChatSearchPage({super.key});

  @override
  ConsumerState<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends ConsumerState<ChatSearchPage> {
  static const _pageSize = 20;
  static const _debounceDuration = Duration(milliseconds: 350);

  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  Timer? _debounce;
  ChatMessageSearchSort _sort = ChatMessageSearchSort.relevance;
  List<ChatMessageSearchHit> _hits = const [];
  String _submittedQuery = '';
  int _offset = 0;
  int _requestGeneration = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _loadMoreFailed = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _requestGeneration++;
      setState(() {
        _submittedQuery = '';
        _hits = const [];
        _offset = 0;
        _hasMore = false;
        _isLoading = false;
        _isLoadingMore = false;
        _loadMoreFailed = false;
        _error = null;
      });
      return;
    }

    setState(() {});
    _debounce = Timer(_debounceDuration, () => _search(reset: true));
  }

  void _onSubmitted(String _) {
    _debounce?.cancel();
    _search(reset: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 280) {
      _search(reset: false);
    }
  }

  Future<void> _search({required bool reset}) async {
    final query = reset ? _searchController.text.trim() : _submittedQuery;
    if (query.isEmpty) return;
    if (reset) {
      final generation = ++_requestGeneration;
      setState(() {
        _submittedQuery = query;
        _isLoading = true;
        _isLoadingMore = false;
        _loadMoreFailed = false;
        _error = null;
        _hits = const [];
        _offset = 0;
        _hasMore = false;
      });
      await _fetchPage(query: query, offset: 0, generation: generation);
      return;
    }

    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final generation = _requestGeneration;
    setState(() {
      _isLoadingMore = true;
      _loadMoreFailed = false;
    });
    await _fetchPage(query: query, offset: _offset, generation: generation);
  }

  Future<void> _fetchPage({
    required String query,
    required int offset,
    required int generation,
  }) async {
    try {
      final page = await ref
          .read(discourseServiceProvider)
          .searchChatMessages(
            query: query,
            sort: _sort,
            offset: offset,
            limit: _pageSize,
          );
      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        final existing = offset == 0
            ? <int>{}
            : _hits.map((hit) => hit.message.id).toSet();
        final uniqueHits = page.hits
            .where((hit) => existing.add(hit.message.id))
            .toList();
        _hits = offset == 0 ? uniqueHits : [..._hits, ...uniqueHits];
        _offset = offset + page.hits.length;
        _hasMore = page.hasMore && page.hits.isNotEmpty;
        _isLoading = false;
        _isLoadingMore = false;
        _loadMoreFailed = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        if (offset == 0) {
          _error = error;
        } else {
          _loadMoreFailed = true;
        }
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _changeSort(ChatMessageSearchSort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    if (_searchController.text.trim().isNotEmpty) {
      _search(reset: true);
    }
  }

  String _sortLabel(BuildContext context, ChatMessageSearchSort sort) {
    return switch (sort) {
      ChatMessageSearchSort.relevance => context.l10n.chat_searchSortRelevance,
      ChatMessageSearchSort.latest => context.l10n.chat_searchSortLatest,
    };
  }

  Future<void> _openResult(ChatMessageSearchHit hit) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatChannelPage(
          channelId: hit.channel.id,
          title: hit.channel.title,
          initialMessageId: hit.message.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.chat_searchTitle)),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: _onQueryChanged,
                    onSubmitted: _onSubmitted,
                    decoration: InputDecoration(
                      hintText: context.l10n.chat_searchMessagesHint,
                      prefixIcon: Icon(
                        Symbols.search_rounded,
                        size: 26,
                        color: theme.colorScheme.outline,
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).deleteButtonTooltip,
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                _onQueryChanged('');
                                _focusNode.requestFocus();
                              },
                            ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<ChatMessageSearchSort>(
                      initialValue: _sort,
                      tooltip: _sortLabel(context, _sort),
                      position: PopupMenuPosition.under,
                      offset: const Offset(0, 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      color: theme.colorScheme.surface,
                      constraints: const BoxConstraints(
                        minWidth: 200,
                        maxWidth: 280,
                      ),
                      onSelected: _changeSort,
                      itemBuilder: (context) => [
                        for (final sort in ChatMessageSearchSort.values)
                          PopupMenuItem(
                            value: sort,
                            child: Text(_sortLabel(context, sort)),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.unfold_more_rounded,
                              size: 22,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _sortLabel(context, _sort),
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_submittedQuery.isEmpty) {
      return _SearchStatus(
        icon: Icons.manage_search_rounded,
        text: context.l10n.chat_searchPrompt,
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _SearchStatus(
        icon: Icons.search_off_rounded,
        text: context.l10n.chat_searchFailed,
        action: TextButton.icon(
          onPressed: () => _search(reset: true),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.l10n.chat_retry),
        ),
      );
    }
    if (_hits.isEmpty) {
      return _SearchStatus(
        icon: Icons.search_off_rounded,
        text: context.l10n.chat_searchNoResults,
      );
    }

    return ListView.separated(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      itemCount: _hits.length + 1,
      separatorBuilder: (_, index) => index < _hits.length - 1
          ? const Divider(height: 1, indent: 76)
          : const SizedBox.shrink(),
      itemBuilder: (context, index) {
        if (index == _hits.length) return _buildFooter(context);
        final hit = _hits[index];
        return _ChatSearchResultTile(hit: hit, onTap: () => _openResult(hit));
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: TextButton.icon(
            onPressed: () => _search(reset: false),
            icon: const Icon(Icons.refresh_rounded, size: 19),
            label: Text(context.l10n.chat_retry),
          ),
        ),
      );
    }
    return const SizedBox(height: 20);
  }
}

class _ChatSearchResultTile extends StatelessWidget {
  const _ChatSearchResultTile({required this.hit, required this.onTap});

  final ChatMessageSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = hit.message;
    final channelTitle = hit.channel.title.trim().isEmpty
        ? '#${hit.channel.id}'
        : hit.channel.title;
    final renderedHtml = chatSearchMessageRenderedHtml(message);
    final imageHtml = chatSearchContentImageHtml(renderedHtml);
    final emojiHtml = imageHtml == null
        ? chatSearchEmojiHtml(renderedHtml)
        : null;
    final preview = _messagePreview(message.excerpt ?? message.message);
    final time = TimeUtils.formatRelativeTime(message.createdAt);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SmartAvatar(
              imageUrl: message.user.getAvatarUrl(size: 88),
              radius: 22,
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
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: message.user.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (message.user.username.isNotEmpty) ...[
                                TextSpan(
                                  text: '  @${message.user.username}',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  const SizedBox(height: 5),
                  if (imageHtml != null)
                    _SearchResultRichContent(
                      key: ValueKey('chat-search-content-${message.id}'),
                      html: imageHtml,
                      messageId: message.id,
                      maxHeight: 180,
                    )
                  else if (emojiHtml != null)
                    _SearchResultRichContent(
                      key: ValueKey('chat-search-content-${message.id}'),
                      html: emojiHtml,
                      messageId: message.id,
                      maxHeight: 40,
                    )
                  else
                    Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      ChatChannelIcon(channel: hit.channel, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
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

  static String _messagePreview(String value) {
    final text = value.contains('<')
        ? (html_parser.parseFragment(value).text ?? '')
        : value;
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

@visibleForTesting
String chatSearchMessageRenderedHtml(ChatMessage message) {
  final cooked = message.cooked?.trim();
  final rawHtml = md.markdownToHtml(
    EmojiHandler().replaceEmojis(message.message),
  );
  if (cooked?.isNotEmpty == true && cooked!.contains('<img')) return cooked;
  if (rawHtml.contains('<img')) return rawHtml;
  return cooked?.isNotEmpty == true ? cooked! : rawHtml;
}

@visibleForTesting
String? chatSearchContentImageHtml(String html) {
  final fragment = html_parser.parseFragment(html);
  for (final image in fragment.querySelectorAll('img')) {
    if (_isEmojiImage(image)) continue;
    return '<p>${image.outerHtml}</p>';
  }
  return null;
}

@visibleForTesting
String? chatSearchEmojiHtml(String html) {
  final fragment = html_parser.parseFragment(html);
  final images = fragment.querySelectorAll('img');
  if (images.isEmpty || fragment.text?.trim().isNotEmpty == true) return null;
  if (images.any((image) => !_isEmojiImage(image))) return null;
  return '<p>${images.map((image) => image.outerHtml).join()}</p>';
}

bool _isEmojiImage(dom.Element image) {
  final src =
      (image.attributes['data-orig-src'] ?? image.attributes['src'] ?? '')
          .toLowerCase();
  return image.classes.contains('emoji') || src.contains('/emoji/');
}

class _SearchResultRichContent extends StatefulWidget {
  const _SearchResultRichContent({
    super.key,
    required this.html,
    required this.messageId,
    required this.maxHeight,
  });

  final String html;
  final int messageId;
  final double maxHeight;

  @override
  State<_SearchResultRichContent> createState() =>
      _SearchResultRichContentState();
}

class _SearchResultRichContentState extends State<_SearchResultRichContent> {
  late final FluxdoRenderCallbacks _callbacks = FluxdoRenderCallbacks.generic(
    heroTagNamespace: 'chat_search_${widget.messageId}',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 360,
              maxHeight: widget.maxHeight,
            ),
            child: _callbacks.render(
              cookedHtml: widget.html,
              baseTextStyle: theme.textTheme.bodyMedium,
              selectionEnabled: false,
              compact: true,
              shrinkWrapWidth: true,
              trimTopMargin: true,
              trimBottomMargin: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchStatus extends StatelessWidget {
  const _SearchStatus({required this.icon, required this.text, this.action});

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
            Icon(
              icon,
              size: 54,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
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
