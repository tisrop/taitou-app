import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/chat/chat_message_search.dart';

void main() {
  group('ChatMessageSearchPage', () {
    test('解析消息、所属频道和分页信息', () {
      final page = ChatMessageSearchPage.fromJson({
        'messages': [
          {
            'id': 42,
            'message': 'happy day',
            'excerpt': 'happy <mark>day</mark>',
            'created_at': '2026-08-04T08:00:00.000Z',
            'chat_channel_id': 7,
            'user': {
              'id': 3,
              'username': 'alice',
              'name': 'Alice',
              'avatar_template': '/user_avatar/{size}/3.png',
            },
            'channel': {
              'id': 7,
              'title': 'General',
              'chatable_type': 'Category',
              'chatable': {'color': '0088CC'},
            },
          },
        ],
        'meta': {'has_more': true, 'limit': 20, 'offset': 0},
      });

      expect(page.hits, hasLength(1));
      expect(page.hits.single.message.id, 42);
      expect(page.hits.single.message.user.displayName, 'Alice');
      expect(page.hits.single.channel.id, 7);
      expect(page.hits.single.channel.title, 'General');
      expect(page.hasMore, isTrue);
      expect(page.limit, 20);
      expect(page.offset, 0);
    });

    test('缺少消息列表时返回空页和默认分页信息', () {
      final page = ChatMessageSearchPage.fromJson(const {});

      expect(page.hits, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.limit, 20);
      expect(page.offset, 0);
    });

    test('可通过频道对象或消息的频道 ID 判断结果归属', () {
      final page = ChatMessageSearchPage.fromJson({
        'messages': [
          {
            'id': 42,
            'message': 'hello',
            'chat_channel_id': 7,
            'user': {'id': 3, 'username': 'alice'},
            'channel': {'id': 8, 'title': 'General'},
          },
        ],
      });

      final hit = page.hits.single;
      expect(hit.belongsToChannel(7), isTrue);
      expect(hit.belongsToChannel(8), isTrue);
      expect(hit.belongsToChannel(9), isFalse);
    });

    test('保留 GIF 消息搜索结果', () {
      final page = ChatMessageSearchPage.fromJson({
        'messages': [
          {
            'id': 43,
            'message':
                r'![Greetings: Man Waving Hello](https://static.klipy.com/a.gif)',
            'chat_channel_id': 7,
            'user': {'id': 3, 'username': 'alice'},
            'channel': {'id': 7, 'title': 'General'},
          },
        ],
      });

      expect(page.hits, hasLength(1));
      expect(page.hits.single.message.message, contains('klipy.com/a.gif'));
    });

    test('跳过缺少频道或必填消息字段的损坏结果', () {
      final page = ChatMessageSearchPage.fromJson({
        'messages': [
          {
            'id': 1,
            'message': 'missing channel',
            'chat_channel_id': 7,
            'user': {'id': 3, 'username': 'alice'},
          },
          {
            'message': 'missing message id',
            'chat_channel_id': 7,
            'user': {'id': 3, 'username': 'alice'},
            'channel': {'id': 7, 'title': 'General'},
          },
        ],
        'meta': {'has_more': false},
      });

      expect(page.hits, isEmpty);
    });
  });

  test('搜索排序值与 API 参数一致', () {
    expect(ChatMessageSearchSort.relevance.apiValue, 'relevance');
    expect(ChatMessageSearchSort.latest.apiValue, 'latest');
  });
}
