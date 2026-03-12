import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:sportwai/config/theme.dart';

/// Base shimmer wrapper — dark-theme aware.
class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
      highlightColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ─── Workout list skeleton ──────────────────────────────────────────────────

class WorkoutCardSkeleton extends StatelessWidget {
  const WorkoutCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _ShimmerBox(width: 180, height: 18, borderRadius: BorderRadius.circular(6)),
              const Spacer(),
              _ShimmerBox(width: 40, height: 18, borderRadius: BorderRadius.circular(6)),
            ]),
            const SizedBox(height: 10),
            _ShimmerBox(width: 120, height: 13, borderRadius: BorderRadius.circular(5)),
            const SizedBox(height: 8),
            _ShimmerBox(width: double.infinity, height: 13, borderRadius: BorderRadius.circular(5)),
          ],
        ),
      ),
    );
  }
}

class WorkoutListSkeleton extends StatelessWidget {
  final int count;
  const WorkoutListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(count, (_) => const WorkoutCardSkeleton()),
      ),
    );
  }
}

// ─── History list skeleton ──────────────────────────────────────────────────

class SessionCardSkeleton extends StatelessWidget {
  const SessionCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Column(children: [
            _ShimmerBox(width: 28, height: 22, borderRadius: BorderRadius.circular(5)),
            const SizedBox(height: 4),
            _ShimmerBox(width: 22, height: 12, borderRadius: BorderRadius.circular(4)),
          ]),
          const SizedBox(width: 24),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _ShimmerBox(width: 140, height: 15, borderRadius: BorderRadius.circular(5)),
              const SizedBox(height: 6),
              _ShimmerBox(width: 80, height: 12, borderRadius: BorderRadius.circular(4)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class HistoryListSkeleton extends StatelessWidget {
  final int count;
  const HistoryListSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShimmerBox(width: 100, height: 14, borderRadius: BorderRadius.circular(5)),
          const SizedBox(height: 12),
          ...List.generate(count, (_) => const SessionCardSkeleton()),
        ],
      ),
    );
  }
}

// ─── Analytics skeleton ─────────────────────────────────────────────────────

class AnalyticsSkeleton extends StatelessWidget {
  const AnalyticsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(children: [
            _statBox(),
            const SizedBox(width: 12),
            _statBox(),
            const SizedBox(width: 12),
            _statBox(),
          ]),
          const SizedBox(height: 16),
          // Chart placeholder
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Shimmer.fromColors(
              baseColor: const Color(0xFF2A2A2A),
              highlightColor: const Color(0xFF3A3A3A),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ShimmerBox(width: 140, height: 16, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 12),
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Shimmer.fromColors(
              baseColor: const Color(0xFF2A2A2A),
              highlightColor: const Color(0xFF3A3A3A),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox() => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            _ShimmerBox(width: 36, height: 24, borderRadius: BorderRadius.circular(5)),
            const SizedBox(height: 6),
            _ShimmerBox(width: 50, height: 11, borderRadius: BorderRadius.circular(4)),
          ]),
        ),
      );
}
