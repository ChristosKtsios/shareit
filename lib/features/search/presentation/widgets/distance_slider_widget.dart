import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';

class DistanceSliderWidget extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  /// Λογικά όρια ακτίνας (χλμ) — bounded ώστε να μη φορτώνει υπερβολικά δεδομένα.
  final double min;
  final double max;

  const DistanceSliderWidget({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) {
    final km = 'map.unitKm'.tr();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 16),
          const SizedBox(width: 6),
          Text(
            'dist.range'.tr(namedArgs: {'n': '${value.toInt()}'}),
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor:   AppColors.primary,
            inactiveTrackColor: AppColors.surfaceVariant,
            thumbColor:         AppColors.primary,
            overlayColor:
                AppColors.primary.withValues(alpha: 0.15),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min:   min,
            max:   max,
            divisions: (max - min).toInt(),
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${min.toInt()} $km',
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 11)),
            Text('${max.toInt()} $km',
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 11)),
          ],
        ),
      ]),
    );
  }
}