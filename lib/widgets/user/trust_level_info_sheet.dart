import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../common/overlay/app_bottom_sheet.dart';

/// Compact trust-level label used on profile surfaces.
class TrustLevelBadge extends StatelessWidget {
  const TrustLevelBadge({
    super.key,
    required this.level,
    this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.textStyle,
  });

  final int level;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = trustLevelLabel(context, level);
    final content = Padding(
      padding: padding,
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(
              color: foregroundColor ?? theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w500,
            )
            .merge(textStyle),
      ),
    );

    final badge = Material(
      color: backgroundColor ?? theme.colorScheme.secondaryContainer,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              key: ValueKey('trust-level-badge-$level'),
              onTap: onTap,
              child: content,
            ),
    );

    return Semantics(
      button: onTap != null,
      label: label,
      child: onTap == null
          ? badge
          : Tooltip(message: context.l10n.user_trustLevelTitle, child: badge),
    );
  }
}

/// Trust-level overview shown from profile badges.
abstract final class TrustLevelInfoSheet {
  static Future<void> show({
    required BuildContext context,
    required int currentLevel,
    bool? canChat,
  }) {
    return AppBottomSheet.show<void>(
      context: context,
      title: context.l10n.user_trustLevelTitle,
      builder: (context) =>
          TrustLevelInfoContent(currentLevel: currentLevel, canChat: canChat),
    );
  }
}

class TrustLevelInfoContent extends StatelessWidget {
  const TrustLevelInfoContent({
    super.key,
    required this.currentLevel,
    this.canChat,
  });

  final int currentLevel;
  final bool? canChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('trust-level-current'),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Symbols.shield_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.user_trustLevelCurrent,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trustLevelLabel(context, currentLevel),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canChat != null) _ChatCapabilityChip(canChat: canChat!),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.user_trustLevelOverview,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (var level = 0; level <= 4; level++) ...[
            _TrustLevelRow(level: level, selected: level == currentLevel),
            if (level != 4) const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.user_trustLevelPermissionNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatCapabilityChip extends StatelessWidget {
  const _ChatCapabilityChip({required this.canChat});

  final bool canChat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = canChat
        ? colorScheme.onTertiaryContainer
        : colorScheme.onErrorContainer;

    return Container(
      key: ValueKey(
        'trust-level-chat-${canChat ? 'available' : 'unavailable'}',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: canChat
            ? colorScheme.tertiaryContainer
            : colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        canChat
            ? context.l10n.user_trustLevelChatAvailable
            : context.l10n.user_trustLevelChatUnavailable,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TrustLevelRow extends StatelessWidget {
  const _TrustLevelRow({required this.level, required this.selected});

  final int level;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      key: ValueKey('trust-level-row-$level'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: selected
            ? Border.all(color: colorScheme.secondary, width: 1.5)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.secondary
                    : colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  'L$level',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? colorScheme.onSecondary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trustLevelLabel(context, level),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  trustLevelDescription(context, level),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(
              Symbols.check_circle_rounded,
              size: 20,
              color: colorScheme.secondary,
            ),
          ],
        ],
      ),
    );
  }
}

String trustLevelLabel(BuildContext context, int level) {
  return switch (level) {
    0 => context.l10n.user_trustLevel0,
    1 => context.l10n.user_trustLevel1,
    2 => context.l10n.user_trustLevel2,
    3 => context.l10n.user_trustLevel3,
    4 => context.l10n.user_trustLevel4,
    _ => context.l10n.user_trustLevelUnknown(level),
  };
}

String trustLevelDescription(BuildContext context, int level) {
  return switch (level) {
    0 => context.l10n.user_trustLevelDescription0,
    1 => context.l10n.user_trustLevelDescription1,
    2 => context.l10n.user_trustLevelDescription2,
    3 => context.l10n.user_trustLevelDescription3,
    4 => context.l10n.user_trustLevelDescription4,
    _ => context.l10n.user_trustLevelPermissionNote,
  };
}
