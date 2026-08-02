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

/// 用户主页「Boost」tab:用户发出过的 Boost 列表(游标分页)。
///
/// 从 _UserProfilePageState 的 _boosts*/_loadBoosts/_buildBoostList 抽出。
class BoostsTab extends ConsumerStatefulWidget {
  const BoostsTab({super.key, required this.username});

  final String username;

  @override
  ConsumerState<BoostsTab> createState() => _BoostsTabState();
}

class _BoostsTabState extends ConsumerState<BoostsTab> {
  static final _paginationHelper = PaginationHelpers.forList<UserBoost>(
    keyExtractor: (b) => b.id,
    expectedPageSize: 20,
  );

  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  List<UserBoost>? _cache;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadMoreFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool loadMore = false}) async {
    if (_loading && _cache != null) return;

    if (!loadMore) {
      _loadMoreCoordinator.resetCooldown();
    }

    setState(() {
      _loading = true;
      _loadMoreFailed = false;
    });

    try {
      final service = ref.read(discourseServiceProvider);
      final beforeId = loadMore && _cache != null && _cache!.isNotEmpty
          ? _cache!.last.id
          : null;
      final response = await service.getUserBoostsGiven(widget.username, beforeBoostId: beforeId);

      if (mounted) {
        setState(() {
          if (loadMore) {
            final currentState = PaginationState<UserBoost>(items: _cache ?? []);
            final result = _paginationHelper.processLoadMore(
              currentState,
              PaginationResult(items: response.boosts, expectedPageSize: 20),
            );
            _cache = result.items;
            _hasMore = result.hasMore;
          } else {
            final result = _paginationHelper.processRefresh(
              PaginationResult(items: response.boosts, expectedPageSize: 20),
            );
            _cache = result.items;
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
      progressCount: () => _cache?.length ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final boosts = _cache;

    // 优先检查 loading 状态
    if (_loading && boosts == null) {
      return const UserActionListSkeleton();
    }

    // 空状态
    if (boosts == null || boosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.rocket_launch_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(context.l10n.userProfile_noBoosts, style: TextStyle(color: Colors.grey[600])),
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
          itemCount: boosts.length + 1,
          itemBuilder: (context, index) {
            if (index == boosts.length) {
              return PagedListFooter(
                hasMore: _hasMore,
                isLoadingMore: _loadMoreCoordinator.isRunning && _loading,
                isLoadMoreFailed: _loadMoreFailed,
                onRetry: _loadMore,
              );
            }
            return UserProfileItems.boostItem(context, boosts[index]);
          },
        ),
      ),
    );
  }
}
