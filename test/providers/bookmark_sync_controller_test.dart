import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/bookmark_sync_controller.dart';
import 'package:fluxdo/providers/bookmarks_reconciler.dart';
import 'package:fluxdo/providers/bookmarks_repository.dart';
import 'package:fluxdo/providers/user_content_providers.dart';
import 'package:fluxdo/storage/bookmark_cache_dao.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/bookmark_hive_test_support.dart';

BookmarkCacheEntry _entry(int id) {
  final updatedAt = DateTime.utc(2026, 8, 1);
  return BookmarkCacheEntry(
    bookmarkId: id,
    topicId: id,
    nameNormalized: null,
    updatedAt: updatedAt,
    cachedAt: updatedAt,
    payload: {
      'id': id,
      '_bookmark_id': id,
      '_bookmark_updated_at': updatedAt.toIso8601String(),
      'title': 'Topic $id',
    },
  );
}

void main() {
  late BookmarkHiveTestSupport storage;
  late BookmarksRepository repository;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    storage = await BookmarkHiveTestSupport.create();
    repository = BookmarksRepository(
      BookmarkCacheDao(boxFactory: storage.openBox),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await storage.dispose();
  });

  ProviderContainer createContainer(BookmarkRawPageLoader loader) {
    final container = ProviderContainer(
      overrides: [
        bookmarksRepositoryProvider.overrideWithValue(repository),
        currentUsernameProvider.overrideWith((ref) async => 'acct'),
        bookmarkRawPageLoaderProvider.overrideWithValue(loader),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('本地为空时全量同步，完成后恢复 idle 并写入缓存', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final container = createContainer((page) async {
      if (page == 0) {
        if (!started.isCompleted) started.complete();
        await gate.future;
        return BookmarkPageParseResult(
          topics: const [],
          entries: [_entry(1)],
          moreUrl: 'next',
        );
      }
      return BookmarkPageParseResult(
        topics: const [],
        entries: const [],
        moreUrl: null,
      );
    });
    final notifier = container.read(bookmarkSyncControllerProvider.notifier);

    final syncing = notifier.ensureFreshness();
    await started.future;

    final progress = container.read(bookmarkSyncControllerProvider);
    expect(progress.isSyncing, isTrue);
    expect(progress.isInitialSync, isTrue);

    gate.complete();
    await syncing;

    expect(
      container.read(bookmarkSyncControllerProvider).phase,
      BookmarkSyncPhase.idle,
    );
    expect(await repository.allBookmarkIds('acct'), {1});
  });

  test('首次同步失败进入可重试状态，退避期内仅 force 会重试', () async {
    var requests = 0;
    final container = createContainer((_) async {
      requests++;
      throw Exception('offline');
    });
    final notifier = container.read(bookmarkSyncControllerProvider.notifier);

    await notifier.ensureFreshness();
    final failed = container.read(bookmarkSyncControllerProvider);
    expect(failed.isFailed, isTrue);
    expect(failed.isInitialSync, isTrue);
    expect(requests, 1);

    await notifier.ensureFreshness();
    expect(requests, 1);

    await notifier.ensureFreshness(force: true);
    expect(requests, 2);
  });

  test('首次同步部分写入后失败仍遵守退避', () async {
    var requests = 0;
    final container = createContainer((page) async {
      requests++;
      if (page == 0) {
        return BookmarkPageParseResult(
          topics: const [],
          entries: [_entry(1)],
          moreUrl: 'next',
        );
      }
      throw Exception('offline');
    });
    final notifier = container.read(bookmarkSyncControllerProvider.notifier);

    await notifier.ensureFreshness();
    expect(requests, 2);
    expect(await repository.allBookmarkIds('acct'), {1});
    expect(container.read(bookmarkSyncControllerProvider).isFailed, isTrue);

    await notifier.ensureFreshness();
    expect(requests, 2);

    await notifier.ensureFreshness(force: true);
    expect(requests, 4);
    expect(
      container.read(bookmarkSyncControllerProvider).isInitialSync,
      isTrue,
    );
  });

  test('同步进行中时忽略重复保鲜与手动全量请求', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var requests = 0;
    final container = createContainer((page) async {
      requests++;
      if (!started.isCompleted) started.complete();
      await gate.future;
      return BookmarkPageParseResult(
        topics: const [],
        entries: const [],
        moreUrl: null,
      );
    });
    final notifier = container.read(bookmarkSyncControllerProvider.notifier);

    final first = notifier.ensureFreshness();
    await started.future;
    await notifier.ensureFreshness();
    expect(await notifier.manualFullSync(), isNull);
    expect(requests, 1);

    gate.complete();
    await first;
  });

  test('同步中请求拉取第一页会在同步完成后补跑', () async {
    final gate = Completer<void>();
    final syncStarted = Completer<void>();
    final pendingPullStarted = Completer<void>();
    var requests = 0;
    final container = createContainer((_) async {
      requests++;
      if (requests == 1) {
        syncStarted.complete();
        await gate.future;
      } else if (requests == 2) {
        pendingPullStarted.complete();
      }
      return BookmarkPageParseResult(
        topics: const [],
        entries: const [],
        moreUrl: null,
      );
    });
    final notifier = container.read(bookmarkSyncControllerProvider.notifier);

    final syncing = notifier.ensureFreshness();
    await syncStarted.future;
    await notifier.pullFirstPage();
    expect(requests, 1);

    gate.complete();
    await syncing;
    await pendingPullStarted.future;
    expect(requests, 2);
  });

  test('reset 后旧账号同步完成不得覆盖 idle 状态', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final container = createContainer((_) async {
      if (!started.isCompleted) started.complete();
      await gate.future;
      return BookmarkPageParseResult(
        topics: const [],
        entries: const [],
        moreUrl: null,
      );
    });
    final notifier = container.read(bookmarkSyncControllerProvider.notifier);

    final syncing = notifier.ensureFreshness();
    await started.future;
    expect(container.read(bookmarkSyncControllerProvider).isSyncing, isTrue);

    notifier.reset();
    expect(
      container.read(bookmarkSyncControllerProvider).phase,
      BookmarkSyncPhase.idle,
    );

    gate.complete();
    await syncing;
    expect(
      container.read(bookmarkSyncControllerProvider).phase,
      BookmarkSyncPhase.idle,
    );
  });
}
