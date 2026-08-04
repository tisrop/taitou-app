import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/chat/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('解析基础消息字段', () {
      final msg = ChatMessage.fromJson({
        'id': 100,
        'message': '大家好',
        'cooked': '<p>大家好</p>',
        'excerpt': '大家好',
        'created_at': '2026-08-03T10:00:00.000Z',
        'edited': true,
        'chat_channel_id': 1,
        'thread_id': null,
        'user': {
          'id': 1,
          'username': 'alice',
          'avatar_template': '/t/{size}.png',
        },
        'mentioned_users': [
          {'id': 2, 'username': 'bob'},
        ],
      });

      expect(msg.id, 100);
      expect(msg.message, '大家好');
      expect(msg.edited, isTrue);
      expect(msg.chatChannelId, 1);
      expect(msg.user.username, 'alice');
      expect(msg.mentionedUsers.length, 1);
      expect(msg.mentionedUsers.first.username, 'bob');
      expect(msg.isDeleted, isFalse);
    });

    test('解析回应、收藏、举报权限和置顶状态', () {
      final msg = ChatMessage.fromJson({
        'id': 101,
        'message': 'hello',
        'chat_channel_id': 1,
        'user': {'id': 1, 'username': 'alice'},
        'reactions': [
          {'emoji': 'heart', 'count': 3, 'reacted': true},
          {'emoji': '', 'count': 1},
        ],
        'bookmark': {'id': 77, 'bookmarkable_type': 'Chat::Message'},
        'available_flags': ['spam', 'inappropriate'],
        'pinned': true,
      });

      expect(msg.reactions, hasLength(1));
      expect(msg.reactions.single.emoji, 'heart');
      expect(msg.reactions.single.count, 3);
      expect(msg.reactions.single.reacted, isTrue);
      expect(msg.bookmarkId, 77);
      expect(msg.availableFlags, ['spam', 'inappropriate']);
      expect(msg.pinned, isTrue);
    });

    test('copyWith 可切换回应、置顶并清除收藏', () {
      final origin = ChatMessage.fromJson({
        'id': 102,
        'message': 'hello',
        'chat_channel_id': 1,
        'user': {'id': 1, 'username': 'alice'},
        'bookmark': {'id': 9},
      });
      final updated = origin.copyWith(
        reactions: const [
          ChatMessageReaction(emoji: 'tada', count: 1, reacted: true),
        ],
        pinned: true,
        clearBookmark: true,
      );

      expect(updated.bookmarkId, isNull);
      expect(updated.pinned, isTrue);
      expect(updated.reactions.single.emoji, 'tada');
      expect(updated.message, origin.message);
    });

    test('解析删除消息', () {
      final msg = ChatMessage.fromJson({
        'id': 5,
        'message': 'x',
        'deleted_at': '2026-08-03T11:00:00.000Z',
        'chat_channel_id': 1,
        'user': {'id': 1, 'username': 'alice'},
      });
      expect(msg.isDeleted, isTrue);
    });

    test('显示名优先昵称', () {
      final msg = ChatMessage.fromJson({
        'id': 1,
        'message': 'hi',
        'chat_channel_id': 1,
        'user': {'id': 1, 'username': 'alice', 'name': '爱丽丝'},
      });
      expect(msg.user.displayName, '爱丽丝');
    });

    test('fromMessageBusData 从 chat_message 根键解析', () {
      final msg = ChatMessage.fromMessageBusData({
        'type': 'processed',
        'chat_message': {
          'id': 88,
          'message': '实时消息',
          'chat_channel_id': 2,
          'user': {'id': 9, 'username': 'carol'},
        },
      });
      expect(msg, isNotNull);
      expect(msg!.id, 88);
      expect(msg.message, '实时消息');
      expect(msg.chatChannelId, 2);
    });

    test('fromMessageBusData 缺 chat_message 返回 null', () {
      expect(ChatMessage.fromMessageBusData({'type': 'delete'}), isNull);
    });

    test('copyWith 合并 cooked/uploads 时保留其余字段', () {
      final origin = ChatMessage.fromJson({
        'id': 100,
        'message': '原文',
        'excerpt': '原文',
        'created_at': '2026-08-03T10:00:00.000Z',
        'chat_channel_id': 7,
        'user': {'id': 3, 'username': 'alice', 'name': '爱丽丝'},
      });

      // processed 事件只带回 cook 结果
      final merged = origin.copyWith(
        cooked: '<p>原文</p>',
        uploads: const [ChatUpload(id: 1, url: '/uploads/a.png')],
      );

      expect(merged.cooked, '<p>原文</p>');
      expect(merged.uploads.single.url, '/uploads/a.png');
      // 其余字段不能被冲掉
      expect(merged.id, 100);
      expect(merged.message, '原文');
      expect(merged.chatChannelId, 7);
      expect(merged.user.displayName, '爱丽丝');
      expect(merged.createdAt, origin.createdAt);
    });
  });

  group('ChatMessagesPage', () {
    test('解析消息列表与分页 meta', () {
      final page = ChatMessagesPage.fromJson({
        'messages': [
          {
            'id': 1,
            'message': 'a',
            'chat_channel_id': 1,
            'user': {'id': 1, 'username': 'u'},
          },
          {
            'id': 2,
            'message': 'b',
            'chat_channel_id': 1,
            'user': {'id': 1, 'username': 'u'},
          },
        ],
        'tracking': {'unread_count': 1},
        'meta': {
          'target_message_id': 2,
          'can_load_more_future': false,
          'can_load_more_past': true,
        },
      });

      expect(page.messages.length, 2);
      expect(page.targetMessageId, 2);
      expect(page.canLoadMorePast, isTrue);
      expect(page.canLoadMoreFuture, isFalse);
    });
  });
}
