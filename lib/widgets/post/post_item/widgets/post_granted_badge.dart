import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../../models/topic.dart';
import '../../../../services/discourse_cache_manager.dart';
import '../../../../utils/font_awesome_helper.dart';
import '../../../../utils/url_helper.dart';

/// 帖子头部徽章图标
class PostGrantedBadgeIcon extends StatelessWidget {
  final GrantedBadge badge;

  const PostGrantedBadgeIcon({super.key, required this.badge});

  /// 徽章说明可能包含链接和 HTML 实体，Tooltip 只显示纯文本。
  static String _plainText(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
  }

  /// 根据徽章类型获取颜色（1=Gold, 2=Silver, 3=Bronze）
  Color _badgeTypeColor(ThemeData theme) {
    switch (badge.badgeTypeId) {
      case 1:
        return const Color(0xFFE5A100);
      case 2:
        return const Color(0xFF9A9A9A);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _badgeTypeColor(theme);
    final description = badge.description != null
        ? _plainText(badge.description!)
        : '';
    final tooltip = description.isNotEmpty ? description : badge.name;

    // 优先使用图片
    if (badge.imageUrl != null && badge.imageUrl!.isNotEmpty) {
      final url = UrlHelper.resolveUrlWithCdn(badge.imageUrl!);
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Image(
            image: discourseImageProvider(url),
            width: 14,
            height: 14,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
    }

    // 使用 FontAwesome 图标
    if (badge.icon != null && badge.icon!.isNotEmpty) {
      final iconData = FontAwesomeHelper.getIcon(badge.icon!);
      if (iconData != null) {
        return Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: FaIcon(iconData, size: 12, color: color),
          ),
        );
      }
    }

    return const SizedBox.shrink();
  }
}
