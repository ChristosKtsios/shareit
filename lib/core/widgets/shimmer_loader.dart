import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../constants/app_colors.dart';

class ShimmerCard extends StatelessWidget {
  final double height;
  const ShimmerCard({super.key, this.height = 120});
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: AppColors.surfaceVariant,
    highlightColor: AppColors.borderLight,
    child: Container(height: height,
        decoration: BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.circular(14))),
  );
}

class ShimmerList extends StatelessWidget {
  final int count;
  const ShimmerList({super.key, this.count = 5});
  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: count,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, __) => const ShimmerCard(),
  );
}
