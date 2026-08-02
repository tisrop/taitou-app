import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../constants.dart';
import '../network/cookie/cookie_jar_service.dart';
import '../local_notification_service.dart'; // 用于获取全局 navigatorKey
import 'cf_challenge_logger.dart';
import 'cf_clearance_refresh_service.dart';
import '../toast_service.dart';
import '../../l10n/s.dart';
import '../../pages/cf_challenge_page.dart';

/// CF 验证服务
/// 处理 Cloudflare Turnstile 验证（仅手动模式）
class CfChallengeService {
  static final CfChallengeService _instance = CfChallengeService._internal();
  factory CfChallengeService() => _instance;
  CfChallengeService._internal();

  bool _isVerifying = false;

  /// CF 验证是否正在进行中（用于外部判断是否应忽略路由变化）
  bool get isVerifying => _isVerifying;

  /// CF 验证状态变化通知（true=进行中, false=空闲）。
  /// 拦截器 / ScreenTrack 等订阅它来在 CF 期间冻结业务流量与数据采集。
  final ValueNotifier<bool> inProgressNotifier = ValueNotifier<bool>(false);

  /// CF 挑战被成功解决、新 cf_clearance 已落 CookieJar 的时刻广播。
  /// [BrowserTrustCoordinator] 订阅它:WebView session bootstrap 因 CF 失败后,
  /// 等待 Dio 侧(或主动发起的)验证完成,再 force 重跑 bootstrap,避免两条线各自为政。
  final ValueNotifier<DateTime?> clearanceResolvedAt = ValueNotifier<DateTime?>(
    null,
  );

  void _setVerifying(bool value) {
    if (_isVerifying == value) return;
    _isVerifying = value;
    inProgressNotifier.value = value;
  }

  /// 是否在拦截到 CF 盾时自动弹出验证 UI（默认 true）
  /// 关闭后 [CfChallengeInterceptor] 命中 CF 盾时会静默 reject，
  /// 交给 ErrorView 提供"手动验证"入口。由 PreferencesNotifier 同步维护。
  bool autoVerifyEnabled = true;

  final _verifyCompleter = <Completer<bool>>[];
  BuildContext? _context;
  static DateTime? _lastToastAt;
  Future<bool>? _activeSessionCompatPrompt;
  bool _sessionCompatPromptDeclined = false;
  Completer<BuildContext>? _contextReadyCompleter;
  VoidCallback? _activePromoteToForeground;
  bool _pendingPromoteToForeground = false;

  /// 冷却机制：连续失败 N 次后进入冷却期
  DateTime? _cooldownUntil;
  int _consecutiveFailures = 0;
  static const _cooldownDuration = Duration(seconds: 30);
  static const _maxFailuresBeforeCooldown = 3;
  static const _toastCooldown = Duration(seconds: 2);

  /// 检查是否在冷却期
  bool get isInCooldown {
    if (_cooldownUntil == null) return false;
    if (DateTime.now().isAfter(_cooldownUntil!)) {
      _cooldownUntil = null;
      return false;
    }
    return true;
  }

  /// 重置冷却期和失败计数（验证成功后调用）
  void resetCooldown() {
    _cooldownUntil = null;
    _consecutiveFailures = 0;
    CfChallengeLogger.logCooldown(entering: false);
  }

  /// 记录一次验证失败，连续达到上限后进入冷却期
  void startCooldown() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxFailuresBeforeCooldown) {
      _cooldownUntil = DateTime.now().add(_cooldownDuration);
      debugPrint(
        '[CfChallenge] 连续失败 $_consecutiveFailures 次，进入 ${_cooldownDuration.inSeconds}s 冷却期',
      );
      CfChallengeLogger.logCooldown(entering: true, until: _cooldownUntil);
    } else {
      debugPrint(
        '[CfChallenge] 验证失败 $_consecutiveFailures/$_maxFailuresBeforeCooldown，允许重试',
      );
    }
  }

  static void showGlobalMessage(String message, {bool isError = true}) {
    final now = DateTime.now();
    if (_lastToastAt != null &&
        now.difference(_lastToastAt!) < _toastCooldown) {
      return;
    }
    _lastToastAt = now;
    if (isError) {
      ToastService.showError(message);
    } else {
      ToastService.showInfo(message);
    }
  }

  /// 原生链路在完成验证后仍被 CF 拒绝时，询问用户是否仅在本次会话
  /// 使用浏览器网络栈。并发失败请求共享同一个弹窗结果。
  Future<bool> confirmSessionCompatibilityMode() {
    if (_sessionCompatPromptDeclined) return Future.value(false);
    final active = _activeSessionCompatPrompt;
    if (active != null) return active;

    late final Future<bool> future;
    future = _confirmSessionCompatibilityModeInternal().whenComplete(() {
      if (identical(_activeSessionCompatPrompt, future)) {
        _activeSessionCompatPrompt = null;
      }
    });
    _activeSessionCompatPrompt = future;
    return future;
  }

  Future<bool> _confirmSessionCompatibilityModeInternal() async {
    BuildContext? context = _context;
    if (context == null || !context.mounted) {
      context = navigatorKey.currentContext;
    }
    if (context == null || !context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.current.cf_sessionCompatTitle),
        content: Text(S.current.cf_sessionCompatMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.current.cf_sessionCompatEnable),
          ),
        ],
      ),
    );
    final confirmed = result == true;
    if (!confirmed) {
      // 用户本次会话已经明确拒绝，不在后续 CF 失败时反复打扰。
      _sessionCompatPromptDeclined = true;
    }
    return confirmed;
  }

  void resetSessionCompatibilityDecision() {
    _sessionCompatPromptDeclined = false;
  }

  void setContext(BuildContext context) {
    _context = context;
    if (context.mounted) {
      _contextReadyCompleter ??= Completer<BuildContext>();
      if (!_contextReadyCompleter!.isCompleted) {
        _contextReadyCompleter!.complete(context);
      }
    }
  }

  /// 综合响应头 + 响应体判断 dio Response 是否是 CF 验证响应。
  ///
  /// CF 根据请求的 Accept header 决定 challenge 响应格式:
  /// - 浏览器请求 (Accept: text/html) → 返 text/html "Just a moment..." 页面
  /// - API 请求 (Accept: application/json, text/plain) → 返 text/plain 简短挑战
  /// 但**两者都带 `cf-mitigated: challenge` header**, 这是 CF 官方权威信号。
  ///
  /// 状态码可能是 403 也可能是 429:
  /// - 普通 CF 盾(WAF / bot fight 等)→ 403 + cf-mitigated: challenge
  /// - 速率限制规则 action 配 managed_challenge / js_challenge / challenge → 429 + cf-mitigated: challenge
  /// 两种情况都应该交由 CfChallengeInterceptor 走验证流程,不能当成普通 403/429 处理。
  ///
  /// 历史上这里曾把 content-type 必须 text/html 作为前置条件,导致 dio 这种
  /// 默认 `Accept: application/json, text/plain, */*` 的客户端拿到 text/plain
  /// 时被漏掉, CfChallengeInterceptor 不弹手动验证。
  static bool isCfChallengeResponse(Response? response) {
    if (response == null) return false;
    final headers = response.headers;

    // 1. 必须来自 Cloudflare
    final server = headers.value('server') ?? '';
    if (!server.toLowerCase().contains('cloudflare')) return false;

    // 2. cf-mitigated: challenge — CF 官方权威信号, 不依赖 content-type
    final cfMitigated = headers.value('cf-mitigated') ?? '';
    if (cfMitigated.contains('challenge')) return true;

    // 3. fallback: 老版本 CF 或某些路径不带 cf-mitigated, 用 body 兜底,
    //    但 body 兜底只对 text/html 走 — 避免误判 Discourse 自己的 plaintext 403。
    final contentType = headers.value('content-type') ?? '';
    if (!contentType.contains('text/html')) return false;

    return isCfChallenge(response.data);
  }

  /// 检测是否是 CF 验证页面（用于 403 响应体判断）
  static bool isCfChallenge(dynamic responseData) {
    if (responseData == null) return false;
    final str = responseData.toString();
    // cf_chl_opt 是 CF 验证页面的可靠标记（challenge options JS 变量）
    if (str.contains('cf_chl_opt')) return true;
    // challenge-platform 路径需配合 cloudflare 标记，避免误匹配
    if (str.contains('challenge-platform') && str.contains('cloudflare')) {
      return true;
    }
    // "Just a moment" 需配合 CF 特征，避免误匹配用户内容
    if (str.contains('Just a moment') &&
        (str.contains('cloudflare') || str.contains('cf-challenge'))) {
      return true;
    }
    return false;
  }

  /// 检测页面 HTML 中是否有活跃的 CF 验证盾
  /// 用于判断已加载的页面是否仍在展示验证挑战
  static bool hasActiveCfChallenge(String html) {
    return html.contains('cf-turnstile') ||
        html.contains('challenge-running') ||
        html.contains('challenge-stage') ||
        html.contains('cf_chl_opt');
  }

  /// 检测页面 HTML 是否是源站返回的 404 / 非挑战内容
  /// 用于在 onReceivedHttpError 不可靠的平台上识别 Discourse 404 等非挑战页面
  static bool isOriginNotFound(String html) {
    if (html.isEmpty) return false;
    final lower = html.toLowerCase();
    // 仅保留稳定的 Discourse 自身特征，避免论坛名含 "404" 等场景误判
    return lower.contains('page-not-found') ||
        lower.contains('discourse-no-results') ||
        lower.contains('"errortype":"notfound"') ||
        lower.contains('404-body') ||
        lower.contains('exist or is private') ||
        lower.contains('page you requested');
  }

  /// 显示手动验证页面
  /// 返回值：true=验证成功, false=验证失败, null=冷却期内暂不可用或无 context
  /// [forceForeground] 是否强制前台显示（默认为 true）
  Future<bool?> showManualVerify([
    BuildContext? context,
    bool forceForeground = true,
  ]) async {
    // 检查冷却期
    if (isInCooldown) {
      debugPrint('[CfChallenge] In cooldown, skipping manual verify');
      CfChallengeLogger.log('[VERIFY] Skipped: in cooldown');
      return null;
    }

    final verifyUrl = '${AppConstants.baseUrl}/challenge';
    CfChallengeLogger.logVerifyStart(verifyUrl);

    // 尝试获取 context：传入的 > 已设置的 > 全局 navigatorKey
    BuildContext? ctx = context ?? _context;
    if (ctx == null || !ctx.mounted) {
      // 使用全局 navigatorKey 作为备用
      final navState = navigatorKey.currentState;
      if (navState != null && navState.context.mounted) {
        ctx = navState.context;
        debugPrint('[CfChallenge] Using global navigatorKey context');
      }
    }

    // 启动时可能还没有可用的 context，等到 context 可用后立即弹出
    if (ctx == null || !ctx.mounted) {
      _contextReadyCompleter ??= Completer<BuildContext>();
      debugPrint('[CfChallenge] Waiting for context to be ready...');
      ctx = await _contextReadyCompleter!.future;
    }
    if (!ctx.mounted) {
      debugPrint('[CfChallenge] Context no longer mounted');
      return null;
    }

    // 如果已经在验证中 (Overlay 存在)
    if (_isVerifying) {
      if (forceForeground) {
        final promote = _activePromoteToForeground;
        if (promote == null) {
          _pendingPromoteToForeground = true;
        } else {
          promote();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _activePromoteToForeground?.call();
        });
      }

      final completer = Completer<bool>();
      _verifyCompleter.add(completer);
      return completer.future;
    }

    _setVerifying(true);

    // ignore: use_build_context_synchronously
    final overlayState =
        Overlay.maybeOf(ctx, rootOverlay: true) ??
        navigatorKey.currentState?.overlay;
    if (overlayState == null) {
      debugPrint('[CfChallenge] No overlay available for manual verify');
      CfChallengeLogger.log('[VERIFY] No overlay available');
      _setVerifying(false);
      _pendingPromoteToForeground = false;
      return null;
    }

    // 停止自动续期服务，避免与手动验证冲突
    CfClearanceRefreshService().stop();

    // 备份旧 cf_clearance，验证失败时恢复（避免误删仍有效的值）
    final cookieJarService = CookieJarService();
    final backupCfClearance = await cookieJarService.getCfClearanceCookie();

    // Dio 请求已经 403，说明当前 cf_clearance 可能失效了。
    // 必须确保 WebView 中也没有旧的 cf_clearance，否则 CF 直接放行不显示盾。
    await cookieJarService.deleteCookie('cf_clearance');
    await cookieJarService.deleteWebViewCookie('cf_clearance');
    if (!overlayState.mounted) {
      debugPrint('[CfChallenge] Overlay no longer mounted');
      CfChallengeLogger.log('[VERIFY] Overlay not mounted');
      _setVerifying(false);
      _pendingPromoteToForeground = false;
      return null;
    }

    final resultCompleter = Completer<bool>();
    late final OverlayEntry entry;
    // 引用当前的拦截 Route，用于 cleanup
    ModalRoute? interceptorRoute;

    // Page Key 用于触发内部弹窗
    final pageKey = GlobalKey<CfChallengePageState>();
    _activePromoteToForeground = () {
      pageKey.currentState?.promoteToForeground();
    };
    if (_pendingPromoteToForeground) {
      _pendingPromoteToForeground = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _activePromoteToForeground?.call();
      });
    }

    // 清理资源
    void cleanup() {
      if (entry.mounted) {
        entry.remove();
      }
      if (interceptorRoute?.isActive ?? false) {
        interceptorRoute?.navigator?.removeRoute(interceptorRoute!);
      }
      _activePromoteToForeground = null;
      _pendingPromoteToForeground = false;
      _setVerifying(false);
    }

    void finish(bool success) {
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(success);
      }
      cleanup();
    }

    // 创建 OverlayEntry
    // 我们需要传递一个 promoteCallback 给 Page，让 Page 能调用 Service 来 push route
    void onPromoteToForeground(BuildContext pageContext) {
      if (interceptorRoute != null && interceptorRoute!.isActive) {
        return; // 已经有 Route 了
      }

      // Push 透明 Route 用于拦截返回键
      interceptorRoute = PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, _, _) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              if (!_isVerifying) return;

              // 触发内部弹窗 via GlobalKey
              pageKey.currentState?.showExitConfirmation();
            },
            // 使用 IgnorePointer 让点击事件穿透到下层的 Overlay (WebView)
            child: const IgnorePointer(child: SizedBox.expand()),
          );
        },
      );

      Navigator.of(pageContext).push(interceptorRoute!).then((_) {
        // Route 被 pop
      });
    }

    entry = OverlayEntry(
      builder: (context) => CfChallengePage(
        key: pageKey,
        verifyUrl: verifyUrl,
        startInBackground: !forceForeground,
        onResult: finish,
        onPromoteRequest: () => onPromoteToForeground(context),
        oldCfClearanceValue: backupCfClearance != null
            ? CookieValueCodec.decode(backupCfClearance.value)
            : null,
      ),
    );
    overlayState.insert(entry);

    // 如果初始就是前台，立即执行 promote
    if (forceForeground) {
      // Post frame callback to ensure overlay is mounted and context is valid
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 注意：这里的 ctx 是 Service 传入的 ctx，可能不是 Overlay 的 context
        // 但 Navigator.of(ctx) 应该能找到正确的 Navigator
        // 我们最好使用 OverlayEntry builder 里的 context，但这里访问不到。
        // 使用 ctx 应该是安全的。
        onPromoteToForeground(ctx!);
      });
    }

    final result = await resultCompleter.future;

    // 通知所有等待者
    for (final c in _verifyCompleter) {
      if (!c.isCompleted) c.complete(result);
    }
    _verifyCompleter.clear();

    // 验证成功后重置冷却期
    if (result == true) {
      resetCooldown();
      // 广播:一次 CF 挑战被成功解决,新 cf_clearance 已落 jar。
      clearanceResolvedAt.value = DateTime.now();
      CfChallengeLogger.logVerifyResult(
        success: true,
        reason: 'user completed',
      );
      // 手动验证成功后重新启动自动续期
      CfClearanceRefreshService().start();
    } else {
      // 验证失败，恢复备份的 cf_clearance（避免丢失可能仍有效的值）
      if (backupCfClearance != null) {
        await cookieJarService.restoreCfClearance(backupCfClearance);
        debugPrint('[CfChallenge] 验证失败，已恢复备份 cf_clearance');
      }
      // 验证失败，启动冷却期
      startCooldown();
      debugPrint(
        '[CfChallenge] Verification failed, cooldown until $_cooldownUntil',
      );
      CfChallengeLogger.logVerifyResult(
        success: false,
        reason: 'user cancelled or timeout',
      );
    }

    return result;
  }

  /// 用户主动触发的验证入口：允许绕过冷却期。
  Future<bool?> showManualVerifyNow([
    BuildContext? context,
    bool forceForeground = true,
  ]) {
    resetCooldown();
    return showManualVerify(context, forceForeground);
  }
}
