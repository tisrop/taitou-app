import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../models/chat/chat_channel.dart';
import '../../utils/color_utils.dart';
import '../common/text/emoji_text.dart';
import '../common/visual/smart_avatar.dart';

/// 频道图标，对齐网页版 `ChatChannelIcon`（plugins/chat 的 channel-icon 组件）：
///
/// - 分类（公开）频道：有 `emoji` 就渲染 emoji，否则渲染 `d-chat` 图标；
///   颜色取 `chatable.color` 作为**前景色**（网页是 `style="color: #xxxxxx"`），
///   不是圆形底色。分类为受限访问时右上角叠一个小锁。
/// - 直接消息频道：渲染对方头像。
///
/// 网页版的 `d-chat` 是别名，`chat-setup.js` 里 `replaceIcon("d-chat", "comment")`
/// 把它映射到 FontAwesome solid `comment`，所以这里用 [FontAwesomeIcons.solidComment]。
class ChatChannelIcon extends StatelessWidget {
  const ChatChannelIcon({super.key, required this.channel, this.size = 40});

  final ChatChannel channel;

  /// 图标占位的边长（与列表里的头像对齐）。
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: channel.isDirectMessage
          ? _buildDirectMessageAvatar(context)
          : _buildCategoryIcon(context),
    );
  }

  /// 分类频道图标：emoji / d-chat，外加受限分类的小锁。
  Widget _buildCategoryIcon(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = channel.emoji?.trim();
    final glyphSize = size * 0.6;

    // 网页版 emoji 存的是 shortcode 名（如 `speech_balloon`），要补冒号再渲染。
    // EmojiText 会按 fontSize * 1.2 出图，这里反算一下让 emoji 和图标一样大。
    final Widget glyph = (emoji != null && emoji.isNotEmpty)
        ? EmojiText(':$emoji:', style: TextStyle(fontSize: glyphSize / 1.2))
        : FaIcon(
            FontAwesomeIcons.solidComment,
            size: glyphSize,
            color: _categoryColor(context),
          );

    if (!channel.chatableReadRestricted) {
      return Center(child: glyph);
    }

    // 受限分类：网页版在图标右上角叠一个带底色的小锁。
    final lockSize = size * 0.3;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(child: glyph),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: EdgeInsets.all(lockSize * 0.15),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Symbols.lock_rounded,
              size: lockSize,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// 分类色。网页是为亮色背景设计的，交给 [ColorUtils.readableOn] 适配当前主题；
  /// 拿不到颜色时退回主题的次要前景色。
  Color _categoryColor(BuildContext context) {
    final theme = Theme.of(context);
    final hex = channel.chatableColor?.replaceFirst('#', '').trim();
    if (hex == null || hex.length != 6) {
      return theme.colorScheme.onSurfaceVariant;
    }
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return theme.colorScheme.onSurfaceVariant;
    return ColorUtils.readableOn(Color(0xFF000000 | value), theme.brightness);
  }

  /// 直接消息频道：取一个非自己的成员头像（chatable.users 已排除自己）。
  Widget _buildDirectMessageAvatar(BuildContext context) {
    final users = channel.directMessageUsers;
    final user = users.isNotEmpty ? users.first : null;
    final avatarUrl = user?.getAvatarUrl(size: size.round());
    if (user == null || avatarUrl == null || avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        child: AppIcon(AppIcons.person, size: size * 0.55),
      );
    }
    return SmartAvatar(
      imageUrl: avatarUrl,
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      fallbackText: user.username,
    );
  }
}
