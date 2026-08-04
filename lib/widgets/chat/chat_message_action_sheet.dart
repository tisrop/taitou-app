import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/chat/chat_message.dart';
import '../common/visual/smart_avatar.dart';

enum ChatMessageAction {
  copyLink,
  copyText,
  select,
  pin,
  report,
  delete,
  rebake,
  bookmark,
  reply,
  reaction,
  moreReactions,
}

class ChatMessageActionResult {
  final ChatMessageAction action;
  final String? emoji;

  const ChatMessageActionResult(this.action, {this.emoji});
}

class ChatMessageActionSheet extends StatelessWidget {
  const ChatMessageActionSheet({
    super.key,
    required this.message,
    required this.canModerate,
    required this.canDelete,
    required this.canReport,
  });

  final ChatMessage message;
  final bool canModerate;
  final bool canDelete;
  final bool canReport;

  void _pop(BuildContext context, ChatMessageAction action, {String? emoji}) {
    Navigator.of(context).pop(ChatMessageActionResult(action, emoji: emoji));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = message.isLocal || message.isDeleted;
    final preview =
        (message.excerpt?.trim().isNotEmpty == true
                ? message.excerpt!
                : message.message)
            .trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              SmartAvatar(
                imageUrl: message.user.avatarTemplate.isEmpty
                    ? null
                    : message.user.getAvatarUrl(size: 64),
                radius: 20,
                fallbackText: message.user.displayName,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  preview.isEmpty ? context.l10n.chat_messageNoText : preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              children: [
                _item(
                  context,
                  icon: Icons.link_rounded,
                  label: context.l10n.chat_messageCopyLink,
                  onTap: disabled
                      ? null
                      : () => _pop(context, ChatMessageAction.copyLink),
                ),
                _item(
                  context,
                  icon: Icons.content_copy_rounded,
                  label: context.l10n.chat_messageCopyText,
                  onTap: message.message.trim().isEmpty
                      ? null
                      : () => _pop(context, ChatMessageAction.copyText),
                ),
                _item(
                  context,
                  icon: Icons.checklist_rounded,
                  label: context.l10n.chat_messageSelect,
                  onTap: disabled
                      ? null
                      : () => _pop(context, ChatMessageAction.select),
                ),
                if (canModerate)
                  _item(
                    context,
                    icon: message.pinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                    label: message.pinned
                        ? context.l10n.chat_messageUnpin
                        : context.l10n.chat_messagePin,
                    onTap: disabled
                        ? null
                        : () => _pop(context, ChatMessageAction.pin),
                  ),
                if (canReport)
                  _item(
                    context,
                    icon: Icons.flag_rounded,
                    label: context.l10n.chat_messageReport,
                    onTap: disabled
                        ? null
                        : () => _pop(context, ChatMessageAction.report),
                  ),
                if (canDelete)
                  _item(
                    context,
                    icon: Icons.delete_rounded,
                    label: context.l10n.chat_messageDelete,
                    foregroundColor: theme.colorScheme.error,
                    onTap: disabled
                        ? null
                        : () => _pop(context, ChatMessageAction.delete),
                  ),
                if (canModerate)
                  _item(
                    context,
                    icon: Icons.sync_rounded,
                    label: context.l10n.chat_messageRebake,
                    onTap: disabled
                        ? null
                        : () => _pop(context, ChatMessageAction.rebake),
                  ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _reaction(context, '👍', '+1', disabled),
                _reaction(context, '❤️', 'heart', disabled),
                _reaction(context, '🎉', 'tada', disabled),
                _bottomAction(
                  context,
                  icon: Icons.add_reaction_rounded,
                  tooltip: context.l10n.chat_messageMoreReactions,
                  onPressed: disabled
                      ? null
                      : () => _pop(context, ChatMessageAction.moreReactions),
                ),
                _bottomAction(
                  context,
                  icon: message.bookmarkId == null
                      ? Icons.bookmark_border_rounded
                      : Icons.bookmark_rounded,
                  tooltip: message.bookmarkId == null
                      ? context.l10n.chat_messageBookmark
                      : context.l10n.chat_messageRemoveBookmark,
                  onPressed: disabled
                      ? null
                      : () => _pop(context, ChatMessageAction.bookmark),
                ),
                _bottomAction(
                  context,
                  icon: Icons.reply_rounded,
                  tooltip: context.l10n.chat_messageReply,
                  onPressed: disabled
                      ? null
                      : () => _pop(context, ChatMessageAction.reply),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? foregroundColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: foregroundColor),
      title: Text(label, style: TextStyle(color: foregroundColor)),
      enabled: onTap != null,
      onTap: onTap,
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  Widget _reaction(
    BuildContext context,
    String glyph,
    String name,
    bool disabled,
  ) {
    final reacted = message.reactions.any(
      (reaction) => reaction.emoji == name && reaction.reacted,
    );
    return IconButton(
      onPressed: disabled
          ? null
          : () => _pop(context, ChatMessageAction.reaction, emoji: name),
      tooltip: glyph,
      style: IconButton.styleFrom(
        backgroundColor: reacted
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
      ),
      icon: Text(glyph, style: const TextStyle(fontSize: 27)),
    );
  }

  Widget _bottomAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 29),
    );
  }
}
