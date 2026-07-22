import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/listing_model.dart';

class ListingImagesWidget extends StatelessWidget {
  final ListingModel listing;
  const ListingImagesWidget({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    if (listing.imageUrls.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: listing.imageUrls.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => context.push(
              '/listing/${listing.id}/images?i=$i',
              extra: List<String>.from(listing.imageUrls),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(children: [
                CachedNetworkImage(
                  imageUrl: listing.imageUrls[i],
                  width: 260,
                  height: 200,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 260,
                    height: 200,
                    color: AppColors.surfaceVariant,
                    child: const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 260,
                    height: 200,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.broken_image,
                        color: AppColors.textHint, size: 40),
                  ),
                ),
                // Counter badge
                if (listing.imageUrls.length > 1)
                  Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${i + 1}/${listing.imageUrls.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      )),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
