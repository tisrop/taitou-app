import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../../../models/topic.dart';
import '../../../providers/discourse_providers.dart';
import '../../../providers/preferences_provider.dart';
import '../../../utils/load_more_coordinator.dart';
import '../../../widgets/common/layout/paged_list_footer.dart';
import '../../../widgets/topic/topic_item_builder.dart';
import '../../../widgets/topic/topic_list_skeleton.dart';
import '../../../l10n/s.dart';
import '../../topic_detail_page/topic_detail_page.dart';

/// 用户主页「投票」tab:用户投过票的话题列表(page 分页)。
///
/// 从 _UserProfilePageState 的 _votes*/_loadVotes/_buildVotesList 抽出。
/// 额外 watch preferencesProvider.longPressPreview(话题卡长按预览开关)。
class VotesTab extends ConsumerStatefulWidget {
  const VotesTab({super.key, required this.username});

  final String username;

  @override
  ConsumerState<VotesTab> createState() => _VotesTabState();
}

class _VotesTabState extends ConsumerState<VotesTab> {
  final LoadMoreCoordinator _loadMoreCoordinator = LoadMoreCoordinator();
  List<Topic>? _cache;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadMoreFailed = false;
  int _page = 0;

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
      final page = loadMore ? _page + 1 : 0;
      final response = await service.getVotedTopics(widget.username, page: page);

      if (mounted) {
        setState(() {
          if (loadMore) {
            // 按 id 去重后追加
            final existing = (_cache ?? []).map((t) => t.id).toSet();
            final fresh = response.topics.where((t) => !existing.contains(t.id));
            _cache = [...?_cache, ...fresh];
          } else {
            _cache = response.topics;
          }
          _page = page;
          _hasMore = response.moreTopicsUrl != null;
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
    final topics = _cache;

    // 优先检查 loading 状态
    if (_loading && topics == null) {
      return const TopicListSkeleton();
    }

    // 空状态
    if (topics == null || topics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.how_to_vote_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(context.l10n.userProfile_noVotes, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    final enableLongPress = ref.watch(preferencesProvider).longPressPreview;

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
          padding: const EdgeInsets.all(12),
          itemCount: topics.length + 1,
          itemBuilder: (context, index) {
            if (index == topics.length) {
              return PagedListFooter(
                hasMore: _hasMore,
                isLoadingMore: _loadMoreCoordinator.isRunning && _loading,
                isLoadMoreFailed: _loadMoreFailed,
                onRetry: _loadMore,
              );
            }
            final topic = topics[index];
            return buildTopicItem(
              context: context,
              topic: topic,
              isSelected: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TopicDetailPage(
                    topicId: topic.id,
                    scrollToPostNumber: topic.lastReadPostNumber,
                  ),
                ),
              ),
              enableLongPress: enableLongPress,
            );
          },
        ),
      ),
    );
  }
}
