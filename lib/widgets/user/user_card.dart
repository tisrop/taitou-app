import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../l10n/s.dart';
import '../../models/user.dart';
import '../../models/badge.dart' as badge_model;
import '../../providers/discourse_providers.dart';
import '../../pages/user_profile_page/user_profile_page.dart';
import '../../services/app_error_handler.dart';
import '../../services/discourse_cache_manager.dart';
import '../../services/preloaded_data_service.dart';
import '../../services/toast_service.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/font_awesome_helper.dart';
import '../../utils/number_utils.dart';
import '../../utils/platform_utils.dart';
import '../../utils/time_utils.dart';
import '../common/visual/flair_badge.dart';
import '../badge/badge_ui_utils.dart';
import 'package:common_ui/common_ui.dart';
import '../common/overlay/skeleton.dart';
import '../common/visual/smart_avatar.dart';
import '../../utils/fluxdo_render_callbacks.dart';
import 'avatar_action_menu.dart';
import 'ignore_duration_picker.dart';

/// 卡片与锚点之间的间隙
const double _kGap = 10.0;

/// 距屏幕边缘的最小留白
const double _kScreenMargin = 12.0;

/// 桌面端浮层宽度（比移动端更宽，对齐网页版桌面卡片）
const double _kFloatingWidth = 420.0;

const double _kDesktopAvatarOverflow = 24.0;

/// 移动端停靠卡最大宽度。
const double _kDockedMaxWidth = 480.0;

class _UserCardMetrics {
  final double avatarRadius;
  final double avatarOverflow;
  final double horizontalPadding;
  final double identityInset;
  final double contentTopPadding;
  final double cardRadius;
  final double outerMargin;

  const _UserCardMetrics({
    required this.avatarRadius,
    required this.avatarOverflow,
    required this.horizontalPadding,
    required this.identityInset,
    required this.contentTopPadding,
    required this.cardRadius,
    required this.outerMargin,
  });

  static _UserCardMetrics forWidth(double width, {required bool docked}) {
    if (!docked) {
      return const _UserCardMetrics(
        avatarRadius: 38,
        avatarOverflow: 24,
        horizontalPadding: 16,
        identityInset: 84,
        contentTopPadding: 12,
        cardRadius: 20,
        outerMargin: 12,
      );
    }

    // 移动端使用明显越过卡片顶边的头像；高分辨率截图仍按逻辑像素布局。
    if (width >= 600) {
      return const _UserCardMetrics(
        avatarRadius: 72,
        avatarOverflow: 50,
        horizontalPadding: 24,
        identityInset: 168,
        contentTopPadding: 20,
        cardRadius: 24,
        outerMargin: 24,
      );
    }
    return const _UserCardMetrics(
      avatarRadius: 64,
      avatarOverflow: 44,
      horizontalPadding: 16,
      identityInset: 144,
      contentTopPadding: 16,
      cardRadius: 20,
      outerMargin: 12,
    );
  }
}

/// 是否允许展示用户卡片（站点隐藏公开资料时要求已登录）。
bool canShowUserCardPreview(BuildContext context) {
  final preloaded = PreloadedDataService();
  final hideProfilesFromPublic =
      preloaded.siteSettingsSync?['hide_user_profiles_from_public'] == true;
  if (!hideProfilesFromPublic) return true;

  final currentUser = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(currentUserProvider).value;
  return currentUser != null || preloaded.currentUserSync != null;
}

/// 显示用户卡片。两种形态对齐 Discourse 网页版：
/// - 桌面端：锚定在头像旁的浮层（优先右侧，其次左/下/上）。
/// - 移动端：顶部全宽停靠卡（docked），背景模糊作遮罩。
///
/// [anchorRect] 头像在屏幕坐标系中的矩形（桌面端浮层定位用）。
/// [topicId]/[postNumber] 话题上下文，用于「基于话题的私信」（正文携带帖子链接）。
/// [avatarFallbackUrl]/[nameFallback]/flair* 来自 Post，用于在网络返回前秒显头部。
void showUserCard({
  required BuildContext context,
  required Rect anchorRect,
  required String username,
  LayerLink? layerLink,
  int? topicId,
  String? topicTitle,
  int? postNumber,
  String? avatarFallbackUrl,
  String? nameFallback,
  String? flairUrl,
  String? flairName,
  String? flairBgColor,
  String? flairColor,
  Future<void> Function()? onStartChat,
}) {
  if (!canShowUserCardPreview(context)) return;

  final anchorContext = context;
  final menuNavigatorKey = PlatformUtils.isDesktop
      ? GlobalKey<NavigatorState>()
      : null;
  final metrics = _UserCardMetrics.forWidth(
    MediaQuery.sizeOf(context).width,
    docked: !PlatformUtils.isDesktop,
  );

  Widget buildCard(VoidCallback onClose) => _UserCardContent(
    username: username,
    topicId: topicId,
    topicTitle: topicTitle,
    postNumber: postNumber,
    avatarFallbackUrl: avatarFallbackUrl,
    nameFallback: nameFallback,
    flairUrl: flairUrl,
    flairName: flairName,
    flairBgColor: flairBgColor,
    flairColor: flairColor,
    onStartChat: onStartChat,
    anchorContext: anchorContext,
    menuNavigatorKey: menuNavigatorKey,
    onClose: onClose,
    metrics: metrics,
  );

  if (PlatformUtils.isDesktop) {
    // 桌面端：非模态浮层，不挡背景滚动（对齐网页版 PC）。
    // 用 OverlayEntry（无 barrier）+ 半透明 Listener：卡外按下即关闭，
    // 滚轮/拖动等事件穿透到下层页面，背景照常滚动。
    final overlay = Overlay.of(context, rootOverlay: true);
    OverlayEntry? entry;
    var removed = false;
    void close() {
      if (removed) return;
      removed = true;
      entry?.remove();
    }

    entry = OverlayEntry(
      builder: (ctx) {
        final animatedCard = _CardEntryAnimation(child: buildCard(close));
        // 有 LayerLink：卡片跟随头像滚动（对齐网页版）；否则按锚点矩形静态定位
        final Widget positioned = layerLink != null
            ? CompositedTransformFollower(
                link: layerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(_kGap, -8),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _kFloatingWidth,
                      maxHeight: MediaQuery.of(ctx).size.height * 0.8,
                    ),
                    child: animatedCard,
                  ),
                ),
              )
            : _FloatingLayer(anchorRect: anchorRect, child: animatedCard);

        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => close(),
                child: const SizedBox.expand(),
              ),
            ),
            positioned,
            Positioned.fill(
              child: _UserCardMenuNavigator(navigatorKey: menuNavigatorKey!),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  } else {
    // 移动端：顶部全宽停靠卡；聊天卡只压暗背景以保留频道上下文。
    showAppGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      blur: false,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, _, _) => _DockedLayer(
        chatCard: onStartChat != null,
        child: buildCard(() => Navigator.of(dialogContext).pop()),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
  }
}

class _UserCardMenuNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const _UserCardMenuNavigator({required this.navigatorKey});

  static const _hostRouteName = '_userCardMenuHost';

  @override
  Widget build(BuildContext context) {
    return _UserCardMenuNavigatorHost(navigatorKey: navigatorKey);
  }
}

class _UserCardMenuNavigatorHost extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const _UserCardMenuNavigatorHost({required this.navigatorKey});

  @override
  State<_UserCardMenuNavigatorHost> createState() =>
      _UserCardMenuNavigatorHostState();
}

class _UserCardMenuNavigatorHostState
    extends State<_UserCardMenuNavigatorHost> {
  late final _UserCardMenuNavigatorObserver _observer =
      _UserCardMenuNavigatorObserver(_setMenuActive);
  bool _menuActive = false;

  void _setMenuActive(bool active) {
    if (_menuActive == active || !mounted) return;
    setState(() => _menuActive = active);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_menuActive,
      child: Navigator(
        key: widget.navigatorKey,
        clipBehavior: Clip.none,
        observers: [_observer],
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          settings: const RouteSettings(
            name: _UserCardMenuNavigator._hostRouteName,
          ),
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _UserCardMenuNavigatorObserver extends NavigatorObserver {
  final ValueChanged<bool> onActiveChanged;
  int _menuRouteCount = 0;

  _UserCardMenuNavigatorObserver(this.onActiveChanged);

  bool _isMenuRoute(Route<dynamic>? route) =>
      route?.settings.name != _UserCardMenuNavigator._hostRouteName;

  void _notify() => onActiveChanged(_menuRouteCount > 0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isMenuRoute(route)) {
      _menuRouteCount += 1;
      _notify();
    }
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isMenuRoute(route) && _menuRouteCount > 0) {
      _menuRouteCount -= 1;
      _notify();
    }
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isMenuRoute(route) && _menuRouteCount > 0) {
      _menuRouteCount -= 1;
      _notify();
    }
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_isMenuRoute(oldRoute) && _menuRouteCount > 0) {
      _menuRouteCount -= 1;
    }
    if (_isMenuRoute(newRoute)) {
      _menuRouteCount += 1;
    }
    _notify();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

/// 桌面端浮层入场动画（淡入 + 轻微缩放），OverlayEntry 无路由动画，手动补一个
class _CardEntryAnimation extends StatefulWidget {
  final Widget child;
  const _CardEntryAnimation({required this.child});

  @override
  State<_CardEntryAnimation> createState() => _CardEntryAnimationState();
}

class _CardEntryAnimationState extends State<_CardEntryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 180),
    vsync: this,
  )..forward();
  late final Animation<double> _anim = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(_anim),
        alignment: Alignment.topLeft,
        child: widget.child,
      ),
    );
  }
}

/// 移动端：顶部全宽停靠卡
class _DockedLayer extends StatelessWidget {
  final Widget child;
  final bool chatCard;

  const _DockedLayer({required this.child, required this.chatCard});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final metrics = _UserCardMetrics.forWidth(media.size.width, docked: true);
    final maxHeight = media.size.height * 0.82;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // 顶部多留出头像戳出的高度，避免被状态栏/安全区裁剪。
          padding: EdgeInsets.fromLTRB(
            metrics.outerMargin,
            metrics.avatarOverflow + (chatCard ? 50 : 6),
            metrics.outerMargin,
            metrics.outerMargin,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _kDockedMaxWidth,
              maxHeight: maxHeight,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 桌面端：锚定头像旁的浮层
class _FloatingLayer extends StatelessWidget {
  final Rect anchorRect;
  final Widget child;

  const _FloatingLayer({required this.anchorRect, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _FloatingLayoutDelegate(
        anchorRect: anchorRect,
        safeInsets: MediaQuery.of(context).padding,
      ),
      child: child,
    );
  }
}

/// 桌面端浮层定位：优先放在锚点右侧，其次左侧，再次下方/上方，并 clamp 在屏幕内。
class _FloatingLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect anchorRect;
  final EdgeInsets safeInsets;

  _FloatingLayoutDelegate({required this.anchorRect, required this.safeInsets});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = math.min(
      _kFloatingWidth,
      constraints.maxWidth - _kScreenMargin * 2,
    );
    final maxHeight =
        constraints.maxHeight - safeInsets.vertical - _kScreenMargin * 2;
    return BoxConstraints(
      minWidth: 0,
      maxWidth: maxWidth,
      minHeight: 0,
      maxHeight: math.max(160.0, maxHeight),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 顶部额外留出头像戳出的高度，避免被裁
    final topLimit = safeInsets.top + _kScreenMargin + _kDesktopAvatarOverflow;
    final bottomLimit = size.height - safeInsets.bottom - _kScreenMargin;

    double clampY(double y) =>
        y.clamp(topLimit, math.max(topLimit, bottomLimit - childSize.height));

    // 优先右侧
    final rightX = anchorRect.right + _kGap;
    if (rightX + childSize.width <= size.width - _kScreenMargin) {
      return Offset(rightX, clampY(anchorRect.top));
    }
    // 其次左侧
    final leftX = anchorRect.left - _kGap - childSize.width;
    if (leftX >= _kScreenMargin) {
      return Offset(leftX, clampY(anchorRect.top));
    }
    // 再次下方/上方，水平以锚点居中并 clamp
    final dx = (anchorRect.center.dx - childSize.width / 2).clamp(
      _kScreenMargin,
      size.width - childSize.width - _kScreenMargin,
    );
    final belowTop = anchorRect.bottom + _kGap;
    if (belowTop + childSize.height <= bottomLimit) {
      return Offset(dx, belowTop);
    }
    final aboveTop = anchorRect.top - _kGap - childSize.height;
    return Offset(dx, math.max(topLimit, aboveTop));
  }

  @override
  bool shouldRelayout(_FloatingLayoutDelegate oldDelegate) =>
      anchorRect != oldDelegate.anchorRect ||
      safeInsets != oldDelegate.safeInsets;
}

/// 用户卡片内容
class _UserCardContent extends ConsumerStatefulWidget {
  final String username;
  final int? topicId;
  final String? topicTitle;
  final int? postNumber;
  final String? avatarFallbackUrl;
  final String? nameFallback;
  final String? flairUrl;
  final String? flairName;
  final String? flairBgColor;
  final String? flairColor;
  final Future<void> Function()? onStartChat;
  final BuildContext anchorContext;
  final GlobalKey<NavigatorState>? menuNavigatorKey;
  final VoidCallback onClose;
  final _UserCardMetrics metrics;

  const _UserCardContent({
    required this.username,
    required this.topicId,
    required this.topicTitle,
    required this.postNumber,
    required this.avatarFallbackUrl,
    required this.nameFallback,
    required this.flairUrl,
    required this.flairName,
    required this.flairBgColor,
    required this.flairColor,
    required this.onStartChat,
    required this.anchorContext,
    required this.menuNavigatorKey,
    required this.onClose,
    required this.metrics,
  });

  @override
  ConsumerState<_UserCardContent> createState() => _UserCardContentState();
}

class _UserCardContentState extends ConsumerState<_UserCardContent> {
  User? _user;
  List<badge_model.Badge> _badges = const [];
  bool _loading = true;

  bool _isFollowed = false;
  bool _followLoading = false;

  // normal / mute / ignore
  String _notificationLevel = 'normal';

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.onStartChat != null) _loadBadges();
  }

  Future<void> _load() async {
    try {
      final user = await ref
          .read(discourseServiceProvider)
          .getUserCard(widget.username);
      if (!mounted) return;
      setState(() {
        _user = user;
        _isFollowed = user.isFollowed ?? false;
        _notificationLevel = user.ignored == true
            ? 'ignore'
            : user.muted == true
            ? 'mute'
            : 'normal';
        _loading = false;
      });
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  Future<void> _loadBadges() async {
    final service = ref.read(discourseServiceProvider);
    try {
      final response = await service.getUserBadges(username: widget.username);
      final unique = <int, badge_model.Badge>{};
      for (final userBadge in response.userBadges) {
        final badge = userBadge.badge;
        if (badge != null) unique[badge.id] = badge;
      }
      if (mounted) setState(() => _badges = unique.values.toList());
    } catch (_) {
      // 部分站点关闭了用户徽章接口，回退到 summary 中的热门徽章。
      try {
        final summary = await service.getUserSummary(widget.username);
        if (mounted) setState(() => _badges = summary.badges);
      } catch (_) {
        // 徽章属于次要信息，加载失败不影响用户卡主体展示。
      }
    }
  }

  void _openProfile() {
    widget.onClose();
    Navigator.of(widget.anchorContext).push(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(username: widget.username),
      ),
    );
  }

  void _composeMessage() {
    widget.onClose();
    composeMessageToUser(
      context: widget.anchorContext,
      username: widget.username,
      topicId: widget.topicId,
      postNumber: widget.postNumber,
      topicTitle: widget.topicTitle,
    );
  }

  Future<void> _startChat() async {
    widget.onClose();
    await widget.onStartChat?.call();
  }

  Future<void> _toggleFollow() async {
    if (_followLoading) return;
    setState(() => _followLoading = true);
    final service = ref.read(discourseServiceProvider);
    final wasFollowed = _isFollowed;
    try {
      if (wasFollowed) {
        await service.unfollowUser(widget.username);
      } else {
        await service.followUser(widget.username);
      }
      if (mounted) setState(() => _isFollowed = !wasFollowed);
    } on DioException catch (_) {
      // 网络错误已由 ErrorInterceptor 处理
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  Future<void> _setNotificationLevel(String level) async {
    final service = ref.read(discourseServiceProvider);

    String? expiringAt;
    if (level == 'ignore') {
      expiringAt = await showIgnoreDurationPicker(widget.anchorContext);
      if (expiringAt == null) return; // 取消
    }

    final old = _notificationLevel;
    setState(() => _notificationLevel = level);
    try {
      await service.updateUserNotificationLevel(
        widget.username,
        level: level,
        expiringAt: expiringAt,
      );
      if (!mounted) return;
      final label = switch (level) {
        'mute' => S.current.userProfile_setToMute,
        'ignore' => S.current.userProfile_setToIgnore,
        _ => S.current.userProfile_restored,
      };
      ToastService.showSuccess(label);
    } catch (e, s) {
      if (mounted) setState(() => _notificationLevel = old);
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    final bg = user?.backgroundUrl;
    final hasBg = bg != null && bg.isNotEmpty;
    final isChatCard = widget.onStartChat != null;
    final surface = isChatCard && theme.brightness == Brightness.light
        ? Colors.white
        : theme.colorScheme.surface;
    final horizontalPadding = isChatCard
        ? 10.0
        : widget.metrics.horizontalPadding;
    final contentTopPadding = isChatCard
        ? 8.0
        : widget.metrics.contentTopPadding;

    final body = SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          contentTopPadding,
          horizontalPadding,
          widget.onStartChat != null ? 12 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 第一行：名称排在戳出头像的右侧（对齐网页版 first-row）
            Padding(
              padding: EdgeInsets.only(left: widget.metrics.identityInset),
              child: _buildIdentity(theme, user, hasBg),
            ),
            if (widget.onStartChat != null) ...[
              const SizedBox(height: 52),
              _buildActions(theme, user, primaryOnly: true),
            ],
            if (user != null) ...[
              if (user.isSuspended || user.isSilenced)
                _buildRestrictionBanner(theme, user),
              if (widget.onStartChat == null && _hasBio(user))
                _buildBio(theme, user),
              if (widget.onStartChat == null)
                _buildLocationWebsite(theme, user),
              if (widget.onStartChat != null)
                _buildChatFacts(theme, user)
              else ...[
                _buildFacts(theme, user),
                _buildStatsRow(theme, user),
              ],
              if (widget.onStartChat != null &&
                  widget.metrics.avatarRadius >= 64)
                _buildChatHighlights(theme),
            ] else if (_loading)
              _buildBodySkeleton(theme),
            if (widget.onStartChat == null) ...[
              const SizedBox(height: 16),
              _buildActions(theme, user),
            ],
          ],
        ),
      ),
    );

    final card = Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(widget.metrics.cardRadius),
        boxShadow: [
          // 桌面端无遮罩，靠更重的投影把卡片从背景中托起来
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 32,
            spreadRadius: 1,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // 背景图与内容蒙版放在同一层（child 内嵌套），保证两者矩形完全重合：
      // border 会让 Container 给 child 加内边距，若图放在外层 decoration 会比蒙版多出一圈露边。
      // 背景图走项目图片层以支持 CF/缓存；蒙版顶部较透出背景，向下过渡到接近不透明保证可读（对齐 .card-content 半透明）。
      child: hasBg
          ? DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: discourseImageProvider(bg),
                  fit: BoxFit.cover,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      surface.withValues(alpha: 0.45),
                      surface.withValues(alpha: 0.92),
                    ],
                  ),
                ),
                child: body,
              ),
            )
          : body,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          // 大头像：戳出卡片顶边（对齐网页版），上半在卡外、下半压在卡内
          Positioned(
            left: isChatCard ? 10 : widget.metrics.horizontalPadding,
            top: -widget.metrics.avatarOverflow,
            child: _buildAvatar(theme, user),
          ),
        ],
      ),
    );
  }

  bool _hasBio(User user) => user.bio != null && user.bio!.trim().isNotEmpty;

  /// 大头像（带白色描边 + flair），点击进个人页
  Widget _buildAvatar(ThemeData theme, User? user) {
    // 与各调用方传入的 fallback 尺寸保持一致（144），保证 loading 前后 URL 相同、命中缓存不重载
    final avatarUrl = user?.getAvatarUrl(size: 144) ?? widget.avatarFallbackUrl;
    return GestureDetector(
      onTap: _openProfile,
      child: AvatarWithFlair(
        flairSize: widget.metrics.avatarRadius >= 80 ? 28 : 18,
        flairRight: -2,
        flairBottom: -2,
        flairUrl: user?.flairUrl ?? widget.flairUrl,
        flairName: user?.flairName ?? widget.flairName,
        flairBgColor: user?.flairBgColor ?? widget.flairBgColor,
        flairColor: user?.flairColor ?? widget.flairColor,
        avatar: SmartAvatar(
          imageUrl: (avatarUrl?.isNotEmpty ?? false) ? avatarUrl : null,
          radius: widget.metrics.avatarRadius,
          fallbackText: widget.username,
          border: Border.all(color: theme.colorScheme.surface, width: 3),
        ),
      ),
    );
  }

  /// 名称 / @username / 信任等级
  Widget _buildIdentity(ThemeData theme, User? user, bool hasBg) {
    final displayName = (user?.name?.isNotEmpty ?? false)
        ? user!.name!
        : (widget.nameFallback?.isNotEmpty ?? false)
        ? widget.nameFallback!
        : widget.username;

    // 背景图上给文字加阴影，保证可读
    final shadows = hasBg
        ? <Shadow>[
            Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 6),
          ]
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _openProfile,
            child: Text(
              displayName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                shadows: shadows,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.onStartChat == null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 点击 @username 复制用户名
                    onTap: () => copyUsernameToClipboard(widget.username),
                    child: Text(
                      '@${widget.username}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: hasBg
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.9)
                            : theme.colorScheme.onSurfaceVariant,
                        shadows: shadows,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (user != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      user.trustLevelString,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 简介：高度随内容自适应，超过约 3 行才裁剪。
  /// 用 ConstrainedBox(maxHeight) + 内层不可滚动 ScrollView 让子节点按自然高度布局，
  /// 短简介收缩、长简介封顶裁剪，且不触发 RenderFlex 溢出报错。
  Widget _buildBio(ThemeData theme, User user) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 66),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          // 用户卡 bio 属只读预览：走新引擎 FluxdoRender，关闭划词选区。
          child:
              FluxdoRenderCallbacks.generic(
                heroTagNamespace: 'user_card_bio_${user.username}',
              ).render(
                cookedHtml: user.bio!,
                baseTextStyle: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                ),
                compact: true,
                selectionEnabled: false,
              ),
        ),
      ),
    );
  }

  Widget _buildRestrictionBanner(ThemeData theme, User user) {
    final isSuspended = user.isSuspended;
    final color = isSuspended ? theme.colorScheme.error : Colors.orange;
    final label = isSuspended
        ? (user.isSuspendedForever
              ? S.current.userProfile_permanentlySuspended
              : S.current.userProfile_suspendedUntil(
                  TimeUtils.formatFullDate(user.suspendedTill),
                ))
        : (user.isSilencedForever
              ? S.current.userProfile_permanentlySilenced
              : S.current.userProfile_silencedUntil(
                  TimeUtils.formatFullDate(user.silencedTill),
                ));
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            isSuspended ? Symbols.block_rounded : Symbols.mic_off_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 位置 / 网站（带图标，对齐网页 location-and-website 行）
  Widget _buildLocationWebsite(ThemeData theme, User user) {
    final items = <Widget>[];
    void add(IconData icon, String text) {
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (user.location?.isNotEmpty ?? false) {
      add(Symbols.location_on_rounded, user.location!);
    }
    final site = (user.websiteName?.isNotEmpty ?? false)
        ? user.websiteName!
        : (user.website?.isNotEmpty ?? false)
        ? user.website!
        : null;
    if (site != null) add(Symbols.link_rounded, site);

    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 16, runSpacing: 6, children: items),
    );
  }

  /// 最后发布 / 加入时间 / 阅读时间，标签+值 行内流式（对齐网页 metadata 行）
  Widget _buildFacts(ThemeData theme, User user) {
    final items = <Widget>[];
    if (user.lastPostedAt != null) {
      items.add(
        _metaItem(
          theme,
          S.current.userCard_postedAt,
          TimeUtils.formatRelativeTime(user.lastPostedAt!),
        ),
      );
    }
    if (user.createdAt != null) {
      items.add(
        _metaItem(
          theme,
          S.current.userCard_joinedAt,
          TimeUtils.formatShortDate(user.createdAt),
        ),
      );
    }
    if ((user.timeRead ?? 0) > 0) {
      items.add(
        _metaItem(
          theme,
          S.current.profileStats_timeRead,
          NumberUtils.formatDurationLong(user.timeRead!),
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 14, runSpacing: 4, children: items),
    );
  }

  /// 正在关注 / 粉丝 / 积分，标签+加粗值 行内流式
  Widget _buildStatsRow(ThemeData theme, User user) {
    final items = <Widget>[];
    if (user.totalFollowing != null) {
      items.add(
        _metaItem(
          theme,
          S.current.userProfile_following,
          NumberUtils.formatCount(user.totalFollowing!),
          bold: true,
        ),
      );
    }
    if (user.totalFollowers != null) {
      items.add(
        _metaItem(
          theme,
          S.current.userProfile_followers,
          NumberUtils.formatCount(user.totalFollowers!),
          bold: true,
        ),
      );
    }
    if (user.gamificationScore != null) {
      items.add(
        _metaItem(
          theme,
          S.current.userCard_score,
          NumberUtils.formatCount(user.gamificationScore!),
          bold: true,
          valueColor: theme.colorScheme.primary,
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 14, runSpacing: 4, children: items),
    );
  }

  Widget _buildChatFacts(ThemeData theme, User user) {
    final now = TimeOfDay.now();
    final clock = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(now, alwaysUse24HourFormat: true);
    final rows = <Widget>[
      Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 21,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 6),
          Text(
            clock,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ];

    if (user.lastPostedAt != null) {
      rows.add(
        _chatFactLine(
          theme,
          S.current.userCard_lastPosted,
          TimeUtils.formatRelativeTime(user.lastPostedAt!),
        ),
      );
    }
    if (user.createdAt != null) {
      rows.add(
        _chatFactLine(
          theme,
          S.current.userProfile_joinDate,
          TimeUtils.formatFullDate(user.createdAt),
        ),
      );
    }

    final totalRead = user.timeRead ?? 0;
    final recentRead = user.recentTimeRead ?? 0;
    if (totalRead > 0 || user.gamificationScore != null) {
      rows.add(
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            if (totalRead > 0)
              Text(
                recentRead > 0
                    ? S.current.userCard_reading(
                        NumberUtils.formatDurationLong(totalRead),
                        NumberUtils.formatDurationLong(recentRead),
                      )
                    : '${S.current.profileStats_timeRead} '
                          '${NumberUtils.formatDurationLong(totalRead)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (user.gamificationScore != null)
              _chatFactLine(
                theme,
                S.current.userCard_score,
                NumberUtils.formatCount(user.gamificationScore!),
                valueColor: theme.colorScheme.primary,
                bold: true,
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            rows[index],
          ],
        ],
      ),
    );
  }

  Widget _chatFactLine(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor ?? theme.colorScheme.onSurface,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
      style: theme.textTheme.bodyMedium,
    );
  }

  Widget _buildChatHighlights(ThemeData theme) {
    final earnedBadges = _badges.where((badge) {
      final value = '${badge.slug} ${badge.name}'.toLowerCase();
      return !value.contains('basic') &&
          !value.contains('基本用户') &&
          !value.contains('基本使用者');
    }).toList();
    int priority(badge_model.Badge badge) {
      final value = '${badge.slug} ${badge.name}'.toLowerCase();
      if (value.contains('anniversary') || value.contains('周年')) return 0;
      if (value.contains('first-quote') || value.contains('首次引用')) return 1;
      return 2;
    }

    earnedBadges.sort((a, b) => priority(a).compareTo(priority(b)));
    final visibleBadges = earnedBadges.take(2).toList();
    final otherCount = earnedBadges.length - visibleBadges.length;

    final tiles = <Widget>[
      _buildHighlightTile(
        theme,
        icon: Icons.person_rounded,
        label: _trustLevelLabel(_user?.trustLevel ?? 0),
        color: const Color(0xFFC58A43),
      ),
      ...visibleBadges.map((badge) => _buildBadgeHighlightTile(theme, badge)),
      if (otherCount > 0)
        _buildHighlightTile(
          theme,
          icon: Icons.more_horiz_rounded,
          label: S.current.userCard_otherBadges(otherCount),
          color: theme.colorScheme.onSurface,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 4) / 2;
          return Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final tile in tiles) SizedBox(width: width, child: tile),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBadgeHighlightTile(ThemeData theme, badge_model.Badge badge) {
    final color = BadgeUIUtils.getBadgeColor(context, badge.badgeType);
    Widget icon = Icon(Icons.workspace_premium_rounded, color: color, size: 18);
    if (badge.icon != null && badge.icon!.isNotEmpty) {
      final iconData = FontAwesomeHelper.getIcon(badge.icon!);
      if (iconData != null) {
        icon = FaIcon(iconData, color: color, size: 17);
      }
    }
    return _buildHighlightTile(
      theme,
      iconWidget: icon,
      label: badge.name,
      color: color,
    );
  }

  Widget _buildHighlightTile(
    ThemeData theme, {
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.38,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          iconWidget ?? Icon(icon, color: color, size: 18),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _trustLevelLabel(int level) {
    final label = switch (level) {
      0 => S.current.user_trustLevel0,
      1 => S.current.user_trustLevel1,
      2 => S.current.user_trustLevel2,
      3 => S.current.user_trustLevel3,
      4 => S.current.user_trustLevel4,
      _ => S.current.user_trustLevelUnknown(level),
    };
    return label.replaceFirst(RegExp(r'^L\d+\s*'), '');
  }

  /// 标签（灰）+ 值 的行内项
  Widget _metaItem(
    ThemeData theme,
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          TextSpan(
            text: value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: valueColor ?? theme.colorScheme.onSurface,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 加载中：正文骨架屏（头像/名称已用 Post 兜底秒显，仅正文待加载）
  Widget _buildBodySkeleton(ThemeData theme) {
    return Skeleton(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: double.infinity, height: 13),
            SizedBox(height: 8),
            SkeletonBox(width: 230, height: 13),
            SizedBox(height: 16),
            SkeletonBox(width: 150, height: 12),
            SizedBox(height: 10),
            SkeletonBox(width: 190, height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(
    ThemeData theme,
    User? user, {
    bool primaryOnly = false,
  }) {
    final isLoggedIn = ref.watch(
      currentUserProvider.select((value) => value.value != null),
    );
    final canMessage = isLoggedIn && user?.canSendPrivateMessageToUser == true;
    final canFollow = isLoggedIn && user?.canFollow == true;
    final canMute = isLoggedIn && user?.canMuteUser == true;
    final canIgnore = isLoggedIn && user?.canIgnoreUser == true;
    final chatButtonStyle = widget.onStartChat == null
        ? null
        : FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5B5AC7),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 42),
            shape: const StadiumBorder(),
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          );

    final primary = <Widget>[];
    if (canMessage) {
      primary.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: _composeMessage,
            style: chatButtonStyle,
            icon: const Icon(Symbols.mail_rounded, size: 18, fill: 1),
            label: Text(S.current.userProfile_message),
          ),
        ),
      );
    }
    if (widget.onStartChat != null) {
      primary.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: _startChat,
            style: chatButtonStyle,
            icon: const Icon(Symbols.chat_bubble_rounded, size: 18, fill: 1),
            label: Text(S.current.chat_title),
          ),
        ),
      );
    }
    if (canFollow && !primaryOnly) {
      primary.add(
        Expanded(
          child: _isFollowed
              ? OutlinedButton.icon(
                  onPressed: _followLoading ? null : _toggleFollow,
                  icon: const Icon(Symbols.how_to_reg_rounded, size: 18),
                  label: Text(S.current.userProfile_followed),
                )
              : FilledButton.tonalIcon(
                  onPressed: _followLoading ? null : _toggleFollow,
                  icon: const Icon(Symbols.person_add_alt_rounded, size: 18),
                  label: Text(S.current.userProfile_follow),
                ),
        ),
      );
    }

    final primaryRow = primary.isEmpty
        ? const SizedBox.shrink()
        : Row(
            children: [
              for (var i = 0; i < primary.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                primary[i],
              ],
            ],
          );
    if (primaryOnly) return primaryRow;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary.isNotEmpty) ...[primaryRow, const SizedBox(height: 8)],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openProfile,
                icon: const Icon(Symbols.account_circle_rounded, size: 18),
                label: Text(S.current.userCard_viewProfile),
              ),
            ),
            if (canMute || canIgnore) ...[
              const SizedBox(width: 8),
              _buildMoreMenu(theme, canMute, canIgnore),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildMoreMenu(ThemeData theme, bool canMute, bool canIgnore) {
    return SwipeDismissiblePopupMenuButton<String>(
      tooltip: '',
      icon: const Icon(Symbols.more_horiz_rounded),
      style: IconButton.styleFrom(
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(48, 40),
      ),
      onSelected: _setNotificationLevel,
      menuNavigatorKey: widget.menuNavigatorKey,
      itemBuilder: (context) => [
        if (canMute)
          _notificationLevel == 'mute'
              ? _menuItem(
                  'normal',
                  Symbols.volume_up_rounded,
                  S.current.userProfile_restored,
                )
              : _menuItem(
                  'mute',
                  Symbols.volume_off_rounded,
                  S.current.userCard_mute,
                ),
        if (canIgnore)
          _notificationLevel == 'ignore'
              ? _menuItem(
                  'normal',
                  Symbols.visibility_rounded,
                  S.current.userProfile_restored,
                )
              : _menuItem(
                  'ignore',
                  Symbols.visibility_off_rounded,
                  S.current.userCard_ignore,
                ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}
