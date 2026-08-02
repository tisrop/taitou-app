import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_ui/m3e_ui.dart';

import '../l10n/s.dart';
import '../models/gamification.dart';
import '../navigation/nav_action_bus.dart';
import '../services/app_logger.dart';
import '../services/discourse/discourse_service.dart';
import '../widgets/common/visual/smart_avatar.dart';
import 'user_profile_page/user_profile_page.dart';

typedef GamificationPageLoader =
    Future<GamificationLeaderboardResponse> Function(int page);

/// discourse-gamification 积分排行榜。
class GamificationLeaderboardPage extends ConsumerStatefulWidget {
  const GamificationLeaderboardPage({
    super.key,
    this.isActive = true,
    this.loadPage,
  });

  final bool isActive;
  final GamificationPageLoader? loadPage;

  @override
  ConsumerState<GamificationLeaderboardPage> createState() =>
      _GamificationLeaderboardPageState();
}

class _GamificationLeaderboardPageState
    extends ConsumerState<GamificationLeaderboardPage> {
  final ScrollController _scrollController = ScrollController();
  final List<GamificationUserScore> _users = [];

  GamificationLeaderboardResponse? _response;
  Object? _error;
  int _page = 0;
  int _pageSize = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<GamificationLeaderboardResponse> _fetch(int page) {
    final loader = widget.loadPage;
    if (loader != null) return loader(page);
    return DiscourseService().getGamificationLeaderboard(page: page);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _isLoadingMore) return;
    if (_scrollController.position.extentAfter < 320) {
      _loadMore();
    }
  }

  void _publishScrollProgress(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return;
    final progress = notification.metrics.pixels.clamp(0.0, double.infinity);
    final current = ref.read(
      navScrollProgressProvider(NavEntryIds.leaderboard),
    );
    final atZero = progress == 0 && current != 0;
    final crossed =
        (progress >= navScrollIconThreshold) !=
        (current >= navScrollIconThreshold);
    if (!atZero && !crossed && (progress - current).abs() < 4) return;
    ref
            .read(navScrollProgressProvider(NavEntryIds.leaderboard).notifier)
            .state =
        progress;
  }

  Future<void> _loadInitial() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _response = response;
        _users
          ..clear()
          ..addAll(response.users);
        _page = 0;
        _pageSize = response.users.length;
        _hasMore = response.users.isNotEmpty && !response.isPreparing;
        _isLoading = false;
      });
      ref.resetNavScrollProgress(NavEntryIds.leaderboard);
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppLogger.error(
        '积分排行榜加载失败',
        tag: 'Gamification',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await _fetch(nextPage);
      if (!mounted) return;

      final seen = _users.map((user) => user.id).toSet();
      final newUsers = response.users
          .where((user) => seen.add(user.id))
          .toList(growable: false);
      setState(() {
        _users.addAll(newUsers);
        _response = GamificationLeaderboardResponse(
          leaderboard: response.leaderboard,
          users: List.unmodifiable(_users),
          personal: response.personal ?? _response?.personal,
          reason: response.reason,
        );
        _page = nextPage;
        _hasMore = _pageSize > 0 && response.users.length >= _pageSize;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.gamification_loadMoreFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _handleNavAction(NavActionEvent? event) {
    if (event == null || event.targetId != NavEntryIds.leaderboard) return;
    if (!widget.isActive) return;
    switch (event.action) {
      case NavAction.scrollToTop:
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        break;
      case NavAction.refresh:
        _loadInitial();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(navActionBusProvider, (_, event) => _handleNavAction(event));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.gamification_title),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadInitial,
            tooltip: context.l10n.common_refresh,
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: LoadingSpinner());
    }
    if (_error != null) {
      return _MessageState(
        icon: Symbols.error_rounded,
        message: context.l10n.common_loadFailed,
        actionLabel: context.l10n.common_retry,
        onAction: _loadInitial,
      );
    }
    if (_response?.isPreparing == true) {
      return _MessageState(
        icon: Symbols.hourglass_top_rounded,
        message: context.l10n.gamification_preparing,
        actionLabel: context.l10n.common_refresh,
        onAction: _loadInitial,
      );
    }
    if (_users.isEmpty) {
      return _MessageState(
        icon: Symbols.emoji_events_rounded,
        message: context.l10n.gamification_empty,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _publishScrollProgress(notification);
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _loadInitial,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (_response?.personal != null)
              SliverToBoxAdapter(
                child: _PersonalRankBand(personal: _response!.personal!),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  _response!.leaderboard.name.isNotEmpty
                      ? _response!.leaderboard.name
                      : context.l10n.gamification_title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SliverList.separated(
              itemCount: _users.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 76, endIndent: 16),
              itemBuilder: (context, index) => _LeaderboardRow(
                score: _users[index],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        UserProfilePage(username: _users[index].username),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 64 + MediaQuery.paddingOf(context).bottom,
                child: _isLoadingMore
                    ? const Center(child: LoadingSpinner(size: 20))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalRankBand extends StatelessWidget {
  const _PersonalRankBand({required this.personal});

  final GamificationPersonalScore personal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(
              Symbols.emoji_events_rounded,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.gamification_yourRank,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '#${personal.position}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${personal.user.totalScore} ${context.l10n.gamification_points}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.score, required this.onTap});

  final GamificationUserScore score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTopThree = score.position >= 1 && score.position <= 3;
    final rankColor = switch (score.position) {
      1 => const Color(0xFFC28B00),
      2 => const Color(0xFF6B7280),
      3 => const Color(0xFFA65F2B),
      _ => theme.colorScheme.onSurfaceVariant,
    };

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: isTopThree
                    ? Icon(
                        Symbols.workspace_premium_rounded,
                        color: rankColor,
                        size: 25,
                      )
                    : Text(
                        '${score.position}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: rankColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              SmartAvatar(
                imageUrl: score.getAvatarUrl(size: 96),
                radius: 20,
                fallbackText: score.username,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      score.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (score.name?.isNotEmpty == true &&
                        score.name != score.username)
                      Text(
                        score.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${score.totalScore}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isTopThree ? rankColor : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                context.l10n.gamification_points,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
