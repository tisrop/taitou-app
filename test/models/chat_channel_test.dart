import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/chat/chat_channel.dart';

void main() {
  group('ChatChannel', () {
    test('解析公开频道基础字段', () {
      final channel = ChatChannel.fromJson({
        'id': 42,
        'title': '技术闲聊',
        'description': '工程师日常',
        'slug': 'tech-chat',
        'emoji': '💬',
        'status': 'open',
        'chatable_type': 'Category',
        'chatable_id': 12,
        'auto_join_users': false,
        'threading_enabled': true,
        'memberships_count': 7,
        'meta': {
          'message_bus_last_ids': {
            'channel_message_bus_last_id': 100,
            'new_messages': 90,
            'new_mentions': 5,
            'kick': 3,
          },
        },
      });

      expect(channel.id, 42);
      expect(channel.title, '技术闲聊');
      expect(channel.isDirectMessage, isFalse);
      expect(channel.threadingEnabled, isTrue);
      expect(channel.membershipsCount, 7);
      expect(channel.messageBusLastIds.newMessages, 90);
      expect(channel.messageBusLastIds.channelMessageBusLastId, 100);
    });

    test('解析直接消息频道与当前用户成员关系', () {
      final channel = ChatChannel.fromJson({
        'id': 7,
        'title': '和小张的对话',
        'chatable_type': 'DirectMessage',
        'current_user_membership': {
          'following': true,
          'muted': false,
          'starred': true,
          'notification_level': 'always',
          'last_read_message_id': 55,
        },
        'last_message': {
          'id': 60,
          'message': '你好呀',
          'created_at': '2026-08-03T10:00:00.000Z',
          'chat_channel_id': 7,
          'user': {
            'id': 3,
            'username': 'zhang',
            'avatar_template': '/t/{size}.png',
          },
        },
      });

      expect(channel.isDirectMessage, isTrue);
      expect(channel.currentUserMembership?.following, isTrue);
      expect(channel.currentUserMembership?.starred, isTrue);
      expect(
        channel.currentUserMembership?.notificationLevel,
        ChatChannelNotificationLevel.always,
      );
      expect(channel.isStarred, isTrue);
      expect(channel.currentUserMembership?.lastReadMessageId, 55);
      expect(channel.lastMessage?.message, '你好呀');
      expect(channel.lastMessage?.user.username, 'zhang');
    });

    test('通知级别缺失或未知时默认仅限提及', () {
      final missing = ChatChannelMembership.fromJson({
        'following': true,
        'muted': false,
      });
      final unknown = ChatChannelMembership.fromJson({
        'following': true,
        'muted': false,
        'notification_level': 'unsupported',
      });

      expect(missing.notificationLevel, ChatChannelNotificationLevel.mention);
      expect(unknown.notificationLevel, ChatChannelNotificationLevel.mention);
    });

    test('直接消息频道解析 chatable.users 成员头像', () {
      final channel = ChatChannel.fromJson({
        'id': 8,
        'title': '群聊',
        'chatable_type': 'DirectMessage',
        'chatable': {
          'group': false,
          'users': [
            {'id': 1, 'username': 'alice', 'avatar_template': '/t/{size}.png'},
            {'id': 2, 'username': 'bob', 'avatar_template': '/t/{size}.png'},
          ],
        },
      });

      expect(channel.isDirectMessage, isTrue);
      expect(channel.directMessageUsers.length, 2);
      expect(channel.directMessageUsers.first.username, 'alice');
      expect(
        channel.directMessageUsers.first.getAvatarUrl(size: 40),
        isNotEmpty,
      );
    });

    test('公开频道 chatable 为 Category 时 directMessageUsers 为空', () {
      final channel = ChatChannel.fromJson({
        'id': 9,
        'title': '公开',
        'chatable_type': 'Category',
        'chatable': {'id': 3, 'name': '某分类', 'color': '0088CC'},
      });
      expect(channel.directMessageUsers, isEmpty);
    });

    test('公开频道解析分类颜色 chatable.color', () {
      final channel = ChatChannel.fromJson({
        'id': 10,
        'title': '带颜色频道',
        'chatable_type': 'Category',
        'chatable': {'id': 4, 'name': '分类', 'color': 'FF5500'},
      });
      expect(channel.chatableColor, 'FF5500');
    });

    test('公开频道解析 chatable.read_restricted 与 isCategoryChannel', () {
      final restricted = ChatChannel.fromJson({
        'id': 11,
        'title': '受限频道',
        'chatable_type': 'Category',
        'chatable': {'id': 5, 'name': '内部分类', 'read_restricted': true},
      });
      expect(restricted.isCategoryChannel, isTrue);
      expect(restricted.chatableReadRestricted, isTrue);

      // chatable 缺 read_restricted 字段时按不受限处理
      final open = ChatChannel.fromJson({
        'id': 12,
        'title': '公开频道',
        'chatable_type': 'Category',
        'chatable': {'id': 6, 'name': '公开分类'},
      });
      expect(open.chatableReadRestricted, isFalse);

      final dm = ChatChannel.fromJson({
        'id': 13,
        'title': '私聊',
        'chatable_type': 'DirectMessage',
      });
      expect(dm.isCategoryChannel, isFalse);
    });

    test('缺少 meta 时 messageBusLastIds 为空对象', () {
      final channel = ChatChannel.fromJson({'id': 1, 'title': '无 meta'});
      expect(channel.messageBusLastIds.newMessages, isNull);
    });

    test('仅开放且尚未加入的频道可加入', () {
      final open = ChatChannel.fromJson({
        'id': 20,
        'title': '开放频道',
        'status': 'open',
      });
      final joined = ChatChannel.fromJson({
        'id': 21,
        'title': '已加入频道',
        'status': 'open',
        'current_user_membership': {'following': true},
      });
      final closed = ChatChannel.fromJson({
        'id': 22,
        'title': '关闭频道',
        'status': 'closed',
      });

      expect(open.isJoinable, isTrue);
      expect(joined.isJoinable, isFalse);
      expect(closed.isJoinable, isFalse);
    });
  });

  group('ChatChannelIndex', () {
    test('按公开/直接消息分组解析', () {
      final index = ChatChannelIndex.fromJson({
        'public_channels': [
          {'id': 1, 'title': '公开一'},
          {'id': 2, 'title': '公开二'},
        ],
        'direct_message_channels': [
          {'id': 3, 'title': '私聊', 'chatable_type': 'DirectMessage'},
        ],
        'tracking': {
          '1': {'unread_count': 2},
        },
      });

      expect(index.publicChannels.length, 2);
      expect(index.directMessageChannels.length, 1);
      expect(index.allChannels.length, 3);
      expect(index.tracking, isNotEmpty);
    });

    test('global_presence_channel_state 为对象时不会崩溃', () {
      // 回归：真实响应中该字段是嵌套对象而非 String，
      // 曾因 as String? 强转抛 _TypeError。
      final index = ChatChannelIndex.fromJson({
        'public_channels': [
          {'id': 1, 'title': '公开一'},
        ],
        'direct_message_channels': <Map<String, dynamic>>[],
        'global_presence_channel_state': {'count': 3, 'users': []},
      });

      expect(index.publicChannels.length, 1);
      expect(index.globalPresenceChannelState, isNotNull);
    });

    test('last_message 的 id 为空时忽略无效消息', () {
      // 回归：部分频道索引响应会返回 last_message 对象，但消息 id 为 null。
      // ChatMessage 的 id 是后续操作必需字段，因此这里应忽略该摘要而不是强转崩溃。
      final index = ChatChannelIndex.fromJson({
        'public_channels': [
          {
            'id': 1,
            'title': '公开一',
            'last_message': {
              'id': null,
              'message': '无有效 id 的消息摘要',
              'chat_channel_id': 1,
            },
          },
        ],
        'direct_message_channels': <Map<String, dynamic>>[],
      });

      expect(index.publicChannels, hasLength(1));
      expect(index.publicChannels.single.lastMessage, isNull);
    });
  });

  group('ChatChannelDirectoryPage', () {
    test('解析频道列表与下一页地址', () {
      final page = ChatChannelDirectoryPage.fromJson({
        'channels': [
          {'id': 31, 'title': 'General', 'status': 'open'},
          {'id': 32, 'title': 'Staff', 'status': 'closed'},
        ],
        'meta': {'load_more_url': '/chat/api/channels?offset=2&limit=2'},
      });

      expect(page.channels.map((channel) => channel.id), [31, 32]);
      expect(page.hasMore, isTrue);
      expect(page.loadMoreUrl, contains('offset=2'));
    });

    test('缺少 meta 时按无下一页处理', () {
      final page = ChatChannelDirectoryPage.fromJson({
        'channels': <Map<String, dynamic>>[],
      });

      expect(page.channels, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });
}
