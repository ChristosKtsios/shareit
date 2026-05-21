import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DistanceSliderWidget extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const DistanceSliderWidget({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 16),
          const SizedBox(width: 6),
          Text(
            value >= 800
                ? 'Όλη η Ελλάδα'
                : 'Εμβέλεια: ${value.toInt()} χλμ',
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
            value: value,
            min:   1,
            max:   800,
            divisions: 80,
            onChanged: onChanged,
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1 χλμ',
                style: TextStyle(
                    color: AppColors.textHint, fontSize: 11)),
            Text('800 χλμ',
                style: TextStyle(
                    color: AppColors.textHint, fontSize: 11)),
          ],
        ),
      ]),
    );
  }
}