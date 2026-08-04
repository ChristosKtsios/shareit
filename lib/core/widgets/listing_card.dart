import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../../features/listings/data/listing_model.dart';

class ListingCard extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback? onTap;

  final double? distanceKm;
  const ListingCard(
      {super.key, required this.listing, this.onTap, this.distanceKm});

  String _formatDateRange() {
    final from = listing.availableFrom;
    final until = listing.availableUntil;
    if (from == null && until == null) return '';

    String formatDate(DateTime d) => '${d.day}/${d.month}';
    String formatTime(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    final fromStr = from != null
        ? formatDate(from) + (listing.hasFromTime ? ' ${formatTime(from)}' : '')
        : null;
    final untilStr = until != null
        ? formatDate(until) +
            (listing.hasUntilTime ? ' ${formatTime(until)}' : '')
        : null;

    if (fromStr != null && untilStr != null) return '$fromStr → $untilStr';
    if (fromStr != null) return 'lcard.fromDate'.tr(namedArgs: {'d': fromStr});
    if (untilStr != null) {
      return 'lcard.untilDate'.tr(namedArgs: {'d': untilStr});
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isOffer = listing.type == ListingType.offer;
    final color = isOffer ? AppColors.offer : AppColors.seek;
    final label = isOffer ? 'map.offerLabel'.tr() : 'map.seekLabel'.tr();
    final dateRange = _formatDateRange();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _Tag(label: label, color: color),
              if (listing.tags.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text('#${listing.tags.first}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ),
              ],
              const Spacer(),
              if (dateRange.isNotEmpty)
                Flexible(
                  child: Text(dateRange,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 11)),
                ),
            ]),
            const SizedBox(height: 8),
            // Κείμενο αριστερά, φωτογραφίες ΔΕΞΙΑ (στο κενό της κάρτας).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(listing.title,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      _DescriptionWithMore(listing.description),
                      if (listing.tags.length > 1) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: listing.tags
                              .skip(1)
                              .take(4)
                              .map((t) => Text('#$t',
                                  style: const TextStyle(
                                      color: AppColors.textHint, fontSize: 11)))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                if (listing.imageUrls.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  _ListingPhotos(
                    urls: listing.imageUrls,
                    // Tap σε φωτο → ανοίγει ο viewer, ΜΕ την αγγελία από κάτω
                    // στη στοίβα: κλείσιμο (X) → λεπτομέρεια αγγελίας, πίσω →
                    // πάλι όλες οι αγγελίες.
                    onPhotoTap: (index) {
                      context.push('/listing/${listing.id}');
                      context.push('/listing/${listing.id}/images?i=$index',
                          extra: List<String>.from(listing.imageUrls));
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<DocumentSnapshot>(
              // Άμυνα: αν λείπει το userId (malformed/legacy αγγελία) μη καλέσεις
              // .doc('') (ρίχνει «document path must be non-empty») — ο builder
              // πέφτει στα local fallback πεδία (userFirstName/userAvatarUrl).
              stream: listing.userId.isEmpty
                  ? const Stream<DocumentSnapshot>.empty()
                  : FirebaseFirestore.instance
                      .collection('users')
                      .doc(listing.userId)
                      .snapshots(),
              builder: (context, snap) {
                String name = listing.userFirstName;
                String? avatar = listing.userAvatarUrl;
                double rating = 0;
                int ratingCount = 0;
                if (snap.hasData && snap.data!.exists) {
                  final d = snap.data!.data() as Map<String, dynamic>;
                  final first = (d['firstName'] as String?) ?? '';
                  final last = (d['lastName'] as String?) ?? '';
                  final full = '$first $last'.trim();
                  if (full.isNotEmpty) name = full;
                  avatar = (d['avatarUrl'] as String?) ?? avatar;
                  rating = (d['rating'] as num?)?.toDouble() ?? 0;
                  ratingCount = (d['ratingCount'] as num?)?.toInt() ?? 0;
                }
                return Row(children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    backgroundImage:
                        avatar != null ? NetworkImage(avatar) : null,
                    child: avatar == null
                        ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600))
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ),
                  if (distanceKm != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.location_on,
                        color: AppColors.textHint, size: 12),
                    Text(
                      distanceKm! < 1
                          ? '${(distanceKm! * 1000).toStringAsFixed(0)} ${'map.unitM'.tr()}'
                          : '${distanceKm!.toStringAsFixed(1)} ${'map.unitKm'.tr()}',
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                  if (ratingCount > 0) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.star, color: AppColors.deal, size: 12),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: AppColors.deal,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                    Text(' ($ratingCount)',
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 10)),
                  ],
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Περιγραφή αγγελίας (έως 2 γραμμές). Αν το κείμενο δεν χωράει, εμφανίζει
/// «Δείτε περισσότερα» — το πάτημα οπουδήποτε στην κάρτα ανοίγει την αγγελία.
class _DescriptionWithMore extends StatelessWidget {
  final String text;
  const _DescriptionWithMore(this.text);

  static const _style =
      TextStyle(color: AppColors.textSecondary, fontSize: 13);

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: _style),
        maxLines: 2,
        textDirection: Directionality.of(context),
      )..layout(maxWidth: constraints.maxWidth);
      final truncated = tp.didExceedMaxLines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: _style, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('lcard.seeMore'.tr(),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      );
    });
  }
}

/// Φωτογραφίες αγγελίας στη δεξιά πλευρά της κάρτας: έως 2 μικρογραφίες. Αν
/// υπάρχουν παραπάνω, η δεύτερη έχει σκούρο overlay με «+X» (X = οι υπόλοιπες).
class _ListingPhotos extends StatelessWidget {
  final List<String> urls;
  final void Function(int index) onPhotoTap;
  const _ListingPhotos({required this.urls, required this.onPhotoTap});

  static const double _size = 58;

  @override
  Widget build(BuildContext context) {
    final show = urls.take(2).toList();
    final extra = urls.length - show.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < show.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          GestureDetector(
            onTap: () => onPhotoTap(i),
            child: _thumb(show[i], showExtra: i == show.length - 1 ? extra : 0),
          ),
        ],
      ],
    );
  }

  Widget _thumb(String url, {required int showExtra}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          CachedNetworkImage(
            imageUrl: url,
            width: _size,
            height: _size,
            fit: BoxFit.cover,
            // Αποκωδικοποίηση στο μέγεθος που εμφανίζεται (όχι 1600px).
            memCacheWidth: 174,
            placeholder: (_, __) => Container(
                width: _size, height: _size, color: AppColors.surfaceVariant),
            errorWidget: (_, __, ___) => Container(
                width: _size,
                height: _size,
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.textHint, size: 20)),
          ),
          if (showExtra > 0)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: Text('+$showExtra',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}
