import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/chat/chat_thread.dart';

void main() {
  test('分页大小不超过 Discourse Chat API 上限', () {
    expect(chatThreadsMaxPageSize, 10);
  });

  group('ChatThreadsPage', () {
    test('解析消息串原消息、预览和继续加载状态', () {
      final page = ChatThreadsPage.fromJson({
        'threads': [
          {
            'id': 42,
            'title': '设计讨论',
            'status': 'open',
            'channel_id': 7,
            'reply_count': 3,
            'last_message_id': 105,
            'original_message': {
              'id': 100,
              'message': '原始消息',
              'excerpt': '原始消息摘要',
              'created_at': '2026-08-05T08:00:00.000Z',
              'chat_channel_id': 7,
              'user': {
                'id': 1,
                'username': 'alice',
                'name': 'Alice',
                'avatar_template': '/user_avatar/{size}.png',
              },
            },
            'preview': {
              'last_reply_created_at': '2026-08-05T09:00:00.000Z',
              'last_reply_excerpt': '最后一条回复',
              'last_reply_id': 105,
              'participant_count': 2,
              'reply_count': 3,
              'participant_users': [
                {'id': 1, 'username': 'alice'},
                {'id': 2, 'username': 'bob'},
              ],
              'last_reply_user': {'id': 2, 'username': 'bob'},
            },
          },
        ],
        'tracking': {
          '42': {'unread_count': 1},
        },
        'meta': {
          'channel_id': 7,
          'load_more_url': '/chat/api/channels/7/threads?offset=20',
        },
      });

      expect(page.hasMore, isTrue);
      expect(page.tracking, isNotEmpty);
      expect(page.threads, hasLength(1));
      final thread = page.threads.single;
      expect(thread.id, 42);
      expect(thread.channelId, 7);
      expect(thread.replyCount, 3);
      expect(thread.originalMessage?.message, '原始消息');
      expect(thread.originalMessage?.user.displayName, 'Alice');
      expect(thread.preview?.lastReplyExcerpt, '最后一条回复');
      expect(thread.preview?.participantUsers, hasLength(2));
      expect(thread.preview?.lastReplyUser?.username, 'bob');
      expect(thread.preview?.lastReplyCreatedAt, isNotNull);
    });

    test('缺少可选字段时返回空分页', () {
      final page = ChatThreadsPage.fromJson({
        'threads': <Map<String, dynamic>>[],
        'meta': {'load_more_url': null},
      });

      expect(page.threads, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.tracking, isEmpty);
    });
  });
}
