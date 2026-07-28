import 'dart:async';

import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/export_history_dao.dart';
import 'user_content_providers.dart';

/// DAO 单例 provider，便于测试替换。
final exportHistoryDaoProvider = Provider<ExportHistoryDao>((ref) {
  return ExportHistoryDao();
});

/// 当前账号的导出历史列表状态。
///
/// 监听 [currentUsernameProvider]：账号切换或首次解析完成时，重建 notifier
/// 并从 Hive 重读。add/remove/clear 都现取当前 username，避免点击导出时
/// username 仍处于 loading 而丢失写入。
final exportHistoryProvider =
    StateNotifierProvider<ExportHistoryNotifier, List<ExportHistoryEntry>>((
      ref,
    ) {
      final dao = ref.watch(exportHistoryDaoProvider);
      final usernameAsync = ref.watch(currentUsernameProvider);
      return ExportHistoryNotifier(
        dao: dao,
        accountId: usernameAsync.asData?.value,
        accountIdResolver: () => ref.read(currentUsernameProvider.future),
      );
    });

class ExportHistoryNotifier extends StateNotifier<List<ExportHistoryEntry>> {
  ExportHistoryNotifier({
    required ExportHistoryDao dao,
    required Future<String?> Function() accountIdResolver,
    String? accountId,
  }) : _dao = dao,
       _accountId = accountId,
       _resolveAccountId = accountIdResolver,
       super(const []) {
    if (accountId != null && accountId.isNotEmpty) {
      _bootstrap(accountId);
    }
  }

  final ExportHistoryDao _dao;
  final Future<String?> Function() _resolveAccountId;
  String? _accountId;

  Future<String?> _ensureAccountId() async {
    if (_accountId != null && _accountId!.isNotEmpty) return _accountId;
    try {
      final id = await _resolveAccountId();
      if (id != null && id.isNotEmpty) _accountId = id;
      return _accountId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _bootstrap(String accountId) async {
    try {
      final entries = await _dao.readAll(accountId);
      if (!mounted) return;
      state = entries;
    } catch (e, st) {
      debugPrint('[ExportHistory] load failed: $e\n$st');
    }
  }

  /// 添加一条记录（最新的在前）。
  Future<void> add(ExportHistoryEntry entry) async {
    final accountId = await _ensureAccountId();
    if (accountId == null || accountId.isEmpty) return;
    await _dao.upsertOne(accountId, entry);
    if (!mounted) return;
    state = [entry, ...state.where((e) => e.id != entry.id)];
  }

  Future<void> remove(String id) async {
    final accountId = await _ensureAccountId();
    if (accountId == null || accountId.isEmpty) return;
    await _dao.deleteOne(accountId, id);
    if (!mounted) return;
    state = state.where((e) => e.id != id).toList(growable: false);
  }

  Future<void> clear() async {
    final accountId = await _ensureAccountId();
    if (accountId == null || accountId.isEmpty) return;
    await _dao.clearAccount(accountId);
    if (!mounted) return;
    state = const [];
  }

  /// 强制从 Hive 重读，处理外部改动后的刷新。
  Future<void> refresh() async {
    final accountId = await _ensureAccountId();
    if (accountId == null || accountId.isEmpty) return;
    await _bootstrap(accountId);
  }
}
