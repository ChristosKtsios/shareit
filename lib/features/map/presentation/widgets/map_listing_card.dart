import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../listings/data/listing_model.dart';

class MapListingCard extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback onClose;

  const MapListingCard({
    super.key,
    required this.listing,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isOffer = listing.type == ListingType.offer;
    final color = isOffer ? AppColors.offer : AppColors.seek;
    final label = isOffer ? '🤲 Προσφέρω' : '🔍 Αναζητώ';

    return GestureDetector(
      onTap: () => context.push('/listing/${listing.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: user info (LIVE από Firestore) + close
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(listing.userId)
                  .snapshots(),
              builder: (context, snap) {
                String displayName = listing.userFirstName.isNotEmpty
                    ? listing.userFirstName
                    : 'Χρήστης';
                String? avatarUrl = listing.userAvatarUrl;

                if (snap.hasData && snap.data!.exists) {
                  final d = snap.data!.data() as Map<String, dynamic>;
                  final first = (d['firstName'] as String?) ?? '';
                  final last = (d['lastName'] as String?) ?? '';
                  final full =
                      last.isNotEmpty ? '$first $last'.trim() : first.trim();
                  if (full.isNotEmpty) displayName = full;
                  avatarUrl = (d['avatarUrl'] as String?) ??
                      (d['photoUrl'] as String?) ??
                      avatarUrl;
                }

                final initial =
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

                return Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/profile/${listing.userId}'),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.2),
                        backgroundImage:
                            avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null
                            ? Text(initial,
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600))
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push('/profile/${listing.userId}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(label,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 14, color: AppColors.textHint),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // Title
            Text(listing.title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),

            // Description
            if (listing.description.isNotEmpty) ...[
              Text(listing.description,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
            ],

            // Photos carousel (αν υπάρχουν)
            if (listing.imageUrls.isNotEmpty) ...[
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: listing.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      listing.imageUrls[i],
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 70,
                          height: 70,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.image_not_supported,
                              color: AppColors.textHint)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Tags
            if (listing.tags.isNotEmpty) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: listing.tags
                    .take(4)
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('#$t',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],

            Row(children: [
              const Icon(Icons.location_on_outlined,
                  size: 12, color: AppColors.textHint),
              const SizedBox(width: 3),
              Expanded(
                child: Text(listing.locationLabel,
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('Πάτα για περισσότερα →',
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ),
    );
  }
}
