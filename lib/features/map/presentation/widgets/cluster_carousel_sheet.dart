import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../listings/data/listing_model.dart';
import '../../providers/map_provider.dart';

class ClusterCarouselSheet extends ConsumerStatefulWidget {
  final List<ListingModel> listings;
  final int initialIndex;
  const ClusterCarouselSheet({
    super.key,
    required this.listings,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<ClusterCarouselSheet> createState() =>
      _ClusterCarouselSheetState();
}

class _ClusterCarouselSheetState extends ConsumerState<ClusterCarouselSheet> {
  late PageController _pageCtrl;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(
        initialPage: widget.initialIndex, viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _currentIndex = i);
    ref.read(mapProvider.notifier).setClusterIndex(i);
  }

  @override
  Widget build(BuildContext context) {
    final userPos = ref.watch(mapProvider).userPosition;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header με indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.listings.length}',
                    style: const TextStyle(
                      color: AppColors.background,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.swipe,
                    color: AppColors.textHint, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'mapx.swipeMore'.tr(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ]),
            ),
            // Carousel
            SizedBox(
              height: 400,
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: _onPageChanged,
                itemCount: widget.listings.length,
                itemBuilder: (_, i) {
                  final l = widget.listings[i];
                  final double? distMeters = userPos == null
                      ? null
                      : Geolocator.distanceBetween(
                          userPos.latitude,
                          userPos.longitude,
                          l.location.latitude,
                          l.location.longitude,
                        );
                  return _ListingCarouselCard(
                      listing: l, distanceMeters: distMeters);
                },
              ),
            ),
            // Dots indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.listings.length, (i) {
                  final active = i == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primary
                          : AppColors.textHint,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingCarouselCard extends StatelessWidget {
  final ListingModel listing;
  final double? distanceMeters;
  const _ListingCarouselCard({required this.listing, this.distanceMeters});

  String _formatDistance(double m) {
    if (m < 1000) return '${m.round()} ${'map.unitM'.tr()}';
    return '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} ${'map.unitKm'.tr()}';
  }

  @override
  Widget build(BuildContext context) {
    final isOffer = listing.type == ListingType.offer;
    final badgeColor = isOffer ? AppColors.offer : AppColors.seek;
    final badgeLabel = isOffer ? 'mapx.badgeOffer'.tr() : 'mapx.badgeSeek'.tr();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero image with badge
            Stack(children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: listing.imageUrls.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: listing.imageUrls.first,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _GradientFallback(isOffer: isOffer),
                          errorWidget: (_, __, ___) => _GradientFallback(isOffer: isOffer),
                        )
                      : _GradientFallback(isOffer: isOffer),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(badgeLabel,
                      style: const TextStyle(
                          color: AppColors.background,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                ),
              ),
              if (distanceMeters != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.near_me, size: 11, color: Colors.white),
                      const SizedBox(width: 3),
                      Text('${_formatDistance(distanceMeters!)} ${'map.away'.tr()}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ]),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                listing.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ),
            // Description (2 lines)
            if (listing.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Text(
                  listing.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.3),
                ),
              ),
            // User info from Firestore (rating + count)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(listing.userId)
                  .snapshots(),
              builder: (context, snap) {
                String name = listing.userFirstName;
                double rating = 0;
                int ratingCount = 0;
                String? avatar = listing.userAvatarUrl;
                if (snap.hasData && snap.data!.exists) {
                  final d = snap.data!.data() as Map<String, dynamic>;
                  name = (d['firstName'] as String?) ?? name;
                  rating = (d['rating'] as num?)?.toDouble() ?? 0;
                  ratingCount = (d['ratingCount'] as num?)?.toInt() ?? 0;
                  avatar = (d['avatarUrl'] as String?) ?? avatar;
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: AppColors.primary,
                      backgroundImage: avatar != null
                          ? CachedNetworkImageProvider(avatar)
                          : null,
                      child: avatar == null
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  color: AppColors.background,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700))
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.star, color: AppColors.deal, size: 12),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: AppColors.deal,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 3),
                    Text('($ratingCount)',
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 10)),
                  ]),
                );
              },
            ),
            // CTA Button
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/listing/${listing.id}');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('mapx.seeMore'.tr(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _GradientFallback extends StatelessWidget {
  final bool isOffer;
  const _GradientFallback({required this.isOffer});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isOffer
              ? [AppColors.offer, AppColors.primary]
              : [AppColors.seek, AppColors.primary],
        ),
      ),
      child: Icon(
        isOffer
            ? Icons.local_offer_outlined
            : Icons.help_outline,
        color: Colors.white.withValues(alpha: 0.7),
        size: 36,
      ),
    );
  }
}
