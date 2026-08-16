import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/models/nested_topic.dart';
import 'package:fluxdo/providers/nested_topic_provider.dart';

Map<String, dynamic> _post(
  int id,
  int postNumber, {
  int directReplyCount = 0,
  int totalDescendantCount = 0,
  List<Map<String, dynamic>> children = const [],
}) {
  return {
    'id': id,
    'post_number': postNumber,
    'username': 'user$id',
    'direct_reply_count': directReplyCount,
    'total_descendant_count': totalDescendantCount,
    'children': children,
  };
}

void main() {
  group('NestedContextResponse', () {
    test('解析祖先链并按从早到晚的顺序包裹目标子树', () {
      final response = NestedContextResponse.fromJson({
        'topic': {'id': 42, 'title': 'Threaded topic'},
        'op_post': _post(1, 1),
        'ancestor_chain': [_post(2, 2), _post(3, 3)],
        'ancestors_truncated': true,
        'target_post': _post(
          4,
          4,
          directReplyCount: 2,
          totalDescendantCount: 3,
          children: [_post(5, 5)],
        ),
      });

      final chain = response.buildContextChain();

      expect(response.topicJson?['id'], 42);
      expect(response.opPost?.postNumber, 1);
      expect(response.ancestorsTruncated, isTrue);
      expect(chain.post.postNumber, 2);
      expect(chain.children.single.post.postNumber, 3);
      expect(chain.children.single.children.single.post.postNumber, 4);
      expect(
        chain.children.single.children.single.children.single.post.postNumber,
        5,
      );
      expect(chain.directReplyCount, 1);
      expect(chain.children.single.directReplyCount, 1);
      expect(chain.children.single.children.single.directReplyCount, 2);
    });

    test('没有祖先时直接返回目标帖子树', () {
      final response = NestedContextResponse.fromJson({
        'ancestor_chain': <Map<String, dynamic>>[],
        'target_post': _post(8, 8, children: [_post(9, 9)]),
      });

      final chain = response.buildContextChain();

      expect(identical(chain, response.targetPost), isTrue);
      expect(chain.children.single.post.postNumber, 9);
    });
  });

  test('NestedRootsResponse 解析 pinned_post_ids', () {
    final response = NestedRootsResponse.fromJson({
      'roots': [_post(2, 2)],
      'has_more_roots': false,
      'page': 0,
      'pinned_post_ids': [11, 22],
    });

    expect(response.pinnedPostIds, [11, 22]);
  });

  test('NestedTopicParams 将目标楼层纳入 family 身份', () {
    const first = NestedTopicParams(topicId: 42, targetPostNumber: 7);
    const same = NestedTopicParams(topicId: 42, targetPostNumber: 7);
    const otherTarget = NestedTopicParams(topicId: 42, targetPostNumber: 8);
    const fullTopic = NestedTopicParams(topicId: 42);

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(otherTarget));
    expect(first, isNot(fullTopic));
  });
}
