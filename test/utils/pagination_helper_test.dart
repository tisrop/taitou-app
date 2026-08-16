import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/pagination_helper.dart';

void main() {
  group('PaginationHelpers.forTopics', () {
    final helper = PaginationHelpers.forTopics<int>(
      keyExtractor: (item) => item,
    );

    test('moreUrl 非空且响应非空时 hasMore=true', () {
      final state = helper.processRefresh(
        const PaginationResult(items: [1, 2], moreUrl: '/latest.json?page=1'),
      );

      expect(state.hasMore, isTrue);
    });

    test('moreUrl 非空但响应为空时 hasMore=false', () {
      final state = helper.processLoadMore(
        const PaginationState(items: [1, 2]),
        const PaginationResult(items: [], moreUrl: '/latest.json?page=2'),
      );

      expect(state.items, [1, 2]);
      expect(state.hasMore, isFalse);
    });

    test('非空重复响应仍保留 hasMore，让调用方可以推进页码', () {
      final state = helper.processLoadMore(
        const PaginationState(items: [1, 2]),
        const PaginationResult(items: [2], moreUrl: '/latest.json?page=2'),
      );

      expect(state.items, [1, 2]);
      expect(state.hasMore, isTrue);
    });
  });

  group('PaginationHelper.mergeUpdates', () {
    final helper = PaginationHelpers.forTopics<({int id, String value})>(
      keyExtractor: (item) => item.id,
    );

    test('只替换已加载的同 key 条目并保留顺序与长度', () {
      final current = [
        (id: 1, value: 'old-1'),
        (id: 2, value: 'old-2'),
        (id: 3, value: 'page-2'),
      ];

      final merged = helper.mergeUpdates(current, [
        (id: 1, value: 'new-1'),
        (id: 2, value: 'new-2'),
      ]);

      expect(merged, [
        (id: 1, value: 'new-1'),
        (id: 2, value: 'new-2'),
        (id: 3, value: 'page-2'),
      ]);
    });

    test('忽略尚未加载的新 key，避免静默同步改变列表长度', () {
      final current = [(id: 1, value: 'old')];

      final merged = helper.mergeUpdates(current, [
        (id: 1, value: 'new'),
        (id: 4, value: 'first-page-new-topic'),
      ]);

      expect(merged, [(id: 1, value: 'new')]);
    });
  });
}
