import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_helpers.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/listing_model.dart';

class ListingInfoWidget extends StatelessWidget {
  final ListingModel listing;
  const ListingInfoWidget({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 20),

      // Χρήστης — πατώντας πάει στο profile
      GestureDetector(
        onTap: () => context.push('/profile/${listing.userId}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(children: [
            UserAvatar(
              initials: listing.userFirstName.isNotEmpty
                  ? listing.userFirstName[0].toUpperCase() : '?',
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(listing.userFirstName,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Text('Δες το προφίλ',
                    style: TextStyle(
                        color: AppColors.primary, fontSize: 12)),
              ],
            )),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
          ]),
        ),
      ),
      const SizedBox(height: 12),

      // Τοποθεσία
      _InfoRow(
        icon: Icons.location_on_outlined,
        text: listing.locationLabel,
        color: AppColors.primary,
      ),
      const SizedBox(height: 8),

      // Ημερομηνία δημιουργίας
      _InfoRow(
        icon: Icons.access_time,
        text: 'Δημοσιεύτηκε ${DateHelpers.timeAgo(listing.createdAt)}',
        color: AppColors.textSecondary,
      ),

      // Ημερομηνία λήξης
      if (listing.availableUntil != null) ...[
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.event_outlined,
          text: 'Διαθέσιμο ως '
              '${listing.availableUntil!.day}/'
              '${listing.availableUntil!.month}/'
              '${listing.availableUntil!.year}',
          color: AppColors.deal,
        ),
      ],
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 8),
    Expanded(child: Text(text,
        style: TextStyle(color: color, fontSize: 13))),
  ]);
}