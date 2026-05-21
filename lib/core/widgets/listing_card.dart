import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../../features/listings/data/listing_model.dart';

class ListingCard extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback? onTap;

  const ListingCard({super.key, required this.listing, this.onTap});

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
    if (fromStr != null) return 'από $fromStr';
    if (untilStr != null) return 'ως $untilStr';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isOffer = listing.type == ListingType.offer;
    final color = isOffer ? AppColors.offer : AppColors.seek;
    final label = isOffer ? '🤲 Προσφέρω' : '🔍 Αναζητώ';
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
            Text(listing.title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(listing.description,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
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
            if (listing.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: listing.imageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(listing.imageUrls[i],
                            width: 60, height: 60, fit: BoxFit.cover)),
                  )),
            ],
            const SizedBox(height: 10),
            Row(children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage: listing.userAvatarUrl != null
                    ? NetworkImage(listing.userAvatarUrl!)
                    : null,
                child: listing.userAvatarUrl == null
                    ? Text(
                        listing.userFirstName.isNotEmpty
                            ? listing.userFirstName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600))
                    : null,
              ),
              const SizedBox(width: 6),
              Text(listing.userFirstName,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ]),
          ],
        ),
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
