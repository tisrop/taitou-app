import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../../models/user_action.dart';
import '../../../providers/discourse_providers.dart';
import '../../../utils/load_more_coordinator.dart';
import '../../../utils/pagination_helper.dart';
import '../../../widgets/common/layout/paged_list_footer.dart';
import '../../../widgets/user/user_profile_skeleton.dart';
import '../../../l10n/s.dart';
import '../widgets/user_profile_items.dart';

/// 用户主页通用 Activity 列表(Activities/Topics/Replies/Likes 共用)。
///
/// 自带缓存 + offset 分页 + loading + 失败重试,filter 参数区分四类动作。
/// 从 _UserProfilePageState 的 _actionsCache/_loadActions/_buildActionList 通用分支抽出。
class UserActivityList extends ConsumerStatefulWidget {
  const UserActivityList({super.key, required this.username, required this.filter});

  final String username;
  final String filter;

  @override
  ConsumerState<UserActivityList> createState() => _UserActivityListState();
}

class _UserActivityListState extends ConsumerState<UserActivityList> {
  static final _paginationHelper = PaginationHelpers.forList<UserAction>(
    keyExtractor: (a) => '${a.topicId}_${a.postNumber}_${a.actionType}',
    expectedPageSize: 30,
  );

  final List<UserAction> _cache = [];
  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  bool _hasMore = true;
  bool _loading = true;
  bool _loadMoreFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool loadMore = false}) async {
    if (_loading && _cache.isNotEmpty) return;

    if (!loadMore) {
      _loadMoreCoordinator.resetCooldown();
    }

    setState(() {
      _loading = true;
      _loadMoreFailed = false;
    });

    try {
      final service = ref.read(discourseServiceProvider);
      final offset = loadMore ? _cache.length : 0;
      final response = await service.getUserActions(
        widget.username,
        filter: widget.filter,
        offset: offset,
      );

      if (mounted) {
        setState(() {
          if (loadMore) {
            final currentState = PaginationState<UserAction>(items: _cache);
            final result = _paginationHelper.processLoadMore(
              currentState,
              PaginationResult(items: response.actions, expectedPageSize: 30),
            );
            _cache
              ..clear()
              ..addAll(result.items);
            _hasMore = result.hasMore;
          } else {
            final result = _paginationHelper.processRefresh(
              PaginationResult(items: response.actions, expectedPageSize: 30),
            );
            _cache
              ..clear()
              ..addAll(result.items);
            _hasMore = result.hasMore;
          }
          _loading = false;
          _loadMoreFailed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (loadMore) {
            _loadMoreFailed = true;
          }
        });
      }
    }
  }

  Future<void> _loadMore() async {
    await _loadMoreCoordinator.loadMore(
      loadMore: () => _load(loadMore: true),
      hasMore: () => _hasMore,
      isActive: () => mounted,
      progressCount: () => _cache.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 优先检查 loading 状态
    if (_loading && _cache.isEmpty) {
      return const UserActionListSkeleton();
    }

    // 空状态
    if (_cache.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.inbox_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(context.l10n.userProfile_noContent, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          final distance =
              notification.metrics.maxScrollExtent - notification.metrics.pixels;
          if (_loadMoreCoordinator.shouldTriggerForDistance(distance)) {
            _loadMore();
          }
        }
        return false;
      },
      child: M3eRefreshIndicator(
        onRefresh: () => _load(),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _cache.length + 1,
          itemBuilder: (context, index) {
            if (index == _cache.length) {
              return PagedListFooter(
                hasMore: _hasMore,
                isLoadingMore: _loadMoreCoordinator.isRunning && _loading,
                isLoadMoreFailed: _loadMoreFailed,
                onRetry: _loadMore,
              );
            }
            return UserProfileItems.actionItem(context, _cache[index]);
          },
        ),
      ),
    );
  }
}
