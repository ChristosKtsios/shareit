import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/shimmer_loader.dart';
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/data/chat_repository.dart';
import '../data/listing_model.dart';
import '../data/listing_repository.dart';
import '../../profile/data/user_repository.dart';

final _listingDetailProvider =
    FutureProvider.family<ListingModel?, String>((ref, id) =>
        ListingRepository().getListingById(id));

final _userPositionProvider = FutureProvider<Position?>((ref) async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.medium));
  } catch (_) {
    return null;
  }
});

class ListingDetailScreen extends ConsumerWidget {
  final String listingId;
  const ListingDetailScreen({super.key, required this.listingId});

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} μ. μακριά';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} χλμ μακριά';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingAsync = ref.watch(_listingDetailProvider(listingId));
    final userPosAsync = ref.watch(_userPositionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: listingAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(
            child: Text(AppStrings.errorGeneric,
                style: TextStyle(color: AppColors.textSecondary))),
        data: (listing) {
          if (listing == null) {
            return const Center(
                child: Text('Η αγγελία δεν βρέθηκε.',
                    style: TextStyle(color: AppColors.textSecondary)));
          }

          final isOffer = listing.type == ListingType.offer;
          final badgeColor = isOffer ? AppColors.offer : AppColors.seek;
          final badgeLabel = isOffer ? 'ΠΡΟΣΦΟΡΑ' : 'ΖΗΤΩ';

          double? distMeters;
          final userPos = userPosAsync.asData?.value;
          if (userPos != null) {
            distMeters = Geolocator.distanceBetween(
              userPos.latitude,
              userPos.longitude,
              listing.location.latitude,
              listing.location.longitude,
            );
          }

          return CustomScrollView(
            slivers: [
              // ── Hero Image + Floating buttons ──
              SliverToBoxAdapter(
                child: _HeroSection(
                  listing: listing,
                  badgeColor: badgeColor,
                  badgeLabel: badgeLabel,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Title
                    Text(listing.title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          color: AppColors.textSecondary, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          distMeters != null
                              ? '${listing.locationLabel} · ${_formatDistance(distMeters)}'
                              : listing.locationLabel,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // Owner card
                    _OwnerCard(listing: listing),
                    const SizedBox(height: 16),

                    // Description
                    const Text('ΠΕΡΙΓΡΑΦΗ',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 6),
                    Text(listing.description,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            height: 1.5)),
                    const SizedBox(height: 16),

                    // Tags
                    if (listing.tags.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: listing.tags
                            .map((t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.12),
                                    border: Border.all(
                                        color: AppColors.primary, width: 0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('#$t',
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11)),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Action buttons
                    _ActionButtons(listing: listing),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── HERO SECTION ──
class _HeroSection extends StatelessWidget {
  final ListingModel listing;
  final Color badgeColor;
  final String badgeLabel;
  const _HeroSection({
    required this.listing,
    required this.badgeColor,
    required this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = listing.imageUrls.isNotEmpty;
    return Stack(children: [
      // Image or gradient
      GestureDetector(
        onTap: hasImage
            ? () => context.push('/listing/${listing.id}/images',
                extra: listing.imageUrls)
            : null,
        child: SizedBox(
          width: double.infinity,
          height: 240,
          child: hasImage
              ? CachedNetworkImage(
                  imageUrl: listing.imageUrls.first,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2))),
                  errorWidget: (_, __, ___) => const _GradientFallback(),
                )
              : const _GradientFallback(),
        ),
      ),
      // Dark overlay για να φαίνεται το κουμπί καλύτερα
      Positioned.fill(
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.25),
                ],
                stops: const [0, 0.4, 1],
              ),
            ),
          ),
        ),
      ),
      // Back button
      Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        child: _CircleIconButton(
          icon: Icons.arrow_back,
          onTap: () => context.pop(),
        ),
      ),
      // Heart button (save/unsave)
      Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        right: 60,
        child: _SaveButton(listingId: listing.id),
      ),
      // More options button (report)
      Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        right: 12,
        child: _CircleIconButton(
          icon: Icons.more_vert,
          onTap: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: AppColors.surface,
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  leading: const Icon(Icons.flag_outlined,
                      color: AppColors.danger),
                  title: const Text('Αναφορά αγγελίας',
                      style: TextStyle(color: AppColors.danger)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push(
                        '/report/listing/${listing.userId}/${listing.id}');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined,
                      color: AppColors.textSecondary),
                  title: const Text('Κοινοποίηση',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Σύντομα: κοινοποίηση')),
                    );
                  },
                ),
              ]),
            );
          },
        ),
      ),
      // Badge
      Positioned(
        bottom: 12,
        right: 12,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(badgeLabel,
              style: const TextStyle(
                  color: AppColors.background,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ),
      ),
      // Image count if multiple
      if (listing.imageUrls.length > 1)
        Positioned(
          bottom: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.collections, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text('${listing.imageUrls.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
    ]);
  }
}

class _GradientFallback extends StatelessWidget {
  const _GradientFallback();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            Color(0xFFF97316),
            AppColors.deal,
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined,
            color: Colors.white54, size: 72),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ── OWNER CARD ──
class _OwnerCard extends StatelessWidget {
  final ListingModel listing;
  const _OwnerCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(listing.userId)
          .snapshots(),
      builder: (context, snap) {
        String firstName = listing.userFirstName;
        String lastName = '';
        String? avatarUrl = listing.userAvatarUrl;
        double rating = 0;
        int dealsCount = 0;
        bool isOnline = false;
        bool showOnline = true;

        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          firstName = (d['firstName'] as String?) ?? firstName;
          lastName = (d['lastName'] as String?) ?? '';
          avatarUrl = (d['avatarUrl'] as String?) ?? avatarUrl;
          rating = (d['rating'] as num?)?.toDouble() ?? 0;
          dealsCount = (d['dealsCount'] as num?)?.toInt() ?? 0;
          showOnline = d['showOnlineStatus'] ?? true;
          final lastSeen = (d['lastSeen'] as Timestamp?)?.toDate();
          if (showOnline && lastSeen != null) {
            isOnline = DateTime.now().difference(lastSeen).inMinutes < 5;
          }
        }

        final fullName =
            lastName.isNotEmpty ? '$firstName $lastName' : firstName;
        final initial =
            firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';

        return GestureDetector(
          onTap: () => context.push('/profile/${listing.userId}'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Row(children: [
              Stack(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary,
                  backgroundImage: avatarUrl != null
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl == null
                      ? Text(initial,
                          style: const TextStyle(
                              color: AppColors.background,
                              fontWeight: FontWeight.w700))
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.surface, width: 2),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName.isNotEmpty ? fullName : 'Χρήστης',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.star,
                          color: AppColors.deal, size: 13),
                      const SizedBox(width: 3),
                      Text('${rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                              color: AppColors.deal,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Text('· $dealsCount deals',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11)),
                    ]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 18),
            ]),
          ),
        );
      },
    );
  }
}

// ── ACTION BUTTONS ──
class _ActionButtons extends ConsumerWidget {
  final ListingModel listing;
  const _ActionButtons({required this.listing});

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Διαγραφή αγγελίας',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Η αγγελία θα διαγραφεί οριστικά.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Άκυρο',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Διαγραφή',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm != true) return;
    await ListingRepository().deleteListing(listing.id);
    if (context.mounted) context.pop();
  }

  Future<void> _startChat(BuildContext context, String uid) async {
    final chatId = await ChatRepository().getOrCreate(
      currentUid: uid,
      otherUid: listing.userId,
      listingId: listing.id,
      listingTitle: listing.title,
      otherUserName: listing.userFirstName,
    );
    if (context.mounted) context.push('/chat/$chatId');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid;
    final isOwner = listing.userId == currentUid;

    if (isOwner) {
      return Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.push('/edit-listing/${listing.id}'),
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: AppColors.primary),
            label: const Text('Επεξεργασία',
                style: TextStyle(color: AppColors.primary)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.danger),
            label: const Text('Διαγραφή',
                style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.danger),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]);
    }

    return Row(children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: currentUid == null
              ? null
              : () => _startChat(context, currentUid),
          icon: const Icon(Icons.message_outlined,
              size: 18, color: AppColors.background),
          label: const Text('Μήνυμα',
              style: TextStyle(
                  color: AppColors.background,
                  fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    ]);
  }
}


class _SaveButton extends ConsumerWidget {
  final String listingId;
  const _SaveButton({required this.listingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        bool saved = false;
        if (snap.hasData && snap.data!.exists) {
          final ids = List<String>.from(
              (snap.data!.data() as Map<String, dynamic>?)?['savedListingIds'] ?? []);
          saved = ids.contains(listingId);
        }
        return _CircleIconButton(
          icon: saved ? Icons.favorite : Icons.favorite_border,
          onTap: () async {
            await UserRepository().toggleSaved(uid, listingId, !saved);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(saved
                      ? 'Αφαιρέθηκε από τα αγαπημένα'
                      : 'Αποθηκεύτηκε στα αγαπημένα'),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          },
        );
      },
    );
  }
}
