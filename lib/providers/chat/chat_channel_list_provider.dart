import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/chat/chat_channel.dart';
import '../../services/message_bus_service.dart';
import '../core_providers.dart';
import '../message_bus/message_bus_service_provider.dart';
import '../message_bus/topic_tracking_providers.dart';

/// 当前用户聊天频道列表 Notifier
///
/// 拉取 `GET /chat/api/me/channels`。频道列表的实时性依赖 MessageBus 的
/// 目录级频道(`/chat`)与每位用户的 tracking 频道(`/chat/user-tracking-state/{userId}`)
/// 推送 unread 变化；这里监听 `/chat/{userId}` tracking 频道做增量未读更新，
/// 并在收到目录级事件时触发静默刷新。
class ChatChannelListNotifier extends AsyncNotifier<ChatChannelIndex> {
  final Map<int, ChatChannel> _pendingUpserts = <int, ChatChannel>{};
  int _fetchGeneration = 0;
  MessageBusService? _subscribedMessageBus;
  int? _subscribedUserId;
  String? _trackingChannel;
  MessageBusCallback? _trackingCallback;
  String? _directoryChannel;
  MessageBusCallback? _directoryCallback;

  @override
  Future<ChatChannelIndex> build() async {
    // 仅依赖身份：同一用户刷新不重建，保留 MessageBus 累积的实时未读。
    final userId = ref.watch(
      currentUserProvider.select((state) => state.value?.id),
    );
    // 确保 MessageBus 已 configure
    ref.watch(messageBusInitProvider);
    final messageBus = ref.watch(messageBusServiceProvider);

    _setupSubscriptions(messageBus, userId);

    ref.onDispose(_teardownSubscriptions);

    final service = ref.watch(discourseServiceProvider);
    final generation = ++_fetchGeneration;
    final index = await service.getChatChannels();
    final current = state.value;
    if (generation != _fetchGeneration && current != null) {
      return current;
    }
    return mergeFetchedIndex(index);
  }

  void _setupSubscriptions(MessageBusService messageBus, int? userId) {
    if (identical(_subscribedMessageBus, messageBus) &&
        _subscribedUserId == userId) {
      return;
    }

    _teardownSubscriptions();
    _subscribedMessageBus = messageBus;
    _subscribedUserId = userId;

    if (userId == null) return;

    // 目录级事件（新频道 / 频道变更）→ 静默刷新列表
    _directoryChannel = '/chat/new-channel';
    _directoryCallback = (_) => _silentRefresh();
    _trackingChannel = '/chat/user-tracking-state/$userId';
    _trackingCallback = (_) => _silentRefresh();
    messageBus.subscribe(_directoryChannel!, _directoryCallback!);
    messageBus.subscribe(_trackingChannel!, _trackingCallback!);
  }

  void _teardownSubscriptions() {
    final messageBus = _subscribedMessageBus;
    if (messageBus != null) {
      if (_directoryChannel != null && _directoryCallback != null) {
        messageBus.unsubscribe(_directoryChannel!, _directoryCallback);
      }
      if (_trackingChannel != null && _trackingCallback != null) {
        messageBus.unsubscribe(_trackingChannel!, _trackingCallback);
      }
    }
    _subscribedMessageBus = null;
    _subscribedUserId = null;
    _directoryChannel = null;
    _directoryCallback = null;
    _trackingChannel = null;
    _trackingCallback = null;
  }

  /// 静默刷新：不进入 loading 态，保留已有数据
  Future<ChatChannelIndex?> _silentRefresh() async {
    final generation = ++_fetchGeneration;
    try {
      final index = await ref.read(discourseServiceProvider).getChatChannels();
      if (generation != _fetchGeneration) return null;
      state = AsyncData(mergeFetchedIndex(index));
      return index;
    } catch (_) {
      // 静默失败：保留当前数据，下次显式刷新再报错
      return null;
    }
  }

  /// 把频道立即写入列表，并在服务端目录短暂滞后时保留它。
  void upsertChannel(ChatChannel channel) {
    _pendingUpserts[channel.id] = channel;
    final index =
        state.value ??
        const ChatChannelIndex(publicChannels: [], directMessageChannels: []);
    state = AsyncData(_upsertIntoIndex(index, channel));
  }

  /// 统一创建或获取直接消息。
  ///
  /// 新会话在首条消息发送前只是服务端草稿，不能写入本地频道列表；
  /// 否则 App 会显示网页端尚不存在的会话。
  Future<ChatChannel> createDirectMessageChannel(
    List<String> targetUsernames, {
    bool upsert = true,
    String? name,
  }) {
    return ref
        .read(discourseServiceProvider)
        .createDirectMessageChannel(
          targetUsernames,
          upsert: upsert,
          name: name,
        );
  }

  ChatChannelIndex _upsertIntoIndex(
    ChatChannelIndex index,
    ChatChannel channel,
  ) {
    final publicChannels = index.publicChannels
        .where((item) => item.id != channel.id)
        .toList();
    final directMessageChannels = index.directMessageChannels
        .where((item) => item.id != channel.id)
        .toList();
    if (channel.isDirectMessage) {
      directMessageChannels.insert(0, channel);
    } else {
      publicChannels.insert(0, channel);
    }

    return ChatChannelIndex(
      publicChannels: publicChannels,
      directMessageChannels: directMessageChannels,
      tracking: index.tracking,
      globalPresenceChannelState: index.globalPresenceChannelState,
    );
  }

  /// 将服务端频道目录与已确认发布但目录响应尚未收录的频道合并。
  ///
  /// protected 是为了让测试 notifier 能模拟延迟的初始目录响应。
  @protected
  ChatChannelIndex mergeFetchedIndex(ChatChannelIndex index) {
    var merged = index;
    final fetchedIds = index.allChannels.map((channel) => channel.id).toSet();
    final resolvedIds = <int>[];
    for (final entry in _pendingUpserts.entries) {
      if (fetchedIds.contains(entry.key)) {
        resolvedIds.add(entry.key);
      } else {
        merged = _upsertIntoIndex(merged, entry.value);
      }
    }
    for (final id in resolvedIds) {
      _pendingUpserts.remove(id);
    }
    return merged;
  }

  /// 从当前列表移除频道。服务端成员关系删除成功后调用，避免等待下一次刷新。
  void removeChannel(int channelId) {
    _pendingUpserts.remove(channelId);
    final index = state.value;
    if (index == null) return;

    final publicChannels = index.publicChannels
        .where((channel) => channel.id != channelId)
        .toList();
    final directMessageChannels = index.directMessageChannels
        .where((channel) => channel.id != channelId)
        .toList();
    if (publicChannels.length == index.publicChannels.length &&
        directMessageChannels.length == index.directMessageChannels.length) {
      return;
    }

    state = AsyncData(
      ChatChannelIndex(
        publicChannels: publicChannels,
        directMessageChannels: directMessageChannels,
        tracking: index.tracking,
        globalPresenceChannelState: index.globalPresenceChannelState,
      ),
    );
  }

  /// 创建频道等局部操作完成后的后台刷新，不切换到 loading 态。
  Future<ChatChannelIndex?> refreshSilently() => _silentRefresh();

  @protected
  List<Duration> get channelVisibilityRetryDelays => const [
    Duration.zero,
    Duration(milliseconds: 120),
    Duration(milliseconds: 280),
    Duration(milliseconds: 600),
  ];

  /// 等待服务端频道目录确认目标频道，解决首条私聊消息发布后目录短暂滞后。
  /// 返回 true 仅表示真实的 `/chat/api/me/channels` 响应已包含该频道。
  Future<bool> refreshUntilChannelVisible(int channelId) async {
    for (final delay in channelVisibilityRetryDelays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final serverIndex = await refreshSilently();
      if (serverIndex?.allChannels.any((channel) => channel.id == channelId) ==
          true) {
        return true;
      }
    }
    return false;
  }

  /// 手动下拉刷新
  Future<void> refresh() async {
    final generation = ++_fetchGeneration;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(discourseServiceProvider).getChatChannels(),
    );
    if (generation != _fetchGeneration) return;
    state = result.whenData(mergeFetchedIndex);
  }

  /// 定位单个频道（列表内已存在则返回；否则发起一次目标请求）
  Future<ChatChannel?> channelById(int channelId) async {
    final index = state.value;
    if (index != null) {
      for (final c in index.allChannels) {
        if (c.id == channelId) return c;
      }
    }
    try {
      return await ref.read(discourseServiceProvider).getChatChannel(channelId);
    } catch (_) {
      return null;
    }
  }
}

final chatChannelListProvider =
    AsyncNotifierProvider<ChatChannelListNotifier, ChatChannelIndex>(
      ChatChannelListNotifier.new,
    );
