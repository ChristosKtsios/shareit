import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

      // ── Χρήστης (live από Firestore — όχι static από listing) ──
      // Φορτώνει την τρέχουσα φωτογραφία προφίλ και το όνομα του χρήστη,
      // ώστε αν αυτός τα άλλαξε αργότερα, να εμφανίζονται ενημερωμένα.
      StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(listing.userId)
            .snapshots(),
        builder: (context, snap) {
          // Fallback στα στατικά της αγγελίας αν δεν έχει φορτώσει ακόμα
          String firstName = listing.userFirstName;
          String lastName = '';
          String? avatarUrl = listing.userAvatarUrl;
          bool isVerified = false;

          if (snap.hasData && snap.data!.exists) {
            final d = snap.data!.data() as Map<String, dynamic>;
            firstName = (d['firstName'] as String?) ?? firstName;
            lastName = (d['lastName'] as String?) ?? '';
            avatarUrl = (d['avatarUrl'] as String?) ?? avatarUrl;
            isVerified = (d['isVerified'] as bool?) ?? false;
          }

          final fullName =
              lastName.isNotEmpty ? '$firstName $lastName' : firstName;
          final initials = '${firstName.isNotEmpty ? firstName[0] : ''}'
                  '${lastName.isNotEmpty ? lastName[0] : ''}'
              .toUpperCase();

          return GestureDetector(
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
                  initials: initials.isNotEmpty ? initials : '?',
                  avatarUrl: avatarUrl,
                  radius: 22,
                  showVerified: isVerified,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName.isNotEmpty ? fullName : 'common.userFallback'.tr(),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text('linfo.viewProfile'.tr(),
                          style: const TextStyle(
                              color: AppColors.primary, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary, size: 20),
              ]),
            ),
          );
        },
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
        text: 'linfo.postedAgo'
            .tr(namedArgs: {'t': DateHelpers.timeAgo(listing.createdAt)}),
        color: AppColors.textSecondary,
      ),

      // Ημερομηνία λήξης
      if (listing.availableUntil != null) ...[
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.event_outlined,
          text: 'linfo.availableUntil'.tr(namedArgs: {
            'd': '${listing.availableUntil!.day}/'
                '${listing.availableUntil!.month}/'
                '${listing.availableUntil!.year}'
          }),
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
        Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13))),
      ]);
}
