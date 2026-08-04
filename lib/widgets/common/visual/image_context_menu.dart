import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';
import 'package:gal/gal.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/s.dart';
import '../../../utils/share_utils.dart';
import '../../../models/topic.dart';
import '../../../pages/image_viewer_page.dart';
import '../../../services/discourse_cache_manager.dart';
import '../../../services/toast_service.dart';
import '../overlay/app_bottom_sheet.dart';
import '../../../utils/platform_utils.dart';
import '../../../utils/quote_builder.dart';
import '../../content/discourse_html_content/image_utils.dart';
import 'package:common_ui/common_ui.dart';

enum ImageContextMenuPresentation { standard, compactFloating }

/// Allows a render surface to opt its descendant images into a specialized
/// long-press menu without rebuilding the shared render callback bundle.
class ImageContextMenuScope extends InheritedWidget {
  const ImageContextMenuScope({
    super.key,
    required this.presentation,
    this.onMarkAd,
    required super.child,
  });

  final ImageContextMenuPresentation presentation;
  final VoidCallback? onMarkAd;

  static ImageContextMenuScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImageContextMenuScope>();

  @override
  bool updateShouldNotify(ImageContextMenuScope oldWidget) =>
      presentation != oldWidget.presentation || onMarkAd != oldWidget.onMarkAd;
}

/// 图片上下文菜单
///
/// 提供统一的图片操作菜单，可在内容页和图片查看页复用。
/// 桌面端支持在鼠标位置弹出 Popup Menu，移动端使用底部弹出菜单。
class ImageContextMenu {
  ImageContextMenu._();

  /// 显示图片上下文菜单
  ///
  /// [imageUrl] 图片 URL（会自动转换为原图 URL）
  /// [showViewFullImage] 是否显示「查看大图」选项（图片查看页内不需要）
  /// [post] 帖子对象（用于引用功能，为 null 时隐藏引用选项）
  /// [topicId] 话题 ID（用于引用功能）
  /// [onQuoteImage] 引用回调（打开回复框），为 null 时隐藏「引用」选项
  /// [position] 鼠标全局位置（桌面端右键时传入，用于定位 Popup Menu）
  /// [onClose] 关闭回调（图片查看页内传入，显示「关闭」选项）
  /// [heroTag] 源缩略图的 Hero tag（「查看大图」打开查看器时飞行转场用）
  static void show({
    required BuildContext context,
    required String imageUrl,
    bool showViewFullImage = true,
    Post? post,
    int? topicId,
    void Function(String quote, Post post)? onQuoteImage,
    Offset? position,
    VoidCallback? onClose,
    String? heroTag,
    ImageContextMenuPresentation? presentation,
    VoidCallback? onMarkAd,
    double? imageWidth,
    double? imageHeight,
    String? fileSizeText,
  }) {
    final originalUrl = DiscourseImageUtils.getOriginalUrl(imageUrl);
    final scope = ImageContextMenuScope.maybeOf(context);
    final effectivePresentation =
        presentation ??
        scope?.presentation ??
        ImageContextMenuPresentation.standard;
    final effectiveOnMarkAd = onMarkAd ?? scope?.onMarkAd;

    if (PlatformUtils.isDesktop && position != null) {
      _showDesktopMenu(
        context: context,
        originalUrl: originalUrl,
        imageUrl: imageUrl,
        showViewFullImage: showViewFullImage,
        post: post,
        topicId: topicId,
        onQuoteImage: onQuoteImage,
        position: position,
        onClose: onClose,
        heroTag: heroTag,
      );
    } else if (effectivePresentation ==
        ImageContextMenuPresentation.compactFloating) {
      _showCompactMobileMenu(
        context: context,
        originalUrl: originalUrl,
        imageUrl: imageUrl,
        showViewFullImage: showViewFullImage,
        post: post,
        topicId: topicId,
        onQuoteImage: onQuoteImage,
        heroTag: heroTag,
        onMarkAd: effectiveOnMarkAd,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        fileSizeText: fileSizeText,
      );
    } else {
      _showMobileMenu(
        context: context,
        originalUrl: originalUrl,
        imageUrl: imageUrl,
        showViewFullImage: showViewFullImage,
        post: post,
        topicId: topicId,
        onQuoteImage: onQuoteImage,
        onClose: onClose,
        heroTag: heroTag,
      );
    }
  }

  /// Chat images use a compact floating menu that mirrors the browser-style
  /// long-press surface while keeping every action inside the app.
  static void _showCompactMobileMenu({
    required BuildContext context,
    required String originalUrl,
    required String imageUrl,
    required bool showViewFullImage,
    Post? post,
    int? topicId,
    void Function(String quote, Post post)? onQuoteImage,
    String? heroTag,
    VoidCallback? onMarkAd,
    double? imageWidth,
    double? imageHeight,
    String? fileSizeText,
  }) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) {
        final theme = Theme.of(dialogContext);
        final size = MediaQuery.sizeOf(dialogContext);
        final menuWidth = (size.width * 0.64).clamp(260.0, 380.0).toDouble();

        void closeThen(VoidCallback action) {
          Navigator.of(dialogContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) action();
          });
        }

        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: menuWidth,
                    maxWidth: menuWidth,
                    maxHeight: size.height * 0.84,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    children: [
                      if (showViewFullImage)
                        _compactItem(
                          dialogContext,
                          S.current.image_view,
                          () => closeThen(
                            () => ImageViewerPage.open(
                              context,
                              originalUrl,
                              thumbnailUrl: imageUrl,
                              heroTag: heroTag,
                            ),
                          ),
                        ),
                      _compactItem(
                        dialogContext,
                        S.current.image_download,
                        () => closeThen(() => _saveImage(originalUrl)),
                      ),
                      _compactItem(
                        dialogContext,
                        S.current.common_shareImage,
                        () => closeThen(() => _shareImage(originalUrl)),
                      ),
                      _compactItem(
                        dialogContext,
                        S.current.image_reverseSearch,
                        () => closeThen(() => _openWithLens(originalUrl)),
                      ),
                      _compactItem(
                        dialogContext,
                        S.current.image_pageInfo,
                        () => closeThen(
                          () => _showImageInfo(
                            context,
                            originalUrl,
                            width: imageWidth,
                            height: imageHeight,
                            fileSizeText: fileSizeText,
                          ),
                        ),
                      ),
                      if (onMarkAd != null)
                        _compactItem(
                          dialogContext,
                          S.current.image_markAd,
                          () => closeThen(onMarkAd),
                        ),
                      _compactItem(
                        dialogContext,
                        S.current.image_moreOptions,
                        () => closeThen(
                          () => _showMobileMenu(
                            context: context,
                            originalUrl: originalUrl,
                            imageUrl: imageUrl,
                            showViewFullImage: showViewFullImage,
                            post: post,
                            topicId: topicId,
                            onQuoteImage: onQuoteImage,
                            heroTag: heroTag,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    );
  }

  static Widget _compactItem(
    BuildContext context,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
      ),
    );
  }

  /// 桌面端：在鼠标位置弹出 Popup Menu
  static void _showDesktopMenu({
    required BuildContext context,
    required String originalUrl,
    required String imageUrl,
    required bool showViewFullImage,
    Post? post,
    int? topicId,
    void Function(String quote, Post post)? onQuoteImage,
    required Offset position,
    VoidCallback? onClose,
    String? heroTag,
  }) {
    final overlayRenderObject = Overlay.of(context).context.findRenderObject();
    if (overlayRenderObject is! RenderBox || !overlayRenderObject.hasSize) {
      // Overlay 未就绪，回退到移动端菜单
      _showMobileMenu(
        context: context,
        originalUrl: originalUrl,
        imageUrl: imageUrl,
        showViewFullImage: showViewFullImage,
        post: post,
        topicId: topicId,
        onQuoteImage: onQuoteImage,
        heroTag: heroTag,
      );
      return;
    }
    final relativeRect = RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlayRenderObject.size,
    );

    final items = <PopupMenuEntry<String>>[
      if (showViewFullImage)
        PopupMenuItem(
          value: 'viewFull',
          child: _MenuItemRow(
            icon: Symbols.zoom_in_rounded,
            label: S.current.image_viewFull,
          ),
        ),
      PopupMenuItem(
        value: 'copyImage',
        child: _MenuItemRow(
          icon: Symbols.content_copy_rounded,
          label: S.current.image_copyImage,
        ),
      ),
      PopupMenuItem(
        value: 'copyLink',
        child: _MenuItemRow(
          icon: Symbols.link_rounded,
          label: S.current.image_copyLink,
        ),
      ),
      PopupMenuItem(
        value: 'share',
        child: _MenuItemRow(
          icon: Symbols.share_rounded,
          label: S.current.common_shareImage,
        ),
      ),
      if (post != null && topicId != null && onQuoteImage != null)
        PopupMenuItem(
          value: 'quote',
          child: _MenuItemRow(
            icon: Symbols.format_quote_rounded,
            label: S.current.common_quote,
          ),
        ),
      if (post != null && topicId != null)
        PopupMenuItem(
          value: 'copyQuote',
          child: _MenuItemRow(
            icon: Symbols.copy_all_rounded,
            label: S.current.common_copyQuote,
          ),
        ),
      if (onClose != null) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'close',
          child: _MenuItemRow(
            icon: Symbols.close_rounded,
            label: S.current.common_close,
          ),
        ),
      ],
    ];

    showSwipeDismissibleMenu<String>(
      context: context,
      position: relativeRect,
      items: items,
    ).then((value) {
      if (value == null) return;
      if (!context.mounted) return;
      _handleMenuAction(
        context: context,
        action: value,
        originalUrl: originalUrl,
        imageUrl: imageUrl,
        post: post,
        topicId: topicId,
        onQuoteImage: onQuoteImage,
        onClose: onClose,
        heroTag: heroTag,
      );
    });
  }

  /// 移动端：底部弹出菜单
  static void _showMobileMenu({
    required BuildContext context,
    required String originalUrl,
    required String imageUrl,
    required bool showViewFullImage,
    Post? post,
    int? topicId,
    void Function(String quote, Post post)? onQuoteImage,
    VoidCallback? onClose,
    String? heroTag,
  }) {
    AppBottomSheet.show(
      context: context,
      contentPadding: EdgeInsets.zero,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showViewFullImage)
              ListTile(
                leading: const Icon(Symbols.zoom_in_rounded),
                title: Text(S.current.image_viewFull),
                onTap: () {
                  Navigator.pop(ctx);
                  ImageViewerPage.open(
                    context,
                    originalUrl,
                    thumbnailUrl: imageUrl,
                    heroTag: heroTag,
                  );
                },
              ),
            ListTile(
              leading: const Icon(Symbols.content_copy_rounded),
              title: Text(S.current.image_copyImage),
              onTap: () {
                Navigator.pop(ctx);
                _copyImage(originalUrl);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.link_rounded),
              title: Text(S.current.image_copyLink),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: originalUrl));
                ToastService.showSuccess(S.current.common_linkCopied);
              },
            ),
            ListTile(
              leading: const Icon(Symbols.share_rounded),
              title: Text(S.current.common_shareImage),
              onTap: () {
                Navigator.pop(ctx);
                _shareImage(originalUrl);
              },
            ),
            if (post != null && topicId != null && onQuoteImage != null)
              ListTile(
                leading: const Icon(Symbols.format_quote_rounded),
                title: Text(S.current.common_quote),
                onTap: () {
                  Navigator.pop(ctx);
                  final quote = QuoteBuilder.build(
                    markdown: '![image]($originalUrl)',
                    username: post.username,
                    postNumber: post.postNumber,
                    topicId: topicId,
                  );
                  onQuoteImage(quote, post);
                },
              ),
            if (post != null && topicId != null)
              ListTile(
                leading: const Icon(Symbols.copy_all_rounded),
                title: Text(S.current.common_copyQuote),
                onTap: () {
                  Navigator.pop(ctx);
                  final quote = QuoteBuilder.build(
                    markdown: '![image]($originalUrl)',
                    username: post.username,
                    postNumber: post.postNumber,
                    topicId: topicId,
                  );
                  Clipboard.setData(ClipboardData(text: quote));
                  ToastService.showSuccess(S.current.common_quoteCopied);
                },
              ),
            if (onClose != null)
              ListTile(
                leading: const Icon(Symbols.close_rounded),
                title: Text(S.current.common_close),
                onTap: () {
                  Navigator.pop(ctx);
                  onClose();
                },
              ),
          ],
        );
      },
    );
  }

  /// 处理菜单选项
  static void _handleMenuAction({
    required BuildContext context,
    required String action,
    required String originalUrl,
    required String imageUrl,
    Post? post,
    int? topicId,
    void Function(String quote, Post post)? onQuoteImage,
    VoidCallback? onClose,
    String? heroTag,
  }) {
    switch (action) {
      case 'viewFull':
        ImageViewerPage.open(
          context,
          originalUrl,
          thumbnailUrl: imageUrl,
          heroTag: heroTag,
        );
      case 'copyImage':
        _copyImage(originalUrl);
      case 'copyLink':
        Clipboard.setData(ClipboardData(text: originalUrl));
        ToastService.showSuccess(S.current.common_linkCopied);
      case 'share':
        _shareImage(originalUrl);
      case 'quote':
        if (post != null && topicId != null && onQuoteImage != null) {
          final quote = QuoteBuilder.build(
            markdown: '![image]($originalUrl)',
            username: post.username,
            postNumber: post.postNumber,
            topicId: topicId,
          );
          onQuoteImage(quote, post);
        }
      case 'copyQuote':
        if (post != null && topicId != null) {
          final quote = QuoteBuilder.build(
            markdown: '![image]($originalUrl)',
            username: post.username,
            postNumber: post.postNumber,
            topicId: topicId,
          );
          Clipboard.setData(ClipboardData(text: quote));
          ToastService.showSuccess(S.current.common_quoteCopied);
        }
      case 'close':
        onClose?.call();
    }
  }

  static Future<void> _saveImage(String imageUrl) async {
    try {
      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) {
        ToastService.showInfo(S.current.imageViewer_grantPermission);
        return;
      }
      final bytes = await BlobImageCache.fetch(
        BlobImageCache.originalBucket,
        imageUrl,
      );
      if (bytes.isEmpty) {
        ToastService.showError(S.current.image_fetchFailed);
        return;
      }
      final ext = _getExtensionFromUrl(imageUrl);
      await Gal.putImageBytes(
        bytes,
        name: 'fluxdo_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      ToastService.showSuccess(S.current.imageViewer_imageSaved);
    } catch (error) {
      debugPrint('[ImageContextMenu] saveImage error: $error');
      ToastService.showError(S.current.imageViewer_saveFailedRetry);
    }
  }

  static Future<void> _openWithLens(String imageUrl) async {
    try {
      final uri = Uri.https('lens.google.com', '/uploadbyurl', {
        'url': imageUrl,
      });
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) ToastService.showError(S.current.common_cannotOpenBrowser);
    } catch (error) {
      debugPrint('[ImageContextMenu] openWithLens error: $error');
      ToastService.showError(S.current.common_cannotOpenBrowser);
    }
  }

  static void _showImageInfo(
    BuildContext context,
    String imageUrl, {
    double? width,
    double? height,
    String? fileSizeText,
  }) {
    final dimensions = width != null && height != null
        ? '${width.round()} × ${height.round()}'
        : null;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.current.image_pageInfo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dimensions != null) ...[
              Text(
                dimensions,
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
            ],
            if (fileSizeText != null && fileSizeText.isNotEmpty) ...[
              Text(fileSizeText),
              const SizedBox(height: 8),
            ],
            SelectableText(imageUrl),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.current.common_close),
          ),
        ],
      ),
    );
  }

  /// 复制图片到剪贴板
  static Future<void> _copyImage(String imageUrl) async {
    try {
      final bytes = await BlobImageCache.fetch(
        BlobImageCache.contentBucket,
        imageUrl,
      );
      if (bytes.isEmpty) {
        ToastService.showError(S.current.image_fetchFailed);
        return;
      }
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        ToastService.showError(S.current.common_clipboardUnavailable);
        return;
      }
      final item = DataWriterItem();
      item.add(Formats.png(bytes));
      await clipboard.write([item]);
      ToastService.showSuccess(S.current.image_copied);
    } catch (e) {
      debugPrint('[ImageContextMenu] copyImage error: $e');
      ToastService.showError(S.current.image_copyFailed);
    }
  }

  /// 分享图片
  static Future<void> _shareImage(String imageUrl) async {
    try {
      final file = await BlobImageCache.getFile(
        BlobImageCache.contentBucket,
        imageUrl,
      );
      final ext = _getExtensionFromUrl(imageUrl);
      final xFile = XFile(file.path, mimeType: 'image/$ext');
      await ShareUtils.shareOrSaveFile(xFile);
    } catch (e) {
      debugPrint('[ImageContextMenu] shareImage error: $e');
      ToastService.showError(S.current.common_shareFailed);
    }
  }

  /// 从 URL 提取文件扩展名
  static String _getExtensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'png';
    final path = uri.path.toLowerCase();
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'jpeg';
    if (path.endsWith('.gif')) return 'gif';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.avif')) return 'avif';
    return 'png';
  }
}

/// Popup Menu 菜单项行（图标 + 文字）
class _MenuItemRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuItemRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}
