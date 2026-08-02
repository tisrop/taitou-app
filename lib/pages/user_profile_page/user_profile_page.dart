import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/user.dart';
import '../../providers/discourse_providers.dart';
import '../../services/discourse_cache_manager.dart';
import '../../utils/time_utils.dart';
import '../../widgets/common/text/relative_time_text.dart';
import '../../utils/number_utils.dart';
import 'package:dio/dio.dart';
import '../../utils/url_helper.dart';
import '../../services/app_error_handler.dart';
import '../../utils/share_utils.dart';
import '../../providers/preferences_provider.dart';
import '../../widgets/common/visual/flair_badge.dart';
import '../../widgets/common/visual/grain_gradient_background.dart';
import '../../widgets/common/misc/error_view.dart';
import '../../widgets/common/visual/smart_avatar.dart';
import '../../widgets/user/avatar_action_menu.dart';
import '../../widgets/content/collapsed_html_content.dart';
import '../../widgets/post/reply_sheet.dart';
import '../../widgets/user/user_profile_skeleton.dart';
import '../../widgets/user/ignore_duration_picker.dart';
import '../../services/toast_service.dart';
import '../search_page.dart';
import '../follow_list_page.dart';
import '../image_viewer_page.dart';
import 'package:common_ui/common_ui.dart';
import '../../l10n/s.dart';
import 'tabs/user_activity_list.dart';
import 'tabs/reactions_tab.dart';
import 'tabs/boosts_tab.dart';
import 'tabs/votes_tab.dart';
import 'tabs/solved_tab.dart';
import 'widgets/summary_tab.dart';
import 'widgets/user_info_dialog.dart';
import 'widgets/user_profile_items.dart';

/// 用户个人页
class UserProfilePage extends ConsumerStatefulWidget {
  final String username;

  const UserProfilePage({super.key, required this.username});

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  User? _user;
  UserSummary? _summary;
  bool _isLoading = true;
  Object? _error;
  StackTrace? _errorStack;

  // 关注状态
  bool _isFollowed = false;
  bool _isFollowLoading = false;

  // 订阅级别: normal / mute / ignore
  String _notificationLevel = 'normal';

  // tab 对应的 filter: summary=总结, 4,5=全部(话题+回复), 4=话题, 5=回复, 1=点赞,
  // reactions=回应, boosts=Boost, votes=投票, solved=已解决
  // 各 tab 的数据加载与分页已下沉到对应的 tab widget(见 tabs/),这里只保留
  // filter→widget 的映射。
  static const List<String> _tabFilters = [
    'summary', '4,5', '4', '5', '1', 'reactions', 'boosts', 'votes', 'solved',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabFilters.length, vsync: this);
    _loadUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      final service = ref.read(discourseServiceProvider);
      // 并行加载用户基本信息和统计数据
      final results = await Future.wait([
        service.getUser(widget.username),
        service.getUserSummary(widget.username),
      ]);

      if (mounted) {
        final user = results[0] as User;
        setState(() {
          _user = user;
          _summary = results[1] as UserSummary;
          _isFollowed = user.isFollowed ?? false;
          _notificationLevel = user.ignored == true
              ? 'ignore'
              : user.muted == true
                  ? 'mute'
                  : 'normal';
          _isLoading = false;
        });
        // 总结 tab 数据已从 _summary 获取，无需额外加载
      }
    } catch (e, s) {
      if (mounted) {
        setState(() {
          _error = e;
          _errorStack = s;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_user == null || _isFollowLoading) return;

    setState(() => _isFollowLoading = true);

    try {
      final service = ref.read(discourseServiceProvider);
      if (_isFollowed) {
        await service.unfollowUser(_user!.username);
      } else {
        await service.followUser(_user!.username);
      }

      if (mounted) {
        setState(() {
          _isFollowed = !_isFollowed;
        });
      }
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) {
        setState(() => _isFollowLoading = false);
      }
    }
  }

  /// 打开私信对话框
  void _openMessageDialog() {
    if (_user == null) return;

    showReplySheet(
      context: context,
      targetUsername: _user!.username,
    );
  }

  /// 打开用户内容搜索
  void _openUserSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchPage(initialQuery: '@${widget.username}'),
      ),
    );
  }

  /// 分享用户
  void _shareUser() {
    final user = ref.read(currentUserProvider).value;
    final username = user?.username ?? '';
    final prefs = ref.read(preferencesProvider);
    final url = ShareUtils.buildShareUrl(
      path: '/u/${widget.username}',
      username: username,
      anonymousShare: prefs.anonymousShare,
    );
    SharePlus.instance.share(ShareParams(text: url));
  }

  /// 设置用户订阅级别
  Future<void> _setNotificationLevel(String level) async {
    if (_user == null) return;

    // 如果是 ignore，需要先选择时长
    if (level == 'ignore') {
      final expiringAt = await _showIgnoreDurationPicker();
      if (expiringAt == null) return; // 用户取消

      final oldLevel = _notificationLevel;
      setState(() => _notificationLevel = 'ignore');
      try {
        final service = ref.read(discourseServiceProvider);
        await service.updateUserNotificationLevel(
          _user!.username,
          level: 'ignore',
          expiringAt: expiringAt,
        );
        if (mounted) {
          setState(() {
            _user = _user!.copyWith(muted: false, ignored: true);
          });
          ToastService.showSuccess(S.current.userProfile_setToIgnore);
        }
      } catch (_) {
        if (mounted) setState(() => _notificationLevel = oldLevel);
      }
      return;
    }

    final oldLevel = _notificationLevel;
    setState(() => _notificationLevel = level);
    try {
      final service = ref.read(discourseServiceProvider);
      await service.updateUserNotificationLevel(_user!.username, level: level);
      if (mounted) {
        setState(() {
          _user = _user!.copyWith(
            muted: level == 'mute',
            ignored: false,
          );
        });
        final label = level == 'mute' ? S.current.userProfile_setToMute : S.current.userProfile_restored;
        ToastService.showSuccess(label);
      }
    } catch (_) {
      if (mounted) setState(() => _notificationLevel = oldLevel);
    }
  }

  /// 显示忽略时长选择弹窗，返回 expiringAt 时间字符串
  Future<String?> _showIgnoreDurationPicker() => showIgnoreDurationPicker(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider).value;
    // 话题卡自定义样式:改设置触发 rebuild(投票 tab 的话题卡直读全局快照)
    ref.watch(preferencesProvider.select((p) => p.topicCardStyle));

    if (_isLoading) {
      return const UserProfileSkeleton();
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.username)),
        body: ErrorView(
          error: _error!,
          stackTrace: _errorStack,
          onRetry: () {
            setState(() {
              _isLoading = true;
              _error = null;
              _errorStack = null;
            });
            _loadUser();
          },
        ),
      );
    }

    // 计算 pinned header 高度
    final double pinnedHeaderHeight = kToolbarHeight + MediaQuery.of(context).padding.top + 36; // 36 是 TabBar 高度

    return Scaffold(
      body: ScrollConfiguration(
        // 禁用 overscroll indicator：Material 3 在 Android 上默认
        // StretchingOverscrollIndicator，与 NestedScrollView/SliverAppBar
        // 组合存在 framework bug（flutter/flutter #100967、#116522、#100538），
        // 表现为上滑松手时 tab 区域回弹抖动（与 topics_page 同因同修）。
        behavior: ScrollConfiguration.of(
          context,
        ).copyWith(scrollbars: false, overscroll: false),
        child: ExtendedNestedScrollView(
          controller: _scrollController,
          pinnedHeaderSliverHeightBuilder: () => pinnedHeaderHeight,
          onlyOneScrollInBody: true,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildSliverAppBar(context, theme, currentUser),
          ],
          body: TabBarView(
            controller: _tabController,
            children: _tabFilters.asMap().entries.map((entry) {
              final index = entry.key;
              final filter = entry.value;
              return ExtendedVisibilityDetector(
                uniqueKey: Key('tab_$index'),
                child: _buildTab(filter),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, ThemeData theme, User? currentUser) {
    final bgUrl = _user?.backgroundUrl;
    final hasBackground = bgUrl != null && bgUrl.isNotEmpty;
    // Standard toolbar height is usually 56.0 + status bar height
    final double pinnedHeight = kToolbarHeight + MediaQuery.of(context).padding.top;
    // 横屏时屏幕高度有限，限制 expandedHeight 不超过屏幕高度的 70%
    final screenHeight = MediaQuery.of(context).size.height;
    final double expandedHeight = 410.0.clamp(0.0, screenHeight * 0.7);

    // Check if there is any info to show (for the "About" popup)
    final hasBio = _user?.bio != null && _user!.bio!.isNotEmpty;
    final hasLocation = _user?.location != null && _user!.location!.isNotEmpty;
    final hasWebsite = _user?.website != null && _user!.website!.isNotEmpty;
    final hasJoinedAt = _user?.createdAt != null;
    final hasInfo = hasBio || hasLocation || hasWebsite || hasJoinedAt;

    // 检查是否是自己
    final isOwnProfile = currentUser != null && _user != null && currentUser.username == _user!.username;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent, // Transparent to show FlexibleSpaceBar background
      surfaceTintColor: Colors.transparent, // Prevent M3 tint
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(
          icon: const Icon(Symbols.search_rounded),
          onPressed: () => _openUserSearch(),
        ),
        if (_user != null && _user!.canSendPrivateMessageToUser != false)
          IconButton(
            onPressed: _openMessageDialog,
            icon: const Icon(Symbols.mail_rounded),
            tooltip: context.l10n.userProfile_message,
          ),
        SwipeDismissiblePopupMenuButton<String>(
          icon: const Icon(Symbols.more_vert_rounded),
          onSelected: (value) {
            switch (value) {
              case 'about':
                showUserInfoDialog(context, _user!);
              case 'share':
                _shareUser();
              case 'level_normal':
                _setNotificationLevel('normal');
              case 'level_mute':
                _setNotificationLevel('mute');
              case 'level_ignore':
                _setNotificationLevel('ignore');
            }
          },
          itemBuilder: (context) {
            final theme = Theme.of(context);
            return [
              PopupMenuItem<String>(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Symbols.info_rounded, size: 20, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 12),
                    Text(context.l10n.common_about),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Symbols.share_rounded, size: 20, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 12),
                    Text(context.l10n.userProfile_shareUser),
                  ],
                ),
              ),
              // 非自己才显示订阅级别选项
              if (!isOwnProfile && _user != null) ...[
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'level_normal',
                  child: Row(
                    children: [
                      Icon(Symbols.notifications_rounded, size: 20, color: theme.colorScheme.onSurface),
                      const SizedBox(width: 12),
                      Expanded(child: Text(context.l10n.userProfile_normal)),
                      if (_notificationLevel == 'normal')
                        Icon(Symbols.check_rounded, size: 18, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
                if (_user!.canMuteUser != false)
                  PopupMenuItem<String>(
                    value: 'level_mute',
                    child: Row(
                      children: [
                        Icon(Symbols.notifications_off_rounded, size: 20, color: theme.colorScheme.onSurface),
                        const SizedBox(width: 12),
                        Expanded(child: Text(context.l10n.userProfile_mute)),
                        if (_notificationLevel == 'mute')
                          Icon(Symbols.check_rounded, size: 18, color: theme.colorScheme.primary),
                      ],
                    ),
                  ),
                if (_user!.canIgnoreUser == true)
                  PopupMenuItem<String>(
                    value: 'level_ignore',
                    child: Row(
                      children: [
                        Icon(Symbols.visibility_off_rounded, size: 20, color: theme.colorScheme.onSurface),
                        const SizedBox(width: 12),
                        Expanded(child: Text(context.l10n.userProfile_ignored)),
                        if (_notificationLevel == 'ignore')
                          Icon(Symbols.check_rounded, size: 18, color: theme.colorScheme.primary),
                      ],
                    ),
                  ),
              ],
            ];
          },
        ),
      ],
      // Bottom 参数承载 TabBar，并应用圆角背景，这样它会“浮”在 FlexibleSpace 背景图之上
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(36),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.primary,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(height: 36, text: context.l10n.userProfile_tabSummary),
              Tab(height: 36, text: context.l10n.userProfile_tabActivity),
              Tab(height: 36, text: context.l10n.userProfile_tabTopics),
              Tab(height: 36, text: context.l10n.userProfile_tabReplies),
              Tab(height: 36, text: context.l10n.userProfile_tabLikes),
              Tab(height: 36, text: context.l10n.userProfile_tabReactions),
              Tab(height: 36, text: context.l10n.userProfile_tabBoosts),
              Tab(height: 36, text: context.l10n.userProfile_tabVotes),
              Tab(height: 36, text: context.l10n.userProfile_tabSolved),
            ],
          ),
          ),
        ),
      ),
      // Use a Stack to ensure a solid black background exists BEHIND the FlexibleSpaceBar
      flexibleSpace: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final currentHeight = constraints.biggest.height;
          final t = ((currentHeight - pinnedHeight) / (expandedHeight - pinnedHeight)).clamp(0.0, 1.0);
          
          // 标题透明度：收起时显示（当 t < 0.3 时完全显示，避免半透明）
          final titleOpacity = t < 0.3 ? 1.0 : (1.0 - ((t - 0.3) / 0.7)).clamp(0.0, 1.0);
          // 内容透明度：展开时显示
          final contentOpacity = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
          
          return Stack(
            fit: StackFit.expand,
            children: [
              // ===== 层 0: 背景 - shader 动画 + 径向渐变辉光 + 图片叠加 =====
              // 用 ClipRect 裁剪溢出，内部固定为 expandedHeight，防止收起时 shader 被压扁
              Positioned.fill(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: expandedHeight,
                    child: SizedBox(
                      height: expandedHeight,
                      child: const GrainGradientBackground(),
                    ),
                  ),
                ),
              ),
              if (hasBackground)
                Image(
                  image: discourseImageProvider(
                    UrlHelper.resolveUrlWithCdn(bgUrl),
                  ),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    if (wasSynchronouslyLoaded || frame != null) {
                      return AnimatedOpacity(
                        opacity: frame != null ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: child,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),

              // ===== 层 1: 统一压暗遮罩 - 随向上滑动变得更暗 =====
              Container(
                color: Color.lerp(
                  Colors.black.withValues(alpha:0.6), // 展开状态：默认更暗 (0.6)
                  Colors.black.withValues(alpha:0.85), // 收起状态：稍微透一点 (0.85)
                  Curves.easeOut.transform(1.0 - t), // 使用 easeOut 曲线优化滑动体验
                ),
              ),

              // ===== 层 2: 用户信息内容 - 展开时显示，收起时淡出 =====
              Positioned(
                left: 20,
                right: 20,
                bottom: 36 + 24, // TabBar 高度 + 间距
                child: Opacity(
                  opacity: contentOpacity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 头像、姓名、操作按钮一行
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 1. 头像 radius=36，flair 大小 30，偏移 right=-7, bottom=-4
                          GestureDetector(
                            onTap: () {
                              if (_user?.getAvatarUrl() != null) {
                                final avatarUrl = _user!.getAvatarUrl(size: 360);
                                ImageViewerPage.open(
                                  context,
                                  avatarUrl,
                                  heroTag: 'user_avatar_${_user!.username}',
                                );
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: AvatarWithFlair(
                                flairSize: 30,
                                flairRight: -7,
                                flairBottom: -4,
                                flairUrl: _user?.flairUrl,
                                flairName: _user?.flairName,
                                flairBgColor: _user?.flairBgColor,
                                flairColor: _user?.flairColor,
                                avatar: Hero(
                                  tag: 'user_avatar_${_user?.username ?? ''}',
                                  child: SmartAvatar(
                                    imageUrl: _user?.getAvatarUrl() != null
                                        ? _user!.getAvatarUrl(size: 144)
                                        : null,
                                    radius: 36,
                                    fallbackText: _user?.username,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          
                          // 2. 姓名、身份信息
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Row 1: Name + Status
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        (_user?.name?.isNotEmpty == true) ? _user!.name! : (_user?.username ?? ''),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          shadows: [Shadow(color: Colors.black45, offset: Offset(0, 1), blurRadius: 2)],
                                        ),
                                      ),
                                    ),
                                    if (_user?.status != null) ...[
                                      const SizedBox(width: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: _buildStatusEmoji(_user!.status!),
                                      ),
                                    ],
                                  ],
                                ),
                                
                                // Row 2: Username
                                if (_user?.username != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      // 点击 @username 复制用户名
                                      onTap: () => copyUsernameToClipboard(_user!.username),
                                      child: Text(
                                         '@${_user?.username}',
                                         style: TextStyle(color: Colors.white.withValues(alpha:0.85), fontSize: 13),
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox(height: 6), // 占位

                                // Row 3: Level Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha:0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _getTrustLevelLabel(_user?.trustLevel ?? 0),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 3. 操作按钮 (关注)
                          if (_user != null && !isOwnProfile) ...[
                            const SizedBox(width: 12),
                            _buildFollowButton(isOwnProfile),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 封禁/禁言状态 与 个人简介 互斥显示（与 Discourse 前端一致）
                      if (_user!.isSuspended || _user!.isSilenced) ...[
                        GestureDetector(
                          onTap: () => showUserInfoDialog(context, _user!),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 封禁提示
                              if (_user!.isSuspended) ...[
                                _buildRestrictionBanner(
                                  icon: Symbols.block_rounded,
                                  label: _user!.isSuspendedForever
                                      ? context.l10n.userProfile_suspendedBannerForever
                                      : context.l10n.userProfile_suspendedBannerUntil(TimeUtils.formatFullDate(_user!.suspendedTill)),
                                  reason: _user!.suspendReason,
                                  color: Colors.redAccent,
                                ),
                                if (_user!.isSilenced)
                                  const SizedBox(height: 8),
                              ],
                              // 禁言提示
                              if (_user!.isSilenced)
                                _buildRestrictionBanner(
                                  icon: Symbols.mic_off_rounded,
                                  label: _user!.isSilencedForever
                                      ? context.l10n.userProfile_silencedBannerForever
                                      : context.l10n.userProfile_silencedBannerUntil(TimeUtils.formatFullDate(_user!.silencedTill)),
                                  reason: _user!.silenceReason,
                                  color: Colors.orangeAccent,
                                ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // 个人简介（非封禁/禁言状态时显示）
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: hasInfo ? () => showUserInfoDialog(context, _user!) : null,
                          child: Container(
                            height: 54,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: hasBio
                                      ? CollapsedHtmlContent(
                                          html: _user!.bio!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textStyle: TextStyle(
                                            color: Colors.white.withValues(alpha:0.9),
                                            fontSize: 14,
                                            height: 1.3,
                                          ),
                                        )
                                      : Text(
                                          context.l10n.userProfile_noBio,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha:0.5),
                                            fontSize: 14,
                                            height: 1.3,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                ),
                                if (hasInfo) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Symbols.chevron_right_rounded,
                                    size: 16,
                                    color: Colors.white.withValues(alpha:0.6),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],

                      // Stats
                      const SizedBox(height: 16),
                      if (_summary != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 第一行：关注、粉丝
                            if (_user?.totalFollowing != null || _user?.totalFollowers != null)
                              Wrap(
                                spacing: 16,
                                children: [
                                  if (_user?.totalFollowing != null)
                                    GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FollowListPage(
                                            username: widget.username,
                                            isFollowing: true,
                                          ),
                                        ),
                                      ),
                                      child: _buildStatSlot(NumberUtils.formatCount(_user!.totalFollowing!), context.l10n.userProfile_following, _user!.totalFollowing!),
                                    ),
                                  if (_user?.totalFollowers != null)
                                    GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FollowListPage(
                                            username: widget.username,
                                            isFollowing: false,
                                          ),
                                        ),
                                      ),
                                      child: _buildStatSlot(NumberUtils.formatCount(_user!.totalFollowers!), context.l10n.userProfile_followers, _user!.totalFollowers!),
                                    ),
                                ],
                              ),
                            // 第二行：获赞、访问、话题、回复
                            if (_user?.totalFollowing != null || _user?.totalFollowers != null)
                              const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              children: [
                                _buildStatSlot(NumberUtils.formatCount(_summary!.likesReceived), context.l10n.userProfile_statsLikes, _summary!.likesReceived),
                                _buildStatSlot(NumberUtils.formatCount(_summary!.daysVisited), context.l10n.userProfile_statsVisits, _summary!.daysVisited),
                                _buildStatSlot(NumberUtils.formatCount(_summary!.topicCount), context.l10n.userProfile_statsTopics, _summary!.topicCount),
                                _buildStatSlot(NumberUtils.formatCount(_summary!.postCount), context.l10n.userProfile_statsReplies, _summary!.postCount),
                              ],
                            ),
                          ],
                        ),
                      
                      // 最近活动时间
                      if (_user?.lastPostedAt != null || _user?.lastSeenAt != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Symbols.flash_on_rounded, size: 12, color: Colors.white70),
                              const SizedBox(width: 4),
                              RelativeTimeText(
                                dateTime: _user?.lastSeenAt ?? _user!.lastPostedAt!,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ===== 层 3: 收起时的标题栏内容 - 收起时显示，点击展开 =====
              Positioned(
                left: 60 + MediaQuery.of(context).padding.left, // 横屏时需加上左侧安全区
                right: 48 + MediaQuery.of(context).padding.right, // 横屏时需加上右侧安全区
                bottom: 14 + 36, // 调整位置适应 TabBar (36是TabBar高度)
                child: GestureDetector(
                  onTap: titleOpacity > 0.5 ? () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } : null,
                  behavior: HitTestBehavior.opaque,
                  child: Opacity(
                    opacity: titleOpacity,
                    child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 头像 radius=16，flair 大小 14，偏移 right=-3, bottom=-1
                      AvatarWithFlair(
                        flairSize: 14,
                        flairRight: -3,
                        flairBottom: -1,
                        flairUrl: _user?.flairUrl,
                        flairName: _user?.flairName,
                        flairBgColor: _user?.flairBgColor,
                        flairColor: _user?.flairColor,
                        avatar: SmartAvatar(
                          imageUrl: _user?.getAvatarUrl() != null
                              ? _user!.getAvatarUrl(size: 64)
                              : null,
                          radius: 16,
                          fallbackText: _user?.username,
                          border: Border.all(color: Colors.white70, width: 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          (_user?.name?.isNotEmpty == true) ? _user!.name! : (_user?.username ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),

              // 移除之前的所有伪装层
            ],
          );
        }
      ),
    );
  }

  Widget _buildStatSlot(String value, String label, int rawValue) {
    return Tooltip(
      message: '$rawValue',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowButton(bool isOwnProfile) {
    if (_user == null || _user!.canFollow != true || isOwnProfile) {
      return const SizedBox.shrink();
    }

    return _isFollowLoading
        ? Container(
            width: 32,
            height: 32,
            padding: const EdgeInsets.all(8),
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : TextButton.icon(
            onPressed: _toggleFollow,
            icon: Icon(
              _isFollowed ? Symbols.check_rounded : Symbols.add_rounded,
              size: 16,
            ),
            label: Text(_isFollowed ? context.l10n.userProfile_followed : context.l10n.userProfile_follow),
            style: TextButton.styleFrom(
              backgroundColor: _isFollowed ? Colors.white.withValues(alpha:0.15) : Colors.white,
              foregroundColor: _isFollowed ? Colors.white : Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: _isFollowed ? const BorderSide(color: Colors.white38) : BorderSide.none,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          );
  }

  Widget _buildRestrictionBanner({
    required IconData icon,
    required String label,
    required String? reason,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusEmoji(UserStatus status) {
    final emoji = status.emoji;
    if (emoji == null || emoji.isEmpty) return const SizedBox.shrink();

    final isEmojiName = emoji.contains(RegExp(r'[a-zA-Z0-9_]')) && !emoji.contains(RegExp(r'[^\x00-\x7F]'));

    if (isEmojiName) {
      final cleanName = emoji.replaceAll(':', '');
      final emojiUrl = UserProfileItems.getEmojiUrl(cleanName);

      return Image(
        image: emojiImageProvider(emojiUrl),
        width: 18,
        height: 18,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }

    return Text(
      emoji,
      style: const TextStyle(fontSize: 16),
    );
  }

  /// 按 filter 分发到对应的 tab widget。
  /// 各 tab 自带数据加载/分页/loading,首挂载(initState)即触发首次加载。
  Widget _buildTab(String filter) {
    switch (filter) {
      case 'summary':
        return SummaryTab(summary: _summary);
      case 'reactions':
        return ReactionsTab(username: widget.username);
      case 'boosts':
        return BoostsTab(username: widget.username);
      case 'votes':
        return VotesTab(username: widget.username);
      case 'solved':
        return SolvedTab(username: widget.username);
      default:
        // '4,5' / '4' / '5' / '1' 等通用 Activity filter
        return UserActivityList(username: widget.username, filter: filter);
    }
  }

  String _getTrustLevelLabel(int level) {
    switch (level) {
      case 0:
        return S.current.user_trustLevel0;
      case 1:
        return S.current.user_trustLevel1;
      case 2:
        return S.current.user_trustLevel2;
      case 3:
        return S.current.user_trustLevel3;
      case 4:
        return S.current.user_trustLevel4;
      default:
        return S.current.user_trustLevelUnknown(level);
    }
  }
}
