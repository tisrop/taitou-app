import 'package:flutter/material.dart';
import '../common/overlay/skeleton.dart';

/// 通知列表骨架屏
class NotificationListSkeleton extends StatelessWidget {
  const NotificationListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: 10,
        itemBuilder: (context, index) => const _NotificationItemSkeleton(),
      ),
    );
  }
}

/// 单个通知项的骨架屏
class _NotificationItemSkeleton extends StatelessWidget {
  const _NotificationItemSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            width: 0.75,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SkeletonCircle(size: 24),
            ),
          ),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 96, height: 16),
                SizedBox(height: 6),
                SkeletonBox(width: double.infinity, height: 16),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const SkeletonBox(width: 48, height: 14),
        ],
      ),
    );
  }
}
