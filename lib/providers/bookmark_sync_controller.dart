import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bookmarks_reconciler.dart';
import 'bookmarks_repository.dart';
import 'current_username_provider.dart';

enum BookmarkSyncPhase { idle, syncing, failed }

/// 全局书签同步状态，与列表数据和本地分页状态分离。
class BookmarkSyncState {
  const BookmarkSyncState({
    this.phase = BookmarkSyncPhase.idle,
    this.mode,
    this.isInitialSync = false,
  });

  final BookmarkSyncPhase phase;
  final ReconcileMode? mode;

  /// 本地为空时触发的首次同步，用于区分同步中、失败和真正空列表。
  final bool isInitialSync;

  bool get isSyncing => phase == BookmarkSyncPhase.syncing;
  bool get isFailed => phase == BookmarkSyncPhase.failed;
}

/// 书签同步控制器。列表 notifier 只负责本地读取与分页。
class BookmarkSyncController extends Notifier<BookmarkSyncState> {
  static const Duration incrementalThrottle = Duration(minutes: 5);
  static const Duration initialRetryBackoff = Duration(seconds: 30);

  final Map<String, DateTime> _lastFreshAt = {};
  final Map<String, DateTime> _lastInitialAttemptAt = {};
  Future<void>? _inFlight;
  bool _pullInFlight = false;
  bool _pullPending = false;
  int _generation = 0;

  @override
  BookmarkSyncState build() => const BookmarkSyncState();

  /// 本地为空时全量同步；全量到期时全量同步；其余情况节流增量同步。
  Future<void> ensureFreshness({bool force = false}) async {
    if (_inFlight != null) return;
    final generation = _generation;
    final completer = Completer<void>();
    _inFlight = completer.future;
    try {
      await _ensureFreshness(force: force, generation: generation);
    } finally {
      if (_generation == generation) {
        _inFlight = null;
      }
      completer.complete();
    }
  }

  Future<void> _ensureFreshness({
    required bool force,
    required int generation,
  }) async {
    final accountId = await _accountId();
    if (accountId == null || !_isCurrent(generation)) return;
    final reconciler = await ref.read(bookmarksReconcilerProvider.future);
    if (!_isCurrent(generation)) return;
    final repository = ref.read(bookmarksRepositoryProvider);
    final localEmpty = (await repository.idsOrderedByUpdated(
      accountId,
    )).isEmpty;
    if (!_isCurrent(generation)) return;

    final now = DateTime.now();
    final lastAttempt = _lastInitialAttemptAt[accountId];
    final isRecoveringInitialSync = lastAttempt != null;
    if (localEmpty || isRecoveringInitialSync) {
      if (!force &&
          lastAttempt != null &&
          now.difference(lastAttempt) < initialRetryBackoff) {
        return;
      }
      _lastInitialAttemptAt[accountId] = now;
      await _run(
        accountId,
        reconciler,
        mode: ReconcileMode.full,
        initial: true,
        generation: generation,
      );
      return;
    }

    if (reconciler.isFullReconcileDue(accountId)) {
      await _run(
        accountId,
        reconciler,
        mode: ReconcileMode.full,
        initial: false,
        generation: generation,
      );
      return;
    }

    final lastFresh = _lastFreshAt[accountId];
    if (!force &&
        lastFresh != null &&
        now.difference(lastFresh) < incrementalThrottle) {
      return;
    }
    await _run(
      accountId,
      reconciler,
      mode: ReconcileMode.incremental,
      initial: false,
      generation: generation,
    );
  }

  /// 手动全量同步。已有同步进行中时返回 null。
  Future<ReconcileReport?> manualFullSync() async {
    if (_inFlight != null) return null;
    final generation = _generation;
    final completer = Completer<void>();
    _inFlight = completer.future;
    try {
      final accountId = await _accountId();
      if (accountId == null || !_isCurrent(generation)) return null;
      final reconciler = await ref.read(bookmarksReconcilerProvider.future);
      if (!_isCurrent(generation)) return null;
      final localEmpty =
          (await ref
                  .read(bookmarksRepositoryProvider)
                  .idsOrderedByUpdated(accountId))
              .isEmpty;
      if (!_isCurrent(generation)) return null;
      final initial =
          localEmpty || _lastInitialAttemptAt.containsKey(accountId);
      if (initial) {
        _lastInitialAttemptAt[accountId] = DateTime.now();
      }
      return await _run(
        accountId,
        reconciler,
        mode: ReconcileMode.full,
        initial: initial,
        generation: generation,
      );
    } finally {
      if (_generation == generation) {
        _inFlight = null;
      }
      completer.complete();
    }
  }

  /// 拉取第一页并写入缓存，用于下拉刷新和增改后的静默保鲜。
  Future<void> pullFirstPage() async {
    if (_pullInFlight || state.isSyncing) {
      _pullPending = true;
      return;
    }
    final generation = _generation;
    _pullPending = false;
    _pullInFlight = true;
    try {
      final accountId = await _accountId();
      if (accountId == null || !_isCurrent(generation)) return;
      final reconciler = await ref.read(bookmarksReconcilerProvider.future);
      if (!_isCurrent(generation)) return;
      await reconciler.pullToRefresh(accountId);
    } catch (_) {
      // 静默保鲜失败由下一次对账补齐。
    } finally {
      if (_generation == generation) {
        _pullInFlight = false;
        _runPendingPullIfNeeded();
      }
    }
  }

  /// 服务端删除成功后立即清理本地缓存。
  Future<void> purgeLocal(int bookmarkId) async {
    try {
      final accountId = await _accountId();
      if (accountId == null || !ref.mounted) return;
      await ref
          .read(bookmarksRepositoryProvider)
          .deleteOne(accountId, bookmarkId);
    } catch (_) {
      // 本地缓存清理失败由下一次全量对账纠正。
    }
  }

  void reset() {
    _generation++;
    _inFlight = null;
    _pullInFlight = false;
    _pullPending = false;
    _lastFreshAt.clear();
    _lastInitialAttemptAt.clear();
    state = const BookmarkSyncState();
  }

  Future<ReconcileReport?> _run(
    String accountId,
    BookmarksReconciler reconciler, {
    required ReconcileMode mode,
    required bool initial,
    required int generation,
  }) async {
    if (!_isCurrent(generation)) return null;
    state = BookmarkSyncState(
      phase: BookmarkSyncPhase.syncing,
      mode: mode,
      isInitialSync: initial,
    );

    ReconcileReport? report;
    try {
      report = mode == ReconcileMode.full
          ? await reconciler.fullReconcile(accountId)
          : await reconciler.incrementalReconcile(accountId);
    } catch (_) {
      report = null;
    }

    final failed =
        report == null || report.stopReason == ReconcileStopReason.errored;
    if (!_isCurrent(generation)) return report;
    if (failed) {
      state = BookmarkSyncState(
        phase: BookmarkSyncPhase.failed,
        isInitialSync: initial,
      );
    } else {
      if (initial) {
        _lastInitialAttemptAt.remove(accountId);
      }
      _lastFreshAt[accountId] = DateTime.now();
      state = const BookmarkSyncState();
    }
    _runPendingPullIfNeeded();
    return report;
  }

  void _runPendingPullIfNeeded() {
    if (!_pullPending || _pullInFlight || state.isSyncing) return;
    _pullPending = false;
    unawaited(pullFirstPage());
  }

  Future<String?> _accountId() async {
    try {
      return await ref.read(currentUsernameProvider.future);
    } catch (_) {
      return null;
    }
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;
}

final bookmarkSyncControllerProvider =
    NotifierProvider<BookmarkSyncController, BookmarkSyncState>(
      BookmarkSyncController.new,
    );
