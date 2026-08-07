import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/message_bus/topic_tracking_providers.dart';
import 'package:fluxdo/providers/topic_list/topic_list_provider.dart';

Topic _topic({
  int id = 1,
  bool unseen = false,
  int unread = 0,
  int? lastReadPostNumber,
  int highestPostNumber = 1,
}) {
  return Topic(
    id: id,
    title: '话题 $id',
    slug: 'topic-$id',
    postsCount: highestPostNumber,
    replyCount: highestPostNumber - 1,
    views: 12,
    likeCount: 3,
    excerpt: '摘要',
    categoryId: '2',
    unseen: unseen,
    unread: unread,
    lastReadPostNumber: lastReadPostNumber,
    highestPostNumber: highestPostNumber,
    bookmarkId: 99,
    bookmarkName: '稍后读',
    hasAcceptedAnswer: true,
  );
}

TrackedTopicState _tracked({
  int topicId = 1,
  int? lastReadPostNumber,
  required int highestPostNumber,
  bool isSeen = false,
}) {
  return TrackedTopicState(
    topicId: topicId,
    lastReadPostNumber: lastReadPostNumber,
    highestPostNumber: highestPostNumber,
    isSeen: isSeen,
  );
}

void main() {
  group('syncTopicsWithTrackingState', () {
    test('新回复推进最高帖号并增加未读数', () {
      final original = _topic(
        unread: 2,
        lastReadPostNumber: 3,
        highestPostNumber: 5,
      );
      final topics = [original];

      final result = syncTopicsWithTrackingState(topics, {
        1: _tracked(lastReadPostNumber: 3, highestPostNumber: 7),
      });

      expect(result, isNot(same(topics)));
      expect(result.single.highestPostNumber, 7);
      expect(result.single.lastReadPostNumber, 3);
      expect(result.single.unread, 4);
      expect(result.single.bookmarkId, 99);
      expect(result.single.bookmarkName, '稍后读');
      expect(result.single.hasAcceptedAnswer, isTrue);
    });

    test('其他设备推进阅读游标后清除未读', () {
      final original = _topic(
        unread: 4,
        lastReadPostNumber: 3,
        highestPostNumber: 7,
      );

      final result = syncTopicsWithTrackingState(
        [original],
        {1: _tracked(lastReadPostNumber: 7, highestPostNumber: 7)},
      );

      expect(result.single.lastReadPostNumber, 7);
      expect(result.single.unread, 0);
    });

    test('旧消息重放不会让任一游标倒退', () {
      final original = _topic(lastReadPostNumber: 7, highestPostNumber: 7);
      final topics = [original];

      final result = syncTopicsWithTrackingState(topics, {
        1: _tracked(lastReadPostNumber: 3, highestPostNumber: 5),
      });

      expect(result, same(topics));
      expect(result.single.lastReadPostNumber, 7);
      expect(result.single.highestPostNumber, 7);
      expect(result.single.unread, 0);
    });

    test('从未读过的话题保持 unread 为零，dismiss 后清除 unseen', () {
      final original = _topic(unseen: true, unread: 0, highestPostNumber: 4);

      final result = syncTopicsWithTrackingState(
        [original],
        {1: _tracked(highestPostNumber: 5, isSeen: true)},
      );

      expect(result.single.lastReadPostNumber, isNull);
      expect(result.single.highestPostNumber, 5);
      expect(result.single.unread, 0);
      expect(result.single.unseen, isFalse);
    });

    test('无匹配追踪状态时复用原列表实例', () {
      final topics = [_topic(id: 1)];

      final result = syncTopicsWithTrackingState(topics, {
        2: _tracked(topicId: 2, highestPostNumber: 3),
      });

      expect(result, same(topics));
    });
  });
}
