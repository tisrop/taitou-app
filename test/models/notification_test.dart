import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/notification.dart';

void main() {
  group('DiscourseNotification', () {
    test('解析聊天室提及通知的频道和消息定位字段', () {
      final notification = DiscourseNotification.fromJson({
        'id': 101,
        'user_id': 7,
        'notification_type': NotificationType.chatMention.id,
        'read': false,
        'high_priority': true,
        'created_at': '2026-08-04T08:00:00.000Z',
        'data': '''{
          "chat_message_id": 456,
          "chat_channel_id": 12,
          "chat_thread_id": 34,
          "chat_channel_title": "站务讨论",
          "mentioned_by_username": "alice"
        }''',
      });

      expect(notification.notificationType, NotificationType.chatMention);
      expect(notification.data.chatMessageId, 456);
      expect(notification.data.chatChannelId, 12);
      expect(notification.data.chatThreadId, 34);
      expect(notification.data.chatChannelTitle, '站务讨论');
      expect(notification.username, 'alice');
    });

    test('兼容推送载荷中的 channel_id 和字符串数字', () {
      final data = NotificationData.fromJson({
        'chat_message_id': '456',
        'channel_id': '12',
      });

      expect(data.chatMessageId, 456);
      expect(data.chatChannelId, 12);
    });

    test('兼容 double 类型的整数 ID', () {
      final data = NotificationData.fromJson({
        'chat_message_id': 456.0,
        'channel_id': 12.0,
      });

      expect(data.chatMessageId, 456);
      expect(data.chatChannelId, 12);
    });
  });
}
