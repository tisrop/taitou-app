import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/topic_detail_provider.dart';

TopicDetail _detail() {
  return TopicDetail(
    id: 1,
    title: 'Topic',
    slug: 'topic',
    postsCount: 2,
    postStream: PostStream(posts: const [], stream: const [101, 102]),
    categoryId: 1,
    closed: false,
    archived: false,
  );
}

void main() {
  group('实时新回复落地计划', () {
    test('已加载到底部时不提前把新 ID 插入 stream 或递增计数', () {
      final current = _detail();

      final update = resolveNewPostCreatedUpdate(
        currentDetail: current,
        postId: 103,
        hasMoreAfter: false,
      );

      // 计数与 stream 都留给 _loadPendingNewPosts 落地后统一更新，
      // 避免与 addPost 的递增叠加成双重计数。
      expect(update.shouldLoadImmediately, isTrue);
      expect(update.detail.postsCount, 2);
      expect(update.detail.postStream.stream, [101, 102]);
      expect(update.detail.postStream.posts, same(current.postStream.posts));
    });

    test('尚未到底部时只扩展 stream 等待自然分页', () {
      final current = _detail();

      final update = resolveNewPostCreatedUpdate(
        currentDetail: current,
        postId: 103,
        hasMoreAfter: true,
      );

      expect(update.shouldLoadImmediately, isFalse);
      expect(update.detail.postsCount, 3);
      expect(update.detail.postStream.stream, [101, 102, 103]);
      expect(update.detail.postStream.posts, same(current.postStream.posts));
    });
  });
}
