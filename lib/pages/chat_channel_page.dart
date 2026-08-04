import 'dart:async';
import 'dart:io';

import 'package:app_icons/app_icons.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo_render/fluxdo_render.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../constants.dart';
import '../l10n/s.dart';
import '../models/chat/chat_channel.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_message_search.dart';
import '../models/chat/gif.dart';
import '../models/topic.dart';
import '../providers/chat/chat_channel_list_provider.dart';
import '../providers/chat/chat_list_provider.dart';
import '../providers/core_providers.dart';
import '../services/app_error_handler.dart';
import '../services/emoji_handler.dart';
import '../services/preloaded_data_service.dart';
import '../services/toast_service.dart';
import '../utils/chat_composer_utils.dart';
import '../utils/cooked_content_utils.dart';
import '../utils/fluxdo_render_callbacks.dart';
import '../widgets/chat/chat_channel_icon.dart';
import '../widgets/chat/chat_message_action_sheet.dart';
import '../widgets/chat/chat_summary_sheet.dart';
import '../widgets/chat/gif_picker_sheet.dart';
import '../widgets/common/overlay/app_bottom_sheet.dart';
import '../widgets/common/visual/image_context_menu.dart';
import '../widgets/common/visual/smart_avatar.dart';
import '../widgets/content/discourse_html_content/image_utils.dart';
import '../widgets/markdown_editor/emoji_picker.dart';
import '../widgets/user/user_card.dart';
import 'chat_channel_details_page.dart';
import 'chat_threads_page.dart';

/// 单个聊天频道的消息流页面。
class ChatChannelPage extends ConsumerStatefulWidget {
  const ChatChannelPage({
    super.key,
    required this.channelId,
    this.title = '',
    this.channel,
    this.initialMessageId,
  });

  final int channelId;
  final String title;
  final ChatChannel? channel;

  /// 从搜索结果进入时，以该消息为锚点加载并定位。
  final int? initialMessageId;

  @override
  ConsumerState<ChatChannelPage> createState() => _ChatChannelPageState();
}

class _ChatChannelPageState extends ConsumerState<ChatChannelPage> {
  final AutoScrollController _scrollController = AutoScrollController();
  static const _channelSearchDebounceDuration = Duration(milliseconds: 350);
  static const _channelSearchPageSize = 40;

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final TextEditingController _channelSearchController =
      TextEditingController();
  final FocusNode _channelSearchFocusNode = FocusNode();
  TextSelection _lastInputSelection = const TextSelection.collapsed(offset: 0);
  Timer? _channelSearchDebounce;
  bool _channelSearchVisible = false;
  bool _channelSearchLoading = false;
  bool _channelSearchNavigating = false;
  List<ChatMessageSearchHit> _channelSearchHits = const [];
  int _channelSearchIndex = -1;
  int _channelSearchGeneration = 0;
  int _channelSearchNavigationGeneration = 0;
  int? _highlightedSearchMessageId;
  bool _sending = false;
  ChatChannel? _channel;
  bool _updatingStarred = false;
  final GlobalKey _historyAnchorKey = GlobalKey();
  int? _historyAnchorMessageId;
  bool _preservingHistoryAnchor = false;
  ChatMessage? _replyingToMessage;
  final Set<int> _selectedMessageIds = <int>{};

  bool get _selectionMode => _selectedMessageIds.isNotEmpty;

  /// 已上传、等待随下一条消息发送的附件。
  final List<_PendingChatAttachment> _pendingAttachments = [];

  /// 附件上传中：加号换转圈并禁用，避免并发上传
  bool _uploading = false;

  /// 整个频道共用一份渲染回调。FluxdoRender 用 identical() 判定渲染配置是否
  /// 变化，每次 build 新建会击穿它的块缓存，导致整列表逐帧重建。
  late final FluxdoRenderCallbacks _renderCallbacks =
      FluxdoRenderCallbacks.generic(
        heroTagNamespace: 'chat-${widget.channelId}',
      );

  /// cooked 解析产物缓存（消息 id → 解析结果）。气泡是 StatelessWidget，
  /// 滚动时反复 rebuild，不缓存就会反复解析 DOM。随页面一起销毁。
  final Map<int, _ParsedCooked> _parseCache = {};

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _inputController.addListener(_rememberInputSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadChannel());
      if (widget.initialMessageId != null) {
        unawaited(_loadInitialMessage());
      }
    });
  }

  Future<void> _loadChannel() async {
    // Creation and picker flows pass the authoritative channel response,
    // including direct-message participants. Do not replace it with a stale
    // channel-list entry that may not contain `chatable.users` yet.
    if (widget.channel != null) return;
    final channel = await ref
        .read(chatChannelListProvider.notifier)
        .channelById(widget.channelId);
    if (!mounted || channel == null) return;
    setState(() => _channel = channel);
  }

  Future<void> _toggleStarred() async {
    final channel = _channel;
    if (channel == null || _updatingStarred) return;

    final starred = !channel.isStarred;
    setState(() => _updatingStarred = true);
    try {
      final membership = await ref
          .read(discourseServiceProvider)
          .setChatChannelStarred(widget.channelId, starred: starred);
      if (!mounted) return;
      setState(() {
        _channel = channel.copyWith(currentUserMembership: membership);
      });
      unawaited(ref.read(chatChannelListProvider.notifier).refreshSilently());
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_starChannelFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingStarred = false);
    }
  }

  void _showMessageUserCard(BuildContext anchorContext, ChatMessageUser user) {
    if (user.username.trim().isEmpty) return;
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    showUserCard(
      context: anchorContext,
      anchorRect: box.localToGlobal(Offset.zero) & box.size,
      username: user.username,
      avatarFallbackUrl: user.avatarTemplate.isEmpty
          ? null
          : user.getAvatarUrl(size: 144),
      nameFallback: user.name,
      onStartChat: () => _startChatWithUser(user.username),
    );
  }

  Future<void> _startChatWithUser(String username) async {
    try {
      final channel = await ref
          .read(chatChannelListProvider.notifier)
          .createDirectMessageChannel([username]);
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
      if (mounted && channel.isDirectMessage) {
        await ref
            .read(chatChannelListProvider.notifier)
            .refreshUntilChannelVisible(channel.id);
      }
    } catch (_) {
      if (mounted) {
        ToastService.showError(context.l10n.chat_createDirectMessageFailed);
      }
    }
  }

  String get _channelTitle {
    final title = _channel?.title.trim();
    if (title?.isNotEmpty == true) return title!;
    if (widget.title.trim().isNotEmpty) return widget.title.trim();
    return '';
  }

  ChatMessageUser? get _directMessagePeer {
    final channel = _channel;
    if (channel == null || !channel.isDirectMessage) return null;
    final users = channel.directMessageUsers;
    return users.length == 1 ? users.first : null;
  }

  Future<void> _openChannelDetails() async {
    final channel = _channel;
    if (channel == null || !channel.isDirectMessage) return;

    final leftChannel = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatChannelDetailsPage(
          channel: channel,
          onChannelChanged: (updated) {
            if (mounted) setState(() => _channel = updated);
          },
        ),
      ),
    );
    if (leftChannel == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildAppBarIdentity(
    BuildContext context,
    ChatChannel? channel,
    String channelTitle,
  ) {
    final content = Row(
      children: [
        if (channel != null) ...[
          ChatChannelIcon(channel: channel, size: 28),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            channelTitle.isEmpty ? context.l10n.chat_title : channelTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (channel?.isDirectMessage != true) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('chat-channel-details-trigger'),
        onTap: _openChannelDetails,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: content,
        ),
      ),
    );
  }

  void _openChannelSearch() {
    if (!_channelSearchVisible) {
      setState(() => _channelSearchVisible = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _channelSearchFocusNode.requestFocus();
    });
  }

  void _closeChannelSearch() {
    _channelSearchDebounce?.cancel();
    _channelSearchGeneration++;
    _channelSearchNavigationGeneration++;
    _channelSearchController.clear();
    _channelSearchFocusNode.unfocus();
    setState(() {
      _channelSearchVisible = false;
      _channelSearchLoading = false;
      _channelSearchNavigating = false;
      _channelSearchHits = const [];
      _channelSearchIndex = -1;
      _highlightedSearchMessageId = null;
    });
  }

  void _onChannelSearchChanged(String value) {
    _queueChannelSearch(value, immediate: false);
  }

  void _onChannelSearchSubmitted(String value) {
    _queueChannelSearch(value, immediate: true);
  }

  void _queueChannelSearch(String value, {required bool immediate}) {
    _channelSearchDebounce?.cancel();
    final query = value.trim();
    final generation = ++_channelSearchGeneration;
    _channelSearchNavigationGeneration++;
    setState(() {
      _channelSearchLoading = false;
      _channelSearchNavigating = false;
      _channelSearchHits = const [];
      _channelSearchIndex = -1;
      _highlightedSearchMessageId = null;
    });
    if (query.isEmpty) return;

    if (immediate) {
      unawaited(_searchCurrentChannel(query, generation: generation));
    } else {
      _channelSearchDebounce = Timer(
        _channelSearchDebounceDuration,
        () => unawaited(_searchCurrentChannel(query, generation: generation)),
      );
    }
  }

  Future<void> _searchCurrentChannel(
    String query, {
    required int generation,
  }) async {
    if (!mounted || generation != _channelSearchGeneration) return;
    setState(() => _channelSearchLoading = true);

    try {
      var offset = 0;
      var hasMore = false;
      final hits = <ChatMessageSearchHit>[];
      final seenMessageIds = <int>{};

      do {
        final page = await ref
            .read(discourseServiceProvider)
            .searchChatMessages(
              query: query,
              sort: ChatMessageSearchSort.latest,
              offset: offset,
              limit: _channelSearchPageSize,
              channelId: widget.channelId,
            );
        if (!mounted || generation != _channelSearchGeneration) return;

        for (final hit in page.hits) {
          if (!hit.belongsToChannel(widget.channelId) ||
              !seenMessageIds.add(hit.message.id)) {
            continue;
          }
          hits.add(hit);
        }
        offset += page.hits.length;
        hasMore = page.hasMore && page.hits.isNotEmpty;
      } while (hasMore);

      // 频道消息按时间从旧到新编号，使上/下按钮和消息流方向一致。
      hits.sort((a, b) {
        final aTime = a.message.createdAt;
        final bTime = b.message.createdAt;
        if (aTime == null && bTime == null) {
          return a.message.id.compareTo(b.message.id);
        }
        if (aTime == null) return -1;
        if (bTime == null) return 1;
        final byTime = aTime.compareTo(bTime);
        return byTime != 0 ? byTime : a.message.id.compareTo(b.message.id);
      });

      setState(() {
        _channelSearchLoading = false;
        _channelSearchHits = hits;
        _channelSearchIndex = hits.isEmpty ? -1 : 0;
      });
      if (hits.isNotEmpty) {
        await _showChannelSearchResult(0);
      }
    } catch (_) {
      if (!mounted || generation != _channelSearchGeneration) return;
      setState(() {
        _channelSearchLoading = false;
        _channelSearchHits = const [];
        _channelSearchIndex = -1;
      });
      ToastService.showError(context.l10n.chat_searchFailed);
    }
  }

  Future<void> _showChannelSearchResult(int index) async {
    if (index < 0 || index >= _channelSearchHits.length) return;
    final navigationGeneration = ++_channelSearchNavigationGeneration;
    final messageId = _channelSearchHits[index].message.id;
    setState(() {
      _channelSearchIndex = index;
      _channelSearchNavigating = true;
      _highlightedSearchMessageId = messageId;
    });

    try {
      final provider = chatListProvider(widget.channelId);
      var state = ref.read(provider);
      var messageIndex = state.messages.indexWhere(
        (message) => message.id == messageId,
      );
      if (messageIndex < 0) {
        final found = await ref.read(provider.notifier).loadAround(messageId);
        if (!mounted ||
            navigationGeneration != _channelSearchNavigationGeneration) {
          return;
        }
        if (!found) {
          ToastService.showError(context.l10n.chat_searchFailed);
          return;
        }
        state = ref.read(provider);
        messageIndex = state.messages.indexWhere(
          (message) => message.id == messageId,
        );
      }
      if (messageIndex < 0) return;

      final reverseIndex = state.messages.length - 1 - messageIndex;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          navigationGeneration != _channelSearchNavigationGeneration) {
        return;
      }
      await _scrollController.scrollToIndex(
        reverseIndex,
        preferPosition: AutoScrollPosition.middle,
        duration: const Duration(milliseconds: 260),
      );
    } finally {
      if (mounted &&
          navigationGeneration == _channelSearchNavigationGeneration) {
        setState(() => _channelSearchNavigating = false);
      }
    }
  }

  void _openThreads() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadsPage(
          channelId: widget.channelId,
          channelTitle: _channelTitle,
        ),
      ),
    );
  }

  Future<void> _loadInitialMessage() async {
    final messageId = widget.initialMessageId;
    if (messageId == null || !mounted) return;
    final found = await ref
        .read(chatListProvider(widget.channelId).notifier)
        .loadAround(messageId);
    if (!mounted || !found) return;
    final state = ref.read(chatListProvider(widget.channelId));
    final anchorMessageIndex = state.anchorMessageIndex;
    if (anchorMessageIndex == null) return;

    // ListView 为 reverse，构建索引与状态中的升序索引方向相反。
    final reverseIndex = state.messages.length - 1 - anchorMessageIndex;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _scrollController.scrollToIndex(
      reverseIndex,
      preferPosition: AutoScrollPosition.middle,
      duration: const Duration(milliseconds: 260),
    );
  }

  void _rememberInputSelection() {
    final selection = _inputController.selection;
    if (selection.isValid) _lastInputSelection = selection;
  }

  @override
  void dispose() {
    _channelSearchDebounce?.cancel();
    _scrollController.dispose();
    _inputController.removeListener(_rememberInputSelection);
    _inputController.dispose();
    _inputFocusNode.dispose();
    _channelSearchController.dispose();
    _channelSearchFocusNode.dispose();
    _parseCache.clear();
    super.dispose();
  }

  /// 取一条消息的 cooked 解析结果；无 cooked（本地乐观消息）返回 null。
  _ParsedCooked? _parsedFor(ChatMessage msg) {
    final cooked = msg.cooked;
    if (cooked == null || cooked.trim().isEmpty) return null;
    // 编辑后 cooked 会变，用它做签名让缓存自然失效
    final signature = cooked.hashCode;
    final cached = _parseCache[msg.id];
    if (cached != null && cached.signature == signature) return cached;
    final nodes = ParagraphParser().parse(cooked);
    final parsed = _ParsedCooked(
      signature: signature,
      nodes: nodes,
      style: cookedBubbleStyleOf(nodes),
    );
    _parseCache[msg.id] = parsed;
    return parsed;
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    if (_selectionMode) {
      _toggleMessageSelection(message.id);
      return;
    }

    final currentUser = ref.read(currentUserProvider).value;
    final isMine = currentUser?.id == message.user.id;
    final result = await AppBottomSheet.show<ChatMessageActionResult>(
      context: context,
      showDragHandle: true,
      showCloseButton: false,
      contentPadding: EdgeInsets.zero,
      maxHeightFactor: 0.9,
      builder: (_) => ChatMessageActionSheet(
        message: message,
        canModerate: currentUser?.isStaff == true,
        canDelete: isMine || currentUser?.isStaff == true,
        canReport: !isMine && message.availableFlags.isNotEmpty,
      ),
    );
    if (result == null || !mounted) return;

    switch (result.action) {
      case ChatMessageAction.copyLink:
        await _copyMessageLink(message);
        break;
      case ChatMessageAction.copyText:
        await Clipboard.setData(ClipboardData(text: message.message));
        if (mounted) ToastService.showSuccess(context.l10n.chat_messageCopied);
        break;
      case ChatMessageAction.select:
        _toggleMessageSelection(message.id);
        break;
      case ChatMessageAction.pin:
        await _toggleMessagePinned(message);
        break;
      case ChatMessageAction.report:
        await _reportMessage(message);
        break;
      case ChatMessageAction.delete:
        await _deleteMessage(message);
        break;
      case ChatMessageAction.rebake:
        await _rebakeMessage(message);
        break;
      case ChatMessageAction.bookmark:
        await _toggleMessageBookmark(message);
        break;
      case ChatMessageAction.reply:
        setState(() => _replyingToMessage = message);
        _inputFocusNode.requestFocus();
        break;
      case ChatMessageAction.reaction:
        final emoji = result.emoji;
        if (emoji != null) await _toggleReaction(message, emoji);
        break;
      case ChatMessageAction.moreReactions:
        await _pickMessageReaction(message);
        break;
    }
  }

  Future<void> _copyMessageLink(ChatMessage message) async {
    final path = message.threadId == null
        ? '/chat/c/-/${widget.channelId}/${message.id}'
        : '/chat/c/-/${widget.channelId}/t/${message.threadId}/${message.id}';
    final base = AppConstants.baseUrl.replaceFirst(RegExp(r'/$'), '');
    await Clipboard.setData(ClipboardData(text: '$base$path'));
    if (mounted) ToastService.showSuccess(context.l10n.chat_messageLinkCopied);
  }

  void _toggleMessageSelection(int messageId) {
    setState(() {
      if (!_selectedMessageIds.add(messageId)) {
        _selectedMessageIds.remove(messageId);
      }
    });
  }

  void _clearMessageSelection() {
    if (_selectedMessageIds.isEmpty) return;
    setState(_selectedMessageIds.clear);
  }

  Future<void> _copySelectedMessages() async {
    final messages = ref
        .read(chatListProvider(widget.channelId))
        .messages
        .where((message) => _selectedMessageIds.contains(message.id))
        .map((message) => message.message.trim())
        .where((text) => text.isNotEmpty)
        .join('\n\n');
    if (messages.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: messages));
    if (!mounted) return;
    ToastService.showSuccess(context.l10n.chat_messageCopied);
    _clearMessageSelection();
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    ChatMessageReaction? existing;
    for (final reaction in message.reactions) {
      if (reaction.emoji == emoji) {
        existing = reaction;
        break;
      }
    }
    final add = !(existing?.reacted ?? false);
    try {
      await ref
          .read(discourseServiceProvider)
          .publishChatReaction(
            widget.channelId,
            message.id,
            emoji: emoji,
            add: add,
          );
      if (!mounted) return;
      final reactions = List<ChatMessageReaction>.of(message.reactions);
      final index = reactions.indexWhere((reaction) => reaction.emoji == emoji);
      if (index < 0) {
        if (add) {
          reactions.add(
            ChatMessageReaction(emoji: emoji, count: 1, reacted: true),
          );
        }
      } else {
        final nextCount = reactions[index].count + (add ? 1 : -1);
        if (nextCount <= 0) {
          reactions.removeAt(index);
        } else {
          reactions[index] = reactions[index].copyWith(
            count: nextCount,
            reacted: add,
          );
        }
      }
      ref
          .read(chatListProvider(widget.channelId).notifier)
          .updateMessage(message.copyWith(reactions: reactions));
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_messageActionFailed);
      }
    }
  }

  Future<void> _pickMessageReaction(ChatMessage message) async {
    final emoji = await AppBottomSheet.show<String>(
      context: context,
      title: context.l10n.chat_messageMoreReactions,
      maxHeightFactor: 0.82,
      contentPadding: EdgeInsets.zero,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.68,
        child: EmojiPicker(
          bottomPadding: 12,
          onEmojiSelected: (emoji) =>
              Navigator.of(sheetContext).pop(emoji.name),
        ),
      ),
    );
    if (emoji != null && mounted) await _toggleReaction(message, emoji);
  }

  Future<void> _toggleMessageBookmark(ChatMessage message) async {
    try {
      final service = ref.read(discourseServiceProvider);
      final updated = message.bookmarkId == null
          ? message.copyWith(
              bookmarkId: await service.bookmarkChatMessage(message.id),
            )
          : message.copyWith(clearBookmark: true);
      if (message.bookmarkId != null) {
        await service.deleteBookmark(message.bookmarkId!);
      }
      if (!mounted) return;
      ref
          .read(chatListProvider(widget.channelId).notifier)
          .updateMessage(updated);
      ToastService.showSuccess(
        message.bookmarkId == null
            ? context.l10n.chat_messageBookmarked
            : context.l10n.chat_messageBookmarkRemoved,
      );
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_messageActionFailed);
      }
    }
  }

  Future<void> _toggleMessagePinned(ChatMessage message) async {
    final pinned = !message.pinned;
    try {
      await ref
          .read(discourseServiceProvider)
          .setChatMessagePinned(widget.channelId, message.id, pinned: pinned);
      if (!mounted) return;
      ref
          .read(chatListProvider(widget.channelId).notifier)
          .updateMessage(message.copyWith(pinned: pinned));
      ToastService.showSuccess(
        pinned
            ? context.l10n.chat_messagePinned
            : context.l10n.chat_messageUnpinned,
      );
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_messageActionFailed);
      }
    }
  }

  Future<void> _rebakeMessage(ChatMessage message) async {
    try {
      await ref
          .read(discourseServiceProvider)
          .rebakeChatMessage(widget.channelId, message.id);
      if (mounted) ToastService.showSuccess(context.l10n.chat_messageRebaked);
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_messageActionFailed);
      }
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.chat_messageDelete),
        content: Text(dialogContext.l10n.chat_messageDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.chat_messageDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 确认框期间消息可能被 MessageBus 替换；以列表中的最新副本复核权限，
    // 避免把本地乐观消息或无权删除的他人消息提交给删除接口。
    final currentUser = ref.read(currentUserProvider).value;
    final currentMessages = ref
        .read(chatListProvider(widget.channelId))
        .messages;
    final currentMessage = currentMessages.where(
      (item) => item.id == message.id,
    );
    final target = currentMessage.isEmpty ? message : currentMessage.first;
    final canDelete =
        currentUser != null &&
        (target.user.id == currentUser.id || currentUser.isStaff);
    if (target.isLocal || target.isDeleted || !canDelete) {
      ToastService.showError(context.l10n.chat_messageActionFailed);
      return;
    }

    try {
      await ref
          .read(discourseServiceProvider)
          .deleteChatMessage(widget.channelId, message.id);
      if (!mounted) return;
      ref
          .read(chatListProvider(widget.channelId).notifier)
          .removeMessage(message.id);
      if (_replyingToMessage?.id == message.id ||
          _selectedMessageIds.contains(message.id) ||
          _highlightedSearchMessageId == message.id) {
        setState(() {
          if (_replyingToMessage?.id == message.id) {
            _replyingToMessage = null;
          }
          _selectedMessageIds.remove(message.id);
          if (_highlightedSearchMessageId == message.id) {
            _highlightedSearchMessageId = null;
          }
        });
      }
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_messageActionFailed);
      }
    }
  }

  Future<void> _reportMessage(ChatMessage message) async {
    final rawTypes = await PreloadedDataService().getPostActionTypes();
    if (!mounted) return;
    var types =
        (rawTypes ?? const <Map<String, dynamic>>[])
            .map(FlagType.fromJson)
            .where(
              (type) =>
                  type.isFlag &&
                  type.enabled &&
                  type.appliesTo.contains('Chat::Message') &&
                  message.availableFlags.contains(type.nameKey),
            )
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (types.isEmpty) {
      types = FlagType.defaultTypes
          .where((type) => message.availableFlags.contains(type.nameKey))
          .toList();
    }
    if (types.isEmpty) {
      ToastService.showError(context.l10n.chat_messageActionFailed);
      return;
    }

    await AppBottomSheet.show<void>(
      context: context,
      showCloseButton: false,
      contentPadding: EdgeInsets.zero,
      maxHeightFactor: 0.78,
      builder: (sheetContext) => _ChatMessageFlagSheet(
        message: message,
        types: types,
        onSubmit: (type, note) => ref
            .read(discourseServiceProvider)
            .flagChatMessage(
              widget.channelId,
              message.id,
              type.id,
              message: note,
            ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    final attachments = List<_PendingChatAttachment>.of(_pendingAttachments);
    if ((text.isEmpty && attachments.isEmpty) || _sending) return;

    final message = [
      if (text.isNotEmpty) text,
      ...attachments.map((attachment) => attachment.markdown),
    ].join('\n');

    setState(() => _sending = true);
    try {
      await ref
          .read(chatListProvider(widget.channelId).notifier)
          .send(message, inReplyTo: _replyingToMessage);
      if (!mounted) return;

      final channel = _channel;
      if (channel?.isDirectMessage == true) {
        // Discourse 在首条消息成功后发布并关注私聊频道。这里只重新读取
        // 服务端目录，不做本地 upsert，避免 App 显示网页端并不存在的会话。
        await ref
            .read(chatChannelListProvider.notifier)
            .refreshUntilChannelVisible(widget.channelId);
        if (!mounted) return;
      }

      _inputController.clear();
      setState(() {
        _pendingAttachments.removeWhere(attachments.contains);
        _replyingToMessage = null;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.chat_sendFailed)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  ({double revealOffset, double scrollOffset})?
  _captureHistoryAnchorPosition() {
    final anchorContext = _historyAnchorKey.currentContext;
    if (anchorContext == null || !_scrollController.hasClients) return null;

    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return null;

    return (
      revealOffset: viewport.getOffsetToReveal(renderObject, 0).offset,
      scrollOffset: _scrollController.position.pixels,
    );
  }

  Future<void> _loadMorePast() async {
    if (_preservingHistoryAnchor) return;

    final provider = chatListProvider(widget.channelId);
    final beforeState = ref.read(provider);
    if (beforeState.isLoading ||
        beforeState.isLoadingMore ||
        !beforeState.canLoadMorePast ||
        beforeState.messages.isEmpty) {
      return;
    }

    _preservingHistoryAnchor = true;
    final beforeCount = beforeState.messages.length;
    setState(() {
      _historyAnchorMessageId = beforeState.messages.first.id;
    });

    try {
      // 先让当前最老消息挂上锚点，再记录它在滚动视口中的实际位置。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final beforeAnchor = _captureHistoryAnchorPosition();

      await ref.read(provider.notifier).loadMorePast();
      if (!mounted) return;

      final afterCount = ref.read(provider).messages.length;
      if (afterCount <= beforeCount || beforeAnchor == null) return;

      // 等新历史完成布局，用同一条消息的实际 RenderBox 位置恢复视口。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      final afterAnchor = _captureHistoryAnchorPosition();
      if (afterAnchor == null) return;

      final position = _scrollController.position;
      final target =
          beforeAnchor.scrollOffset +
          afterAnchor.revealOffset -
          beforeAnchor.revealOffset;
      position.jumpTo(
        target
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    } finally {
      _preservingHistoryAnchor = false;
      if (mounted) {
        setState(() {
          _historyAnchorMessageId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatListProvider(widget.channelId));
    // 乐观消息被服务端 sent 事件替换后 isLocal 会变 false，得靠用户 id 认「自己」
    final currentUserId = ref.watch(currentUserProvider).value?.id;

    final channel = _channel;
    final channelTitle = _channelTitle;

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                onPressed: _clearMessageSelection,
                icon: const Icon(Icons.close_rounded),
              ),
              title: Text(
                context.l10n.chat_messageSelectedCount(
                  _selectedMessageIds.length,
                ),
              ),
              actions: [
                IconButton(
                  onPressed: _copySelectedMessages,
                  tooltip: context.l10n.chat_messageCopyText,
                  icon: const Icon(Icons.content_copy_rounded),
                ),
              ],
            )
          : AppBar(
              title: Row(
                children: [
                  Expanded(
                    child: _buildAppBarIdentity(context, channel, channelTitle),
                  ),
                  if (channel != null)
                    IconButton(
                      tooltip: channel.isStarred
                          ? context.l10n.chat_unstarChannel
                          : context.l10n.chat_starChannel,
                      onPressed: _updatingStarred ? null : _toggleStarred,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: _updatingStarred
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Symbols.star_rounded,
                              fill: channel.isStarred ? 1 : 0,
                            ),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: context.l10n.chat_searchTitle,
                  onPressed: _openChannelSearch,
                  icon: const Icon(Symbols.search_rounded),
                ),
                if (channel?.threadingEnabled == true)
                  IconButton(
                    tooltip: context.l10n.chat_threadsTitle,
                    onPressed: _openThreads,
                    icon: const Icon(Icons.tag_rounded),
                  ),
              ],
            ),
      body: Column(
        children: [
          if (_channelSearchVisible) _buildChannelSearchBar(context),
          Expanded(child: _buildMessages(context, state, currentUserId)),
          _buildInputArea(context),
        ],
      ),
    );
  }

  Widget _buildChannelSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final material = MaterialLocalizations.of(context);
    final hasResults = _channelSearchHits.isNotEmpty;
    final canGoPrevious =
        !_channelSearchLoading &&
        !_channelSearchNavigating &&
        hasResults &&
        _channelSearchIndex > 0;
    final canGoNext =
        !_channelSearchLoading &&
        !_channelSearchNavigating &&
        hasResults &&
        _channelSearchIndex < _channelSearchHits.length - 1;
    final resultLabel = hasResults
        ? '${_channelSearchIndex + 1} / ${_channelSearchHits.length}'
        : '0 / 0';

    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _channelSearchController,
                    focusNode: _channelSearchFocusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChannelSearchChanged,
                    onSubmitted: _onChannelSearchSubmitted,
                    decoration: InputDecoration(
                      hintText: context.l10n.chat_searchMessagesHint,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      suffixIcon: _channelSearchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: material.deleteButtonTooltip,
                              onPressed: () {
                                _channelSearchController.clear();
                                _onChannelSearchChanged('');
                                _channelSearchFocusNode.requestFocus();
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: Center(
                  child: _channelSearchLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          resultLabel,
                          maxLines: 1,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
              ),
              IconButton(
                tooltip: material.previousPageTooltip,
                onPressed: canGoPrevious
                    ? () => unawaited(
                        _showChannelSearchResult(_channelSearchIndex - 1),
                      )
                    : null,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                tooltip: material.nextPageTooltip,
                onPressed: canGoNext
                    ? () => unawaited(
                        _showChannelSearchResult(_channelSearchIndex + 1),
                      )
                    : null,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              TextButton(
                onPressed: _closeChannelSearch,
                child: Text(context.l10n.common_done),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(
    BuildContext context,
    ChatListState state,
    int? currentUserId,
  ) {
    final channel = _channel;
    // 新建私聊没有历史消息时，空状态本身就是可交互的首屏；不要让一次
    // 历史请求（例如认证刷新或网络重试）把输入框和页面永久挡在 spinner 后面。
    if (state.isLoading &&
        state.messages.isEmpty &&
        channel?.isDirectMessage == true &&
        channel?.lastMessage == null) {
      return _buildDirectMessageEmptyState(context, channel!);
    }
    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '${state.error}',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.read(chatListProvider(widget.channelId).notifier).retry(),
              child: Text(context.l10n.chat_retry),
            ),
          ],
        ),
      );
    }
    if (state.messages.isEmpty) {
      if (channel?.isDirectMessage == true) {
        return _buildDirectMessageEmptyState(context, channel!);
      }
      return Center(
        child: Text(
          context.l10n.chat_channelMessagesEmpty,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    final messages = state.messages;
    return ListView.builder(
      controller: _scrollController,
      // reverse: 底部对齐，新消息贴近可视区底部
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == messages.length) {
          // 顶部：历史加载入口（reverse 后 index 最大即列表顶部）
          return _LoadMorePastFooter(
            canLoadMore: state.canLoadMorePast,
            isLoading: state.isLoadingMore,
            onTap: _loadMorePast,
          );
        }
        // reverse 下 index 0 = 最新一条（列表末尾）
        final msg = messages[messages.length - 1 - index];
        final isInitialMessage = msg.id == widget.initialMessageId;
        return AutoScrollTag(
          key: ValueKey('chat-message-${msg.id}'),
          controller: _scrollController,
          index: index,
          builder: (context, animation) => _MessageBubble(
            key: msg.id == _historyAnchorMessageId ? _historyAnchorKey : null,
            message: msg,
            parsed: _parsedFor(msg),
            renderCallbacks: _renderCallbacks,
            currentUserId: currentUserId,
            highlighted:
                isInitialMessage || msg.id == _highlightedSearchMessageId,
            selected: _selectedMessageIds.contains(msg.id),
            onTap: _selectionMode
                ? () => _toggleMessageSelection(msg.id)
                : null,
            onLongPress: () => _showMessageActions(msg),
            onReactionTap: (emoji) => _toggleReaction(msg, emoji),
            onUserTap: _showMessageUserCard,
            onImageMarkAd:
                currentUserId != null &&
                    currentUserId != msg.user.id &&
                    msg.availableFlags.isNotEmpty
                ? () => _reportMessage(msg)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildDirectMessageEmptyState(
    BuildContext context,
    ChatChannel channel,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final users = channel.directMessageUsers;
    final title = _channelTitle;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_rounded,
              size: 64,
              color: colorScheme.onSurface,
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.chat_directMessageFirstUser(title),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.chat_directMessageStart,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (users.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.fromLTRB(6, 5, 14, 5),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChatChannelIcon(channel: channel, size: 32),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.chat_directMessageUsersHere(users.length),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final directMessagePeer = _directMessagePeer;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.7),
      ),
    );

    return SafeArea(
      top: false,
      child: ColoredBox(
        color: colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_replyingToMessage case final reply?) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(color: colorScheme.primary, width: 3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.chat_messageReplyingTo(
                                reply.user.displayName,
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              (reply.excerpt ?? reply.message).trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _replyingToMessage = null),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildComposerMenu(context, theme),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocusNode,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: directMessagePeer != null
                            ? context.l10n.chat_directMessageInputHint(
                                directMessagePeer.username,
                              )
                            : context.l10n.chat_messageInputHint,
                        hintStyle: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.72,
                          ),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        focusedBorder: inputBorder.copyWith(
                          borderSide: BorderSide(
                            color: colorScheme.primary.withValues(alpha: 0.7),
                            width: 1.25,
                          ),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLowest,
                        hoverColor: Colors.transparent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _inputController,
                    builder: (context, value, _) {
                      final canSend =
                          (value.text.trim().isNotEmpty ||
                              _pendingAttachments.isNotEmpty) &&
                          !_sending;
                      return IconButton(
                        onPressed: canSend ? _send : null,
                        tooltip: context.l10n.chat_send,
                        icon: const Icon(Icons.send_rounded, size: 22),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(40, 40),
                          maximumSize: const Size(40, 40),
                          padding: EdgeInsets.zero,
                          backgroundColor: canSend
                              ? colorScheme.primary
                              : Colors.transparent,
                          foregroundColor: colorScheme.onPrimary,
                          disabledForegroundColor: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.48),
                        ),
                      );
                    },
                  ),
                ],
              ),
              if (_pendingAttachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: _pendingAttachments.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final attachment = _pendingAttachments[index];
                      return _PendingAttachmentPreview(
                        attachment: attachment,
                        onRemove: _sending
                            ? null
                            : () {
                                setState(() {
                                  _pendingAttachments.removeAt(index);
                                });
                              },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── 输入框左侧的「+」菜单 ────────────────────────────────────────

  /// 加号按钮。上传中换成转圈并禁用，避免并发上传。
  Widget _buildComposerMenu(BuildContext context, ThemeData theme) {
    final button = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: _uploading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Symbols.add_rounded,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
            ),
    );

    if (_uploading) {
      return Tooltip(message: context.l10n.chat_uploading, child: button);
    }

    return PopupMenuButton<_ComposerAction>(
      tooltip: context.l10n.chat_moreActions,
      // 输入框贴着屏幕底部，菜单会自动向上弹
      position: PopupMenuPosition.over,
      offset: const Offset(0, -12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: _onComposerAction,
      itemBuilder: (context) => [
        _composerMenuItem(
          value: _ComposerAction.insertEmoji,
          icon: Symbols.emoji_emotions_rounded,
          label: context.l10n.chat_insertEmoji,
        ),
        _composerMenuItem(
          value: _ComposerAction.attachFile,
          icon: Symbols.image_rounded,
          label: context.l10n.chat_attachFile,
        ),
        _composerMenuItem(
          value: _ComposerAction.insertGif,
          icon: Symbols.gif_box_rounded,
          label: context.l10n.chat_insertGif,
        ),
        _composerMenuItem(
          value: _ComposerAction.summarize,
          icon: Symbols.auto_awesome_rounded,
          label: context.l10n.chat_summarize,
        ),
      ],
      child: button,
    );
  }

  PopupMenuItem<_ComposerAction> _composerMenuItem({
    required _ComposerAction value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<_ComposerAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  void _onComposerAction(_ComposerAction action) {
    switch (action) {
      case _ComposerAction.insertEmoji:
        unawaited(_pickEmoji());
      case _ComposerAction.attachFile:
        unawaited(_pickAndAttachFile());
      case _ComposerAction.insertGif:
        unawaited(_pickGif());
      case _ComposerAction.summarize:
        unawaited(_summarize());
    }
  }

  // ─── 插入表情符号 ────────────────────────────────────────────────

  Future<void> _pickEmoji() async {
    // PopupMenu 和 BottomSheet 会让输入框失焦，提前保存选区才能稳定插入到
    // 用户打开菜单前的光标位置。
    final selection = _lastInputSelection;
    final shortcode = await AppBottomSheet.show<String>(
      context: context,
      title: context.l10n.chat_insertEmoji,
      contentPadding: EdgeInsets.zero,
      showTitleDivider: true,
      maxHeightFactor: 0.82,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.68,
        child: EmojiPicker(
          bottomPadding: 16,
          onEmojiSelected: (emoji) {
            Navigator.of(sheetContext).pop(':${emoji.name}:');
          },
        ),
      ),
    );
    if (shortcode == null || !mounted) return;

    _inputController.value = insertChatComposerText(
      _inputController.value,
      shortcode,
      selection: selection,
    );
    _inputFocusNode.requestFocus();
  }

  /// 把文本插入输入框光标处（GIF 等文本型内容走这里）。
  void _insertIntoInput(String text) {
    final current = _inputController.text;
    final selection = _inputController.selection.isValid
        ? _inputController.selection
        : _lastInputSelection;
    final start = selection.isValid ? selection.start : current.length;
    final end = selection.isValid ? selection.end : current.length;
    // 前面有内容且不在行首时补个换行，别和已有文字挤在一行
    final needsLeadingNewline = start > 0 && current[start - 1] != '\n';
    final insert = '${needsLeadingNewline ? '\n' : ''}$text\n';
    _inputController.value = TextEditingValue(
      text: current.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
  }

  // ─── 附加文件 ────────────────────────────────────────────────────

  Future<void> _pickAndAttachFile() async {
    final picked = await FilePicker.platform.pickFiles();
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final result = await ref.read(discourseServiceProvider).uploadFile(path);
      // 播种短链 → 真实 URL，插入后立刻能渲染出图，不用等服务端解析
      final url = result.url;
      if (url != null) {
        DiscourseImageUtils.seedUploadUrl(result.shortUrl, url);
      }
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(
          _PendingChatAttachment(
            markdown: result.toAutoMarkdown(),
            fileName: result.originalFilename,
            localPath: path,
            previewUrl: result.url,
            fileSizeLabel: result.humanFilesize,
            isImage: result.isImage,
          ),
        );
      });
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 弹 toast
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
      if (mounted) ToastService.showError(context.l10n.chat_uploadFailed);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ─── 插入 GIF ────────────────────────────────────────────────────

  Future<void> _pickGif() async {
    final theme = Theme.of(context);
    final gif = await AppBottomSheet.show<GifItem>(
      context: context,
      titleWidget: Text(
        context.l10n.chat_gifSearchHint,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        Builder(
          builder: (sheetContext) => IconButton(
            onPressed: () => Navigator.of(sheetContext).maybePop(),
            tooltip: MaterialLocalizations.of(
              sheetContext,
            ).modalBarrierDismissLabel,
            icon: const Icon(Symbols.close_rounded, size: 30),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ),
      ],
      showCloseButton: false,
      showDragHandle: false,
      showTitleDivider: true,
      contentPadding: EdgeInsets.zero,
      maxHeightFactor: 0.95,
      builder: (_) => const GifPickerSheet(),
    );
    if (gif == null || !mounted) return;
    _insertIntoInput(gif.toMarkdown());
  }

  // ─── 总结消息 ────────────────────────────────────────────────────

  static const _summaryRangeHours = [1, 3, 6, 12, 24];

  Future<void> _summarize() async {
    final hours = await AppBottomSheet.show<int>(
      context: context,
      title: context.l10n.chat_summarizeRangeTitle,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final h in _summaryRangeHours)
            ListTile(
              leading: const Icon(Symbols.schedule_rounded),
              title: Text(sheetContext.l10n.chat_summarizeRangeHours(h)),
              onTap: () => Navigator.pop(sheetContext, h),
            ),
        ],
      ),
    );
    if (hours == null || !mounted) return;

    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final notifier = ref.read(chatListProvider(widget.channelId).notifier);

    // 时间窗可能没被本地已加载的消息覆盖，先补历史（内部有上限）
    final collected = await notifier.collectSince(cutoff);
    if (!mounted) return;

    if (collected.messages.isEmpty) {
      ToastService.showInfo(context.l10n.chat_summarizeEmpty);
      return;
    }

    await AppBottomSheet.show<void>(
      context: context,
      title: context.l10n.chat_summarizeTitle,
      builder: (_) => ChatSummarySheet(
        channelTitle: widget.title.isEmpty
            ? context.l10n.chat_title
            : widget.title,
        hours: hours,
        messages: collected.messages,
        truncated: collected.truncated,
      ),
    );
  }
}

class _ChatMessageFlagSheet extends StatefulWidget {
  const _ChatMessageFlagSheet({
    required this.message,
    required this.types,
    required this.onSubmit,
  });

  final ChatMessage message;
  final List<FlagType> types;
  final Future<void> Function(FlagType type, String? note) onSubmit;

  @override
  State<_ChatMessageFlagSheet> createState() => _ChatMessageFlagSheetState();
}

class _ChatMessageFlagSheetState extends State<_ChatMessageFlagSheet> {
  final TextEditingController _noteController = TextEditingController();
  FlagType? _selected;
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null || _submitting) return;
    final note = _noteController.text.trim();
    if (selected.requireMessage && note.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(selected, note.isEmpty ? null : note);
      if (!mounted) return;
      Navigator.of(context).pop();
      ToastService.showSuccess(context.l10n.chat_messageReported);
    } catch (error, stackTrace) {
      AppErrorHandler.handleUnexpected(error, stackTrace);
      if (mounted) {
        ToastService.showError(context.l10n.chat_messageActionFailed);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Icon(Icons.flag_rounded, color: theme.colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.chat_messageReport,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  for (final type in widget.types)
                    ListTile(
                      selected: identical(type, _selected),
                      leading: Icon(
                        identical(type, _selected)
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                      ),
                      onTap: () => setState(() => _selected = type),
                      title: Text(type.name),
                      subtitle: type.description.trim().isEmpty
                          ? null
                          : Text(
                              type.description
                                  .replaceAll(
                                    '%{username}',
                                    widget.message.user.username,
                                  )
                                  .replaceAll(
                                    '@%{username}',
                                    '@${widget.message.user.username}',
                                  ),
                            ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.l10n.chat_messageReportNote,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _selected == null ||
                        _submitting ||
                        (_selected!.requireMessage &&
                            _noteController.text.trim().isEmpty)
                    ? null
                    : _submit,
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.l10n.post_submitFlag),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingChatAttachment {
  final String markdown;
  final String fileName;
  final String localPath;
  final String? previewUrl;
  final String? fileSizeLabel;
  final bool isImage;

  const _PendingChatAttachment({
    required this.markdown,
    required this.fileName,
    required this.localPath,
    required this.previewUrl,
    required this.fileSizeLabel,
    required this.isImage,
  });
}

class _PendingAttachmentPreview extends StatelessWidget {
  final _PendingChatAttachment attachment;
  final VoidCallback? onRemove;

  const _PendingAttachmentPreview({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final width = attachment.isImage ? 108.0 : 208.0;
    return SizedBox(
      width: width,
      height: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 8,
            child: attachment.isImage
                ? _buildImagePreview(context)
                : _buildFilePreview(context),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Material(
              color: Colors.black87,
              shape: CircleBorder(
                side: BorderSide(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.close_rounded,
                    size: 24,
                    color: onRemove == null ? Colors.white38 : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 100,
      height: 100,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.85),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(attachment.localPath),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildImageFallback(context),
        ),
      ),
    );
  }

  Widget _buildImageFallback(BuildContext context) {
    final previewUrl = attachment.previewUrl;
    if (previewUrl != null && previewUrl.isNotEmpty) {
      return Image.network(
        previewUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFileIcon(context),
      );
    }
    return _buildFileIcon(context);
  }

  Widget _buildFilePreview(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      height: 72,
      padding: const EdgeInsets.fromLTRB(14, 10, 38, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          _buildFileIcon(context),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (attachment.fileSizeLabel case final size?) ...[
                  const SizedBox(height: 2),
                  Text(
                    size,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Icon(
          Symbols.description_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 「+」菜单里的动作
enum _ComposerAction { insertEmoji, attachFile, insertGif, summarize }

class _LoadMorePastFooter extends StatelessWidget {
  final bool canLoadMore;
  final bool isLoading;
  final VoidCallback onTap;

  const _LoadMorePastFooter({
    required this.canLoadMore,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!canLoadMore) {
      return const SizedBox(height: 4);
    }
    return InkWell(
      onTap: isLoading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.chat_loadMore),
        ),
      ),
    );
  }
}

/// 一条消息的 cooked 解析产物。既决定气泡形态，也直接喂给 FluxdoRender，
/// 免得渲染时再解析一遍同样的 HTML。
class _ParsedCooked {
  final int signature;
  final List<BlockNode> nodes;

  /// 该用哪种外框
  final CookedBubbleStyle style;

  const _ParsedCooked({
    required this.signature,
    required this.nodes,
    required this.style,
  });
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// cooked 解析结果；本地乐观消息还没有 cooked 时为 null。
  final _ParsedCooked? parsed;

  final FluxdoRenderCallbacks renderCallbacks;

  /// 当前登录用户 id；未登录/未加载完为 null。
  final int? currentUserId;
  final bool highlighted;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onReactionTap;
  final void Function(BuildContext anchorContext, ChatMessageUser user)?
  onUserTap;
  final VoidCallback? onImageMarkAd;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.parsed,
    required this.renderCallbacks,
    required this.currentUserId,
    this.highlighted = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onReactionTap,
    this.onUserTap,
    this.onImageMarkAd,
  });

  /// 自己发的：本地乐观消息，或作者就是当前用户。
  /// 不能只看 isLocal —— 乐观消息被服务端 sent 事件替换后它就变 false 了。
  bool get _isMine =>
      message.isLocal ||
      (currentUserId != null && message.user.id == currentUserId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = _isMine;
    final content = _buildMessageContent(context, theme, isMine);
    final avatar = _buildAvatar(context, theme);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: ColoredBox(
        color: selected
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.72)
            : highlighted
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.42)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: isMine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selected) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 8),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
              ],
              if (isMine) ...[
                Flexible(child: content),
                const SizedBox(width: 8),
                avatar,
              ] else ...[
                avatar,
                const SizedBox(width: 8),
                Flexible(child: content),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent(
    BuildContext context,
    ThemeData theme,
    bool isMine,
  ) {
    final style = parsed?.style ?? CookedBubbleStyle.bubble;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        _buildMessageMeta(context, theme, isMine),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          child: switch (style) {
            // 纯图片：去掉底色和内边距，只把图片本身切个圆角
            CookedBubbleStyle.image => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildBody(context, theme),
            ),
            // 纯 emoji：直接裸出。不切圆角，否则会啃掉 only-emoji 大图的边角
            CookedBubbleStyle.emoji => _buildBody(context, theme),
            CookedBubbleStyle.bubble => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMine
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _buildBody(context, theme),
            ),
          },
        ),
        if (message.reactions.isNotEmpty) ...[
          const SizedBox(height: 5),
          Wrap(
            alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
            spacing: 5,
            runSpacing: 4,
            children: [
              for (final reaction in message.reactions)
                _buildReactionChip(theme, reaction),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildReactionChip(ThemeData theme, ChatMessageReaction reaction) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onReactionTap == null
          ? null
          : () => onReactionTap!(reaction.emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: reaction.reacted
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: reaction.reacted
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              EmojiHandler().getEmojiUrl(reaction.emoji),
              width: 18,
              height: 18,
              errorBuilder: (_, _, _) => Text(':${reaction.emoji}:'),
            ),
            const SizedBox(width: 4),
            Text('${reaction.count}', style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageMeta(BuildContext context, ThemeData theme, bool isMine) {
    final displayName = message.user.displayName.trim();
    final createdAt = message.createdAt;
    final timeText = createdAt == null
        ? ''
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(createdAt),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );

    if (displayName.isEmpty && timeText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.pinned) ...[
            Icon(
              Icons.push_pin_rounded,
              size: 13,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
          ],
          if (displayName.isNotEmpty)
            Builder(
              builder: (anchorContext) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUserTap == null
                    ? null
                    : () => onUserTap!(anchorContext, message.user),
                child: Text(
                  displayName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isMine
                        ? theme.colorScheme.primary
                        : theme.colorScheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (displayName.isNotEmpty && timeText.isNotEmpty)
            const SizedBox(width: 6),
          if (timeText.isNotEmpty)
            Text(
              timeText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.68,
                ),
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, ThemeData theme) {
    final avatarUrl = message.user.avatarTemplate.isEmpty
        ? null
        : message.user.getAvatarUrl(size: 64);
    return Builder(
      builder: (anchorContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onUserTap == null
            ? null
            : () => onUserTap!(anchorContext, message.user),
        child: SmartAvatar(
          imageUrl: avatarUrl,
          radius: 16,
          fallbackText: message.user.displayName,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }

  /// 正文：服务端 cook 过就走富文本（图片 / 链接 / emoji / 代码块等都靠它），
  /// 只有本地乐观消息还没拿到 cooked 时才退回纯文本。
  Widget _buildBody(BuildContext context, ThemeData theme) {
    final parsed = this.parsed;
    if (parsed == null) {
      return Text(message.message, style: theme.textTheme.bodyMedium);
    }
    return ImageContextMenuScope(
      presentation: ImageContextMenuPresentation.compactFloating,
      onMarkAd: onImageMarkAd,
      child: renderCallbacks.render(
        cookedHtml: message.cooked!,
        parsedNodes: parsed.nodes,
        baseTextStyle: theme.textTheme.bodyMedium,
        selectionEnabled: false,
        // 紧凑模式：去掉段落外边距，免得气泡内上下多出一圈空白
        compact: true,
        // 短消息按内容宽度收缩，保持贴近头像；长内容仍受气泡最大宽度限制
        shrinkWrapWidth: true,
      ),
    );
  }
}
