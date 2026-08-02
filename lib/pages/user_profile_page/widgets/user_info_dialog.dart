import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/user.dart';
import '../../../utils/time_utils.dart';
import '../../../utils/fluxdo_render_callbacks.dart';
import '../../../utils/dialog_utils.dart';
import '../../../l10n/s.dart';

/// 用户主页右上角「关于」弹窗。
///
/// 只读展示用户简介 / 封禁禁言状态 / 位置 / 网站 / 加入时间。
/// 从 _UserProfilePageState._showUserInfo 抽出,逻辑零变化。
void showUserInfoDialog(BuildContext context, User user) {
  final hasBio = user.bio != null && user.bio!.isNotEmpty;
  final hasLocation = user.location != null && user.location!.isNotEmpty;
  final hasWebsite = user.website != null && user.website!.isNotEmpty;
  final hasJoinedAt = user.createdAt != null;
  final isSuspended = user.isSuspended;
  final isSilenced = user.isSilenced;

  if (!hasBio && !hasLocation && !hasWebsite && !hasJoinedAt && !isSuspended && !isSilenced) return;

  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 标题栏
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Row(
                  children: [
                    Text(
                      context.l10n.common_about,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),

              // 内容
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  children: [
                    // 封禁/禁言状态
                    if (isSuspended)
                      _buildRestrictionSection(
                        theme,
                        icon: Symbols.block_rounded,
                        title: context.l10n.userProfile_suspendedStatus,
                        label: user.isSuspendedForever
                            ? context.l10n.userProfile_permanentlySuspended
                            : context.l10n.userProfile_suspendedUntil(TimeUtils.formatFullDate(user.suspendedTill)),
                        reason: user.suspendReason,
                        color: theme.colorScheme.error,
                      ),
                    if (isSilenced)
                      _buildRestrictionSection(
                        theme,
                        icon: Symbols.mic_off_rounded,
                        title: context.l10n.userProfile_silencedStatus,
                        label: user.isSilencedForever
                            ? context.l10n.userProfile_permanentlySilenced
                            : context.l10n.userProfile_silencedUntil(TimeUtils.formatFullDate(user.silencedTill)),
                        reason: user.silenceReason,
                        color: Colors.orange,
                      ),

                    // 个人简介
                    if (hasBio) ...[
                      Text(
                        context.l10n.userProfile_bio,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 个人简介属只读展示：走新引擎 FluxdoRender，关闭划词选区。
                      FluxdoRenderCallbacks.generic(
                        heroTagNamespace: 'user_profile_bio_${user.username}',
                      ).render(
                        cookedHtml: user.bio!,
                        baseTextStyle: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                        ),
                        selectionEnabled: false,
                      ),
                      const SizedBox(height: 32),
                    ],

                    // 其他信息列表
                    if (hasLocation || hasWebsite || hasJoinedAt) ...[
                      Text(
                        context.l10n.userProfile_moreInfo,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        ),
                      const SizedBox(height: 16),

                      if (hasLocation)
                        _buildInfoRow(
                          context,
                          Symbols.location_on_rounded,
                          context.l10n.userProfile_location,
                          user.location!,
                        ),

                      if (hasWebsite)
                        _buildInfoRow(
                          context,
                          Symbols.link_rounded,
                          context.l10n.userProfile_website,
                          user.websiteName ?? user.website!,
                          url: user.website,
                          isLink: true,
                        ),

                      if (hasJoinedAt)
                        _buildInfoRow(
                          context,
                          Symbols.calendar_today_rounded,
                          context.l10n.userProfile_joinDate,
                          TimeUtils.formatFullDate(user.createdAt),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// 关于弹窗中的封禁/禁言区块
Widget _buildRestrictionSection(
  ThemeData theme, {
  required IconData icon,
  required String title,
  required String label,
  required String? reason,
  required Color color,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value, {String? url, bool isLink = false}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: InkWell(
      onTap: isLink && url != null ? () => launchUrl(Uri.parse(url)) : null,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isLink ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                    decoration: isLink ? TextDecoration.underline : null,
                    decorationColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
          if (isLink)
            Icon(
              Symbols.open_in_new_rounded,
              size: 16,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
        ],
      ),
    ),
  );
}
