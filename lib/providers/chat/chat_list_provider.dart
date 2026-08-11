import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/chat/chat_message.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/message_bus_service.dart';
import '../core_providers.dart';
import '../message_bus/message_bus_service_provider.dart';
import '../message_bus/topic_tracking_providers.dart';

/// 单个聊天频道的消息列表状态
class ChatListState {
  /// 按时间升序（旧 → 新）排列的消息
  final List<ChatMessage> messages;

  /// 是否还能向前加载更多历史（direction=past）
  final bool canLoadMorePast;

  /// 是否还能向后加载更新的消息（direction=future）
  final bool canLoadMoreFuture;

  /// 频道名（AppBar 标题）
  final String title;

  /// `loadAround` 返回结果中锚点消息在 [messages]（旧 → 新）里的索引。
  final int? anchorMessageIndex;

  /// 加载状态
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  const ChatListState({
    this.messages = const [],
    this.canLoadMorePast = false,
    this.canLoadMoreFuture = false,
    this.title = '',
    this.anchorMessageIndex,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  ChatListState copyWith({
    List<ChatMessage>? messages,
    bool? canLoadMorePast,
    bool? canLoadMoreFuture,
    String? title,
    int? anchorMessageIndex,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return ChatListState(
      messages: messages ?? this.messages,
      canLoadMorePast: canLoadMorePast ?? this.canLoadMorePast,
      canLoadMoreFuture: canLoadMoreFuture ?? this.canLoadMoreFuture,
      title: title ?? this.title,
      anchorMessageIndex: anchorMessageIndex ?? this.anchorMessageIndex,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : error ?? this.error,
    );
  }

  ChatListState copyWithError(Object e) {
    return copyWith(error: e, isLoading: false, isLoadingMore: false);
  }
}

/// 单个聊天频道的实时消息 Notifier
///
/// 复用 `topic_channel_provider` 的骨架：进入 build 先确保 MessageBus 已
/// configure，随后按频道名订阅 `/chat/{id}` 与 `/chat/{id}/new-messages`，
/// 并把 MessageBus 推送的新消息/变更通过 microtask 攒批后并入消息列表，
/// 避免积压回放时逐条 rebuild。
class ChatListNotifier extends Notifier<ChatListState> {
  ChatListNotifier(this.channelId);
  final int channelId;

  String? _rootChannel;
  MessageBusCallback? _rootCallback;

  bool _disposed = false;
  bool _flushScheduled = false;
  int _loadGeneration = 0;
  int _lastReadMessageId = 0;
  int? _pendingReadMessageId;
  Future<void>? _readReportInFlight;

  /// 待并入的新消息/编辑；value 为该消息对应的本地暂存 id（仅 sent 事件有）
  final List<_IncomingMessage> _pendingIncoming = [];
  // 只带 cook 结果的 processed 事件，按 id 合并进已有消息
  final List<ChatMessage> _pendingProcessed = [];
  // 记录该批次里已删除的消息 id，避免逐条处理
  final List<int> _pendingDeleted = [];

  @override
  ChatListState build() {
    _disposed = false;
    ref.watch(messageBusInitProvider);
    final messageBus = ref.watch(messageBusServiceProvider);
    final service = ref.read(discourseServiceProvider);

    _rootChannel = '/chat/$channelId';

    // 消息流事件全部走根频道 `/chat/{id}`（对齐网页端
    // chat-channel-subscription-manager）。`/chat/{id}/new-messages` 推的是
    // `type: "channel" | "thread"` 的频道未读跟踪报文，不含消息流，这里不订阅。
    void onRootMessage(MessageBusMessage message) {
      final data = message.data;
      if (data is! Map<String, dynamic>) return;

      switch (data['type'] as String?) {
        // 新消息落库。自己发的会带 staged_id，用它把本地乐观消息就地升级。
        case 'sent':
          final chatMsg = ChatMessage.fromMessageBusData(data);
          if (chatMsg != null) {
            _enqueueIncoming(chatMsg, stagedId: _parseStagedId(data));
          }
          break;
        // cook 完成：只带回 cooked/uploads，合并进已有消息而非整条替换
        case 'processed':
          final chatMsg = ChatMessage.fromMessageBusData(data);
          if (chatMsg != null) _enqueueProcessed(chatMsg);
          break;
        case 'edit':
        case 'restore':
          final chatMsg = ChatMessage.fromMessageBusData(data);
          if (chatMsg != null) _enqueueIncoming(chatMsg);
          break;
        case 'delete':
          final deletedId = data['deleted_id'] as int?;
          if (deletedId != null) _enqueueDeleted(deletedId);
          break;
        case 'bulk_delete':
          final ids = data['deleted_ids'];
          if (ids is List) {
            for (final id in ids.whereType<int>()) {
              _enqueueDeleted(id);
            }
          }
          break;
        default:
          break;
      }
    }

    messageBus.subscribe(_rootChannel!, onRootMessage);
    _rootCallback = onRootMessage;

    ref.onDispose(() {
      _disposed = true;
      _flushScheduled = false;
      _pendingIncoming.clear();
      _pendingProcessed.clear();
      _pendingDeleted.clear();
      _pendingReadMessageId = null;
      if (_rootChannel != null && _rootCallback != null) {
        messageBus.unsubscribe(_rootChannel!, _rootCallback);
      }
      _rootChannel = null;
      _rootCallback = null;
    });

    // 初始加载最近消息
    _loadInitial(service, generation: ++_loadGeneration);

    return const ChatListState();
  }

  Future<void> _loadInitial(
    DiscourseService service, {
    required int generation,
  }) async {
    try {
      final page = await service.getChatMessages(
        channelId,
        pageSize: 50,
        fetchFromLastRead: true,
      );
      if (_disposed || generation != _loadGeneration) return;
      final sorted = _sortedAsc(page.messages);
      state = ChatListState(
        messages: sorted,
        canLoadMorePast: page.canLoadMorePast,
        canLoadMoreFuture: page.canLoadMoreFuture,
        isLoading: false,
      );
      // 上报已读
      if (sorted.isNotEmpty) {
        unawaited(markReadThrough(sorted.last.id));
      }
    } catch (e) {
      if (_disposed || generation != _loadGeneration) return;
      state = state.copyWithError(e);
    }
  }

  /// 重新加载（错误重试）
  Future<void> retry() async {
    final service = ref.read(discourseServiceProvider);
    state = const ChatListState();
    await _loadInitial(service, generation: ++_loadGeneration);
  }

  /// 将频道已读游标推进到 [messageId]。
  ///
  /// 同一时刻只发送一个请求；并发到达的更新会合并为最大的消息 id，避免实时
  /// 消息密集到达时逐条请求。失败的游标会保留，下一次可见性触发时重试。
  Future<void> markReadThrough(int messageId) async {
    if (_disposed || messageId <= _lastReadMessageId) return;

    final pending = _pendingReadMessageId;
    if (pending == null || messageId > pending) {
      _pendingReadMessageId = messageId;
    }

    final inFlight = _readReportInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final report = _drainReadReports();
    _readReportInFlight = report;
    try {
      await report;
    } finally {
      if (identical(_readReportInFlight, report)) {
        _readReportInFlight = null;
      }
    }
  }

  Future<void> _drainReadReports() async {
    final service = ref.read(discourseServiceProvider);
    while (!_disposed) {
      final messageId = _pendingReadMessageId;
      if (messageId == null || messageId <= _lastReadMessageId) return;
      _pendingReadMessageId = null;

      try {
        await service.markChatChannelRead(channelId, messageId);
      } catch (_) {
        if (!_disposed && messageId > (_pendingReadMessageId ?? 0)) {
          _pendingReadMessageId = messageId;
        }
        return;
      }

      if (_disposed) return;
      _lastReadMessageId = messageId;
    }
  }

  /// 以指定消息为锚点加载其前后消息，供搜索结果跳转。
  Future<bool> loadAround(int messageId) async {
    final generation = ++_loadGeneration;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
    );
    try {
      final page = await ref
          .read(discourseServiceProvider)
          .getChatMessages(channelId, pageSize: 50, targetMessageId: messageId);
      if (_disposed || generation != _loadGeneration) return false;
      final sorted = _sortedAsc(page.messages);
      final anchorMessageIndex = sorted.indexWhere(
        (message) => message.id == messageId,
      );
      state = ChatListState(
        messages: sorted,
        canLoadMorePast: page.canLoadMorePast,
        canLoadMoreFuture: page.canLoadMoreFuture,
        anchorMessageIndex: anchorMessageIndex < 0 ? null : anchorMessageIndex,
        isLoading: false,
      );
      return anchorMessageIndex >= 0;
    } catch (e) {
      if (_disposed || generation != _loadGeneration) {
        return false;
      }
      state = state.copyWithError(e);
      return false;
    }
  }

  /// 加载更早的历史消息（向上滚动触底）
  Future<void> loadMorePast() async {
    if (state.isLoading || state.isLoadingMore || !state.canLoadMorePast) {
      return;
    }
    final messages = state.messages;
    if (messages.isEmpty) return;
    final oldestId = messages.first.id;
    state = state.copyWith(isLoadingMore: true);
    try {
      final service = ref.read(discourseServiceProvider);
      final page = await service.getChatMessages(
        channelId,
        pageSize: 50,
        direction: 'past',
        targetMessageId: oldestId,
      );
      if (_disposed) return;
      final newMessages = page.messages.where((m) => m.id < oldestId).toList();
      state = state.copyWith(
        messages: [...newMessages, ...messages],
        canLoadMorePast: page.canLoadMorePast,
        isLoadingMore: false,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// 发送一条消息；乐观加入列表（用负 ID 暂存），服务端 `sent` 事件带回同一个
  /// staged_id 后就地升级为正式消息。
  Future<void> send(String text, {ChatMessage? inReplyTo}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final stagedId = _nextStagedId();
    final optimistic = ChatMessage(
      id: stagedId,
      message: trimmed,
      cooked: null,
      createdAt: DateTime.now(),
      chatChannelId: channelId,
      user: ChatMessageUser(id: -1, username: ''),
      inReplyTo: inReplyTo == null
          ? null
          : ChatMessageReplyTo(
              id: inReplyTo.id,
              excerpt: inReplyTo.excerpt ?? inReplyTo.message,
              user: inReplyTo.user,
            ),
      isLocal: true,
    );
    state = state.copyWith(messages: [...state.messages, optimistic]);
    try {
      await ref
          .read(discourseServiceProvider)
          .sendChatMessage(
            channelId,
            message: trimmed,
            stagedId: '$stagedId',
            inReplyToId: inReplyTo?.id,
          );
    } catch (_) {
      // 发送失败：移出乐观消息，交由上层 toast 提示
      if (_disposed) return;
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != stagedId).toList(),
      );
      rethrow;
    }
  }

  /// 用服务端操作结果即时更新单条消息，MessageBus 后续事件仍可覆盖它。
  void updateMessage(ChatMessage message) {
    if (_disposed) return;
    final index = state.messages.indexWhere((item) => item.id == message.id);
    if (index < 0) return;
    final messages = List<ChatMessage>.of(state.messages);
    messages[index] = message;
    state = state.copyWith(messages: messages);
  }

  void removeMessage(int messageId) {
    if (_disposed) return;
    state = state.copyWith(
      messages: state.messages
          .where((message) => message.id != messageId)
          .toList(),
    );
  }

  /// 收集 [cutoff] 之后的消息，供「总结消息」用。
  ///
  /// 本地已加载的可能不够覆盖整个时间窗，会向前翻页补历史；为了不让一个
  /// 活跃频道拖出上千条（AI 上下文也吃不下），命中 [maxMessages] 就停，
  /// 返回值里的 `truncated` 告诉调用方"只总结了最近这些"。
  Future<({List<ChatMessage> messages, bool truncated})> collectSince(
    DateTime cutoff, {
    int maxMessages = 300,
  }) async {
    // 每轮翻一页 50 条，最多 10 轮 —— 与 maxMessages 一起兜住请求量
    for (var round = 0; round < 10; round++) {
      if (_disposed) break;
      final loaded = state.messages;
      if (loaded.isEmpty) break;
      if (loaded.length >= maxMessages) break;
      if (!state.canLoadMorePast) break;
      // 最老一条已经早于 cutoff → 时间窗已被完整覆盖
      final oldest = loaded.first.createdAt;
      if (oldest != null && oldest.isBefore(cutoff)) break;
      await loadMorePast();
    }

    final inRange = state.messages.where((m) {
      final at = m.createdAt;
      return at != null && at.isAfter(cutoff);
    }).toList();

    if (inRange.length <= maxMessages) {
      return (messages: inRange, truncated: false);
    }
    // 超上限时保留最近的部分
    return (
      messages: inRange.sublist(inRange.length - maxMessages),
      truncated: true,
    );
  }

  int _nextStagedId() => -(DateTime.now().microsecondsSinceEpoch % 0x7fffffff);

  /// `sent` 报文里的 staged_id 是我们发出去时那个负数暂存 id 的字符串形式。
  /// 别人发的消息没有这个字段。
  static int? _parseStagedId(Map<String, dynamic> data) {
    final raw = data['staged_id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  void _enqueueIncoming(ChatMessage msg, {int? stagedId}) {
    _pendingIncoming.add(_IncomingMessage(msg, stagedId));
    _scheduleFlush();
  }

  void _enqueueProcessed(ChatMessage msg) {
    _pendingProcessed.add(msg);
    _scheduleFlush();
  }

  void _enqueueDeleted(int messageId) {
    _pendingDeleted.add(messageId);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      if (_disposed) return;
      final incoming = List<_IncomingMessage>.from(_pendingIncoming);
      final processed = List<ChatMessage>.from(_pendingProcessed);
      final deleted = List<int>.from(_pendingDeleted);
      _pendingIncoming.clear();
      _pendingProcessed.clear();
      _pendingDeleted.clear();
      if (incoming.isEmpty && processed.isEmpty && deleted.isEmpty) return;

      var list = List<ChatMessage>.from(state.messages);
      for (final item in incoming) {
        final msg = item.message;
        // 优先按 staged_id 命中本地乐观消息：命中即原地替换，不会重复上屏
        final stagedIdx = item.stagedId == null
            ? -1
            : list.indexWhere((m) => m.isLocal && m.id == item.stagedId);
        final idx = stagedIdx >= 0
            ? stagedIdx
            : list.indexWhere((m) => m.id == msg.id);
        if (idx >= 0) {
          list[idx] = msg;
        } else {
          list.add(msg);
        }
      }
      // processed 只带 cook 结果，合并而非替换；找不到就忽略（还没拉到这条）
      for (final msg in processed) {
        final idx = list.indexWhere((m) => m.id == msg.id);
        if (idx < 0) continue;
        list[idx] = list[idx].copyWith(
          cooked: msg.cooked,
          uploads: msg.uploads,
        );
      }
      if (deleted.isNotEmpty) {
        final set = deleted.toSet();
        list = list.where((m) => !set.contains(m.id)).toList();
      }
      list = _sortedAsc(list);
      state = state.copyWith(messages: list);
    });
  }

  static List<ChatMessage> _sortedAsc(List<ChatMessage> msgs) {
    final sorted = List<ChatMessage>.from(msgs);
    sorted.sort((a, b) {
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    return sorted;
  }
}

/// 待并入的一条消息。[stagedId] 仅 `sent` 事件带，用于命中本地乐观消息。
class _IncomingMessage {
  final ChatMessage message;
  final int? stagedId;
  const _IncomingMessage(this.message, this.stagedId);
}

final chatListProvider = NotifierProvider.family
    .autoDispose<ChatListNotifier, ChatListState, int>(ChatListNotifier.new);
