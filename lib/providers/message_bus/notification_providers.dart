import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/s.dart';
import '../../services/message_bus_service.dart';
import '../../services/local_notification_service.dart';
import '../../models/notification.dart';
import '../discourse_providers.dart';
import '../preferences_provider.dart';
import '../../utils/blocked_user_filter.dart';
import 'models.dart';
import 'message_bus_service_provider.dart';
import 'topic_tracking_providers.dart';

/// 通知计数 Notifier
/// 优先使用 MessageBus 推送的实时计数，初始值从 currentUser 获取。
///
/// 收到第一条实时更新前，持续采纳 currentUser 渐进加载出的服务端计数；
/// 收到实时更新后则锁定 MessageBus 的新值，避免后续缓存刷新将徽章回刷。
class NotificationCountNotifier extends Notifier<NotificationCountState> {
  bool _liveUpdateReceived = false;
  int? _lastUserId;

  @override
  NotificationCountState build() {
    final user = ref.watch(currentUserProvider).value;
    if (user == null) {
      _liveUpdateReceived = false;
      _lastUserId = null;
      return const NotificationCountState();
    }

    final identityChanged = user.id != _lastUserId;
    _lastUserId = user.id;
    if (identityChanged) {
      _liveUpdateReceived = false;
    }

    if (_liveUpdateReceived) {
      return state;
    }

    return NotificationCountState(
      allUnread: user.allUnreadNotificationsCount,
      unread: user.unreadNotifications,
      highPriority: user.unreadHighPriorityNotifications,
    );
  }

  void update({int? allUnread, int? unread, int? highPriority}) {
    _liveUpdateReceived = true;
    state = state.copyWith(
      allUnread: allUnread,
      unread: unread,
      highPriority: highPriority,
    );
  }

  /// 标记所有已读后重置计数，并防止服务端旧值重新点亮徽章。
  void markAllRead() {
    _liveUpdateReceived = true;
    state = const NotificationCountState();
  }
}

final notificationCountStateProvider =
    NotifierProvider<NotificationCountNotifier, NotificationCountState>(() {
      return NotificationCountNotifier();
    });

/// 通知频道监听器
/// 当收到通知消息时更新计数并刷新通知列表
/// 复刻 Discourse 逻辑：通过增量更新（插入新通知 + recent 同步已读状态）保持列表同步
class NotificationChannelNotifier extends Notifier<void> {
  String? _subscribedChannel;
  MessageBusCallback? _callback;

  @override
  void build() {
    // 确保 MessageBus 已 configure（域名配置），避免用主站域名轮询
    ref.watch(messageBusInitProvider);
    final messageBus = ref.watch(messageBusServiceProvider);
    final currentUser = ref.watch(currentUserProvider).value;

    // 清理之前的订阅
    if (_subscribedChannel != null && _callback != null) {
      debugPrint('[NotificationChannel] 清理旧订阅: $_subscribedChannel');
      messageBus.unsubscribe(_subscribedChannel!, _callback);
      _subscribedChannel = null;
      _callback = null;
    }

    if (currentUser == null) {
      debugPrint('[NotificationChannel] 用户未登录，跳过订阅');
      return;
    }

    final channel = '/notification/${currentUser.id}';
    final initialMessageId = currentUser.notificationChannelPosition;

    debugPrint(
      '[NotificationChannel] 订阅频道: $channel, 初始 messageId: $initialMessageId',
    );

    void onMessage(MessageBusMessage message) {
      final data = message.data;
      if (data is Map<String, dynamic>) {
        final allUnreadCount = data['all_unread_notifications_count'] as int?;
        final unreadCount = data['unread_notifications'] as int?;
        final unreadHighPriority =
            data['unread_high_priority_notifications'] as int?;

        debugPrint(
          '[Notification] 计数更新: allUnread=$allUnreadCount, unread=$unreadCount, highPriority=$unreadHighPriority',
        );

        // 更新通知计数
        if (allUnreadCount != null ||
            unreadCount != null ||
            unreadHighPriority != null) {
          ref
              .read(notificationCountStateProvider.notifier)
              .update(
                allUnread: allUnreadCount,
                unread: unreadCount,
                highPriority: unreadHighPriority,
              );
        }

        // 仅在通知列表已加载（面板已打开过）时做增量更新，
        // 避免 ref.read() 意外触发 build() 发起 API 请求
        if (ref.exists(recentNotificationsProvider)) {
          final recentState = ref.read(recentNotificationsProvider);
          if (recentState.hasValue) {
            final recentNotifier = ref.read(
              recentNotificationsProvider.notifier,
            );

            // 如果有新通知，从 last_notification 中提取并添加到列表
            final lastNotification = data['last_notification'];
            if (lastNotification is Map<String, dynamic>) {
              final notification = lastNotification['notification'];
              if (notification is Map<String, dynamic>) {
                try {
                  final newNotification = DiscourseNotification.fromJson(
                    notification,
                  );
                  final blockedUsernames = ref
                      .read(preferencesProvider)
                      .normalizedBlockedUsernames;
                  if (!BlockedUserFilter.isBlockedNotification(
                    newNotification,
                    blockedUsernames,
                  )) {
                    debugPrint(
                      '[Notification] 添加新通知到列表: id=${newNotification.id}',
                    );
                    recentNotifier.addNotification(newNotification);
                  }
                } catch (e) {
                  debugPrint('[Notification] 解析新通知失败: $e');
                }
              }
            }

            // 使用 recent 字段同步通知列表（复刻 Discourse 逻辑）
            // recent 同时承担：更新已读状态 + 移除过期通知
            final recent = data['recent'];
            if (recent is List) {
              final readStatusMap = <int, bool>{};
              for (final entry in recent) {
                if (entry is List && entry.length >= 2) {
                  final id = entry[0] as int?;
                  final read = entry[1] as bool?;
                  if (id != null && read != null) {
                    readStatusMap[id] = read;
                  }
                }
              }
              if (readStatusMap.isNotEmpty) {
                recentNotifier.syncWithRecent(readStatusMap);
              }
            }
          }
        }
      }
    }

    _subscribedChannel = channel;
    _callback = onMessage;

    messageBus.subscribeWithMessageId(channel, onMessage, initialMessageId);

    ref.onDispose(() {
      if (_subscribedChannel != null && _callback != null) {
        debugPrint('[NotificationChannel] 取消订阅频道: $_subscribedChannel');
        messageBus.unsubscribe(_subscribedChannel!, _callback);
      }
    });
  }
}

final notificationChannelProvider =
    NotifierProvider<NotificationChannelNotifier, void>(
      NotificationChannelNotifier.new,
    );

/// 通知提醒频道监听器（复刻 Discourse 官方实现）
/// 订阅 /notification-alert/{userId} 频道，用于触发系统通知
class NotificationAlertChannelNotifier extends Notifier<void> {
  String? _subscribedChannel;
  MessageBusCallback? _callback;

  @override
  void build() {
    // 确保 MessageBus 已 configure（域名配置），避免用主站域名轮询
    ref.watch(messageBusInitProvider);
    final messageBus = ref.watch(messageBusServiceProvider);
    final currentUser = ref.watch(currentUserProvider).value;

    // 清理之前的订阅
    if (_subscribedChannel != null && _callback != null) {
      debugPrint('[NotificationAlert] 清理旧订阅: $_subscribedChannel');
      messageBus.unsubscribe(_subscribedChannel!, _callback);
      _subscribedChannel = null;
      _callback = null;
    }

    if (currentUser == null) {
      debugPrint('[NotificationAlert] 用户未登录，跳过订阅');
      return;
    }

    // Discourse-compatible 服务端可通过此频道触发桌面通知。
    // 注意：原生 Discourse 的群组摘要通常只写入通知列表，不会发布 type 16 alert；
    // 因此应用内 /notification/{userId} 通知仍是群组收件箱跳转的主路径。
    final channel = '/notification-alert/${currentUser.id}';

    debugPrint('[NotificationAlert] 订阅频道: $channel');

    void onAlert(MessageBusMessage message) {
      final data = message.data;
      debugPrint('[NotificationAlert] 收到提醒: $data');

      if (data is Map<String, dynamic>) {
        // Discourse payload 格式:
        // {
        //   notification_type: int,
        //   post_number: int,
        //   topic_title: String,
        //   topic_id: int,
        //   excerpt: String,
        //   username: String,
        //   post_url: String,
        //   group_name: String? (fork 服务端的群组摘要扩展字段),
        // }
        final topicTitle = data['topic_title'] as String? ?? '';
        final topicId = data['topic_id'] as int?;
        final postNumber = data['post_number'] as int?;
        final excerpt = data['excerpt'] as String? ?? '';
        final username = data['username'] as String? ?? '';
        final notificationType = data['notification_type'] as int?;
        final groupName = data['group_name'] as String?;

        final blockedUsernames = ref
            .read(preferencesProvider)
            .normalizedBlockedUsernames;
        if (BlockedUserFilter.isBlockedUsername(username, blockedUsernames)) {
          return;
        }

        // 构建通知标题（参考 desktop-notifications.js 的 i18nKey 逻辑）
        String title = topicTitle;
        if (title.isEmpty) {
          title = _getNotificationTypeLabel(notificationType);
        }

        // 构建通知内容
        String body = excerpt;
        if (body.isEmpty && username.isNotEmpty) {
          body = username;
        }

        debugPrint(
          '[NotificationAlert] 发送系统通知: title=$title, body=$body, topicId=$topicId, postNumber=$postNumber',
        );

        // type 16 的系统通知仅作为服务端已发布该 alert 时的防御性兼容路径。
        // 真正的群组收件箱入口由通知列表中的 groupMessageSummary 处理。
        LocalNotificationService().show(
          title: title,
          body: body,
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          topicId: topicId,
          postNumber: postNumber,
          openPrivateMessages:
              notificationType == NotificationType.groupMessageSummary.id,
          privateMessageGroupName: groupName,
        );
      }
    }

    _subscribedChannel = channel;
    _callback = onAlert;

    messageBus.subscribe(channel, onAlert);

    ref.onDispose(() {
      if (_subscribedChannel != null && _callback != null) {
        debugPrint('[NotificationAlert] 取消订阅频道: $_subscribedChannel');
        messageBus.unsubscribe(_subscribedChannel!, _callback);
      }
    });
  }

  /// 获取通知类型标签
  String _getNotificationTypeLabel(int? type) {
    if (type == null) return S.current.notification_newNotification;
    final notificationType = NotificationType.fromId(type);
    return notificationType.label;
  }
}

final notificationAlertChannelProvider =
    NotifierProvider<NotificationAlertChannelNotifier, void>(
      NotificationAlertChannelNotifier.new,
    );
