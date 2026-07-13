import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../listings/data/listing_model.dart';
import '../../providers/map_provider.dart';

class MapListingCard extends ConsumerWidget {
  final ListingModel listing;
  final VoidCallback onClose;

  const MapListingCard({
    super.key,
    required this.listing,
    required this.onClose,
  });

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} ${'map.unitM'.tr()}';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} ${'map.unitKm'.tr()}';
  }

  String _formatDateTime(DateTime dt, bool hasTime, String locale) {
    if (!hasTime) return DateFormat('d MMM', locale).format(dt);
    return DateFormat('d MMM, HH:mm', locale).format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffer = listing.type == ListingType.offer;
    final color = isOffer ? AppColors.offer : AppColors.seek;
    final label = isOffer ? 'map.offerLabel'.tr() : 'map.seekLabel'.tr();
    final locale = context.locale.languageCode;
    final hasAvailability =
        listing.availableFrom != null || listing.availableUntil != null;

    // Απόσταση από την τρέχουσα θέση του χρήστη (αν υπάρχει).
    final userPos = ref.watch(mapProvider).userPosition;
    final double? distMeters = userPos == null
        ? null
        : Geolocator.distanceBetween(
            userPos.latitude,
            userPos.longitude,
            listing.location.latitude,
            listing.location.longitude,
          );

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
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(listing.userId)
                  .snapshots(),
              builder: (context, snap) {
                String displayName = listing.userFirstName.isNotEmpty
                    ? listing.userFirstName
                    : 'common.userFallback'.tr();
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

            Text(listing.title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),

            if (listing.description.isNotEmpty) ...[
              Text(listing.description,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
            ],

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

            // ΝΕΟ: Διαθεσιμότητα με ώρες
            if (hasAvailability) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.deal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.deal.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (listing.availableFrom != null)
                      Row(children: [
                        const Icon(Icons.play_arrow,
                            color: AppColors.deal, size: 12),
                        const SizedBox(width: 4),
                        Text('map.fromColon'.tr(),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Text(
                            _formatDateTime(listing.availableFrom!,
                                listing.hasFromTime, locale),
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    if (listing.availableFrom != null &&
                        listing.availableUntil != null)
                      const SizedBox(height: 3),
                    if (listing.availableUntil != null)
                      Row(children: [
                        const Icon(Icons.flag_outlined,
                            color: AppColors.danger, size: 12),
                        const SizedBox(width: 4),
                        Text('map.untilColon'.tr(),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Text(
                            _formatDateTime(listing.availableUntil!,
                                listing.hasUntilTime, locale),
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                  ],
                ),
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
              if (distMeters != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.near_me,
                        size: 11, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Text('${_formatDistance(distMeters)} ${'map.away'.tr()}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
              const SizedBox(width: 8),
              Text('map.tapMore'.tr(),
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ),
    );
  }
}
