import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/listing_model.dart';

class ListingHeaderWidget extends StatelessWidget {
  final ListingModel listing;
  const ListingHeaderWidget({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final isOffer = listing.type == ListingType.offer;
    final color = isOffer ? AppColors.offer : AppColors.seek;
    final label = isOffer ? AppStrings.offer : AppStrings.seek;
    final emoji = isOffer ? '🤲' : '🔍';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text('$emoji $label',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 14),
      Text(listing.title,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Text(listing.description,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 15, height: 1.5)),
      if (listing.tags.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: listing.tags
              .map((t) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('#$t',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ))
              .toList(),
        ),
      ],
    ]);
  }
}
