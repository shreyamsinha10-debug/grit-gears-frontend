// ---------------------------------------------------------------------------
// Skeleton loading – placeholders and haptics.
// ---------------------------------------------------------------------------
// [SkeletonBox], [SkeletonMemberList], [SkeletonDashboard] show grey placeholders
// while data is loading. [hapticSuccess] / [hapticSelection] for light feedback on actions.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Premium skeleton placeholder for lists and cards. Use while loading.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton for a list of member-style cards.
class SkeletonMemberList extends StatelessWidget {
  final int itemCount;

  const SkeletonMemberList({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          color: AppTheme.surfaceVariant,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const SkeletonBox(width: 44, height: 44, borderRadius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: double.infinity, height: 16, borderRadius: 4),
                      const SizedBox(height: 8),
                      SkeletonBox(width: 120, height: 12, borderRadius: 4),
                      const SizedBox(height: 4),
                      SkeletonBox(width: 100, height: 12, borderRadius: 4),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SkeletonBox(width: 50, height: 20, borderRadius: 6),
                          const SizedBox(width: 8),
                          SkeletonBox(width: 45, height: 20, borderRadius: 6),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SkeletonBox(width: 70, height: 36, borderRadius: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton for analytics/dashboard cards.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 80, borderRadius: 16)),
              const SizedBox(width: 16),
              Expanded(child: SkeletonBox(height: 80, borderRadius: 16)),
            ],
          ),
          const SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 80, borderRadius: 16),
          const SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 80, borderRadius: 16),
          const SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 50, borderRadius: 12),
        ],
      ),
    );
  }
}

/// Light haptic feedback for actions (check-in, pay, success).
void hapticSuccess() {
  HapticFeedback.lightImpact();
}

void hapticSelection() {
  HapticFeedback.selectionClick();
}
