import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

Map<String, dynamic> _topicJson({
  required int id,
  required String title,
  String slug = 'topic',
  List<Map<String, dynamic>> posters = const [],
}) {
  return {
    'id': id,
    'title': title,
    'slug': slug,
    'posts_count': 3,
    'reply_count': 2,
    'category_id': 1,
    'posters': posters,
  };
}

Map<String, dynamic> _detailJson({
  List<Map<String, dynamic>> suggested = const [],
  List<Map<String, dynamic>> related = const [],
  int highestPostNumber = 0,
}) {
  return {
    'id': 1,
    'title': 'Topic',
    'slug': 'topic',
    'posts_count': 0,
    'highest_post_number': highestPostNumber,
    'category_id': 1,
    'post_stream': {'posts': <dynamic>[], 'stream': <dynamic>[]},
    'suggested_topics': suggested,
    'related_topics': related,
  };
}

void main() {
  group('parseSuggestedTopicList', () {
    test('解析字段稀疏的建议话题', () {
      final topics = parseSuggestedTopicList([
        _topicJson(id: 101, title: 'Suggested'),
      ]);

      expect(topics, hasLength(1));
      expect(topics.single.id, 101);
      expect(topics.single.title, 'Suggested');
      expect(topics.single.replyCount, 2);
      expect(topics.single.categoryId, '1');
    });

    test('poster 内嵌 user 会映射到参与者', () {
      final topics = parseSuggestedTopicList([
        _topicJson(
          id: 101,
          title: 'Suggested',
          posters: [
            {
              'description': 'Original Poster',
              'extras': 'latest',
              'user': {
                'id': 7,
                'username': 'alice',
                'name': 'Alice',
                'avatar_template': '/user_avatar/example/alice/{size}/1_2.png',
              },
            },
          ],
        ),
      ]);

      final poster = topics.single.posters.single;
      expect(poster.userId, 7);
      expect(poster.user?.username, 'alice');
      expect(poster.user?.name, 'Alice');
    });

    test('单条坏数据不会导致整组解析失败', () {
      final topics = parseSuggestedTopicList([
        {'title': 'Missing id'},
        _topicJson(id: 102, title: 'Valid'),
        'not a map',
      ]);

      expect(topics.map((topic) => topic.id), [102]);
    });
  });

  group('TopicDetail suggested topics', () {
    test('fromJson 同时解析 suggested_topics 和 related_topics', () {
      final detail = TopicDetail.fromJson(
        _detailJson(
          suggested: [_topicJson(id: 201, title: 'Suggested')],
          related: [_topicJson(id: 301, title: 'Related')],
        ),
      );

      expect(detail.suggestedTopics.single.id, 201);
      expect(detail.relatedTopics.single.id, 301);
    });

    test('copyWith 默认保留并可替换两组话题', () {
      final detail = TopicDetail.fromJson(
        _detailJson(
          suggested: [_topicJson(id: 201, title: 'Suggested')],
          related: [_topicJson(id: 301, title: 'Related')],
        ),
      );

      final preserved = detail.copyWith(title: 'Updated');
      expect(preserved.suggestedTopics.single.id, 201);
      expect(preserved.relatedTopics.single.id, 301);

      final replacement = Topic.fromJson(
        _topicJson(id: 401, title: 'Replacement'),
      );
      final replaced = detail.copyWith(
        suggestedTopics: [replacement],
        relatedTopics: const [],
      );
      expect(replaced.suggestedTopics.single.id, 401);
      expect(replaced.relatedTopics, isEmpty);
    });
  });

  group('TopicDetail tracking fields', () {
    test('fromJson 解析最高楼层号，copyWith 默认保留并可替换', () {
      final detail = TopicDetail.fromJson(_detailJson(highestPostNumber: 8));

      expect(detail.highestPostNumber, 8);
      expect(detail.copyWith(title: 'Updated').highestPostNumber, 8);
      expect(detail.copyWith(highestPostNumber: 10).highestPostNumber, 10);
    });

    test('响应缺少最高楼层号时回退为零', () {
      final json = _detailJson()..remove('highest_post_number');

      expect(TopicDetail.fromJson(json).highestPostNumber, 0);
    });
  });
}
