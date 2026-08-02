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

/// 用户主页「回应」tab:emoji 回应列表(游标分页)。
///
/// 从 _UserProfilePageState 的 _reactions*/_loadReactions/_buildReactionList 抽出。
class ReactionsTab extends ConsumerStatefulWidget {
  const ReactionsTab({super.key, required this.username});

  final String username;

  @override
  ConsumerState<ReactionsTab> createState() => _ReactionsTabState();
}

class _ReactionsTabState extends ConsumerState<ReactionsTab> {
  static final _paginationHelper = PaginationHelpers.forList<UserReaction>(
    keyExtractor: (r) => r.id,
    expectedPageSize: 20,
  );

  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  List<UserReaction>? _cache;
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
      final response = await service.getUserReactions(widget.username, beforeReactionUserId: beforeId);

      if (mounted) {
        setState(() {
          if (loadMore) {
            final currentState = PaginationState<UserReaction>(items: _cache ?? []);
            final result = _paginationHelper.processLoadMore(
              currentState,
              PaginationResult(items: response.reactions, expectedPageSize: 20),
            );
            _cache = result.items;
            _hasMore = result.hasMore;
          } else {
            final result = _paginationHelper.processRefresh(
              PaginationResult(items: response.reactions, expectedPageSize: 20),
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
    final reactions = _cache;

    // 优先检查 loading 状态
    if (_loading && reactions == null) {
      return const UserActionListSkeleton();
    }

    // 空状态
    if (reactions == null || reactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.emoji_emotions_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(context.l10n.userProfile_noReactions, style: TextStyle(color: Colors.grey[600])),
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
          itemCount: reactions.length + 1,
          itemBuilder: (context, index) {
            if (index == reactions.length) {
              return PagedListFooter(
                hasMore: _hasMore,
                isLoadingMore: _loadMoreCoordinator.isRunning && _loading,
                isLoadMoreFailed: _loadMoreFailed,
                onRetry: _loadMore,
              );
            }
            return UserProfileItems.reactionItem(context, reactions[index]);
          },
        ),
      ),
    );
  }
}
