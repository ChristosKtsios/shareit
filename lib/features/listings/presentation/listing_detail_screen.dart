import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/location_permission_gate.dart';
import '../../../core/services/location_service.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/data/chat_repository.dart';
import '../data/listing_model.dart';
import '../data/listing_repository.dart';
import 'package:share_plus/share_plus.dart';
import '../../profile/data/user_repository.dart';

/// Live + autoDispose: το παλιό `FutureProvider.family` (χωρίς autoDispose)
/// κρατούσε την αγγελία cached για όλη τη ζωή της app, οπότε φωτογραφίες που
/// προστίθεντο αργότερα ΔΕΝ εμφανίζονταν εδώ (ενώ ο χάρτης, που είναι stream,
/// τις έδειχνε). Με stream + autoDispose τα δεδομένα είναι πάντα φρέσκα.
final _listingDetailProvider =
    StreamProvider.autoDispose.family<ListingModel?, String>(
        (ref, id) => ListingRepository().watchById(id));

/// Placeholder labels από παλιές αγγελίες που δεν έχουν πραγματική διεύθυνση.
const _placeholderLabels = {
  'Τρέχουσα τοποθεσία',
  'Επιλεγμένη τοποθεσία',
  'Δεν βρέθηκε τοποθεσία',
  '',
};

/// Reverse-geocode μιας αγγελίας κατά την προβολή, για να δείχνει σωστή περιοχή
/// ακόμα κι όταν έχει αποθηκευμένο placeholder label. Key: "lat,lng".
final _placeLabelProvider =
    FutureProvider.family<String?, String>((ref, latLng) async {
  final parts = latLng.split(',');
  return LocationService.reverseGeocode(
      double.parse(parts[0]), double.parse(parts[1]));
});

final _userPositionProvider = FutureProvider<Position?>((ref) async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    final perm = await LocationPermissionGate.ensure();
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
    if (meters < 1000) {
      return 'ld.metersAway'.tr(namedArgs: {'n': meters.toStringAsFixed(0)});
    }
    return 'ld.kmAway'.tr(namedArgs: {
      'n': (meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)
    });
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDateTime(DateTime dt, bool hasTime, String locale) {
    if (!hasTime) return DateFormat('d MMM yyyy', locale).format(dt);
    return DateFormat('d MMM yyyy, HH:mm', locale).format(dt);
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
        error: (_, __) => Center(
            child: Text(AppStrings.errorGeneric,
                style: const TextStyle(color: AppColors.textSecondary))),
        data: (listing) {
          if (listing == null) {
            return Center(
                child: Text('ld.notFound'.tr(),
                    style: const TextStyle(color: AppColors.textSecondary)));
          }

          final isOffer = listing.type == ListingType.offer;
          final badgeColor = isOffer ? AppColors.offer : AppColors.seek;
          final badgeLabel =
              isOffer ? 'ld.offerBadge'.tr() : 'ld.seekBadge'.tr();

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

          // Αν η αγγελία έχει placeholder label (παλιές αγγελίες), κάνε
          // reverse-geocoding από τις συντεταγμένες για πραγματική περιοχή.
          var placeLabel = listing.locationLabel;
          if (_placeholderLabels.contains(placeLabel.trim())) {
            final geocoded = ref
                .watch(_placeLabelProvider(
                    '${listing.location.latitude},${listing.location.longitude}'))
                .asData
                ?.value;
            if (geocoded != null && geocoded.isNotEmpty) {
              placeLabel = geocoded;
            } else if (placeLabel.trim().isEmpty) {
              placeLabel = 'ld.locationOnMap'.tr();
            }
          }

          return CustomScrollView(
            slivers: [
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
                    Text(listing.title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _openInMaps(listing.location.latitude,
                          listing.location.longitude),
                      child: Row(children: [
                        const Icon(Icons.location_on_outlined,
                            color: AppColors.primary, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            distMeters != null
                                ? '$placeLabel · ${_formatDistance(distMeters)}'
                                : placeLabel,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new,
                            color: AppColors.primary, size: 12),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _OwnerCard(listing: listing),
                    const SizedBox(height: 16),
                    Text('ld.descriptionLabel'.tr(),
                        style: const TextStyle(
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
                    if (listing.availableFrom != null ||
                        listing.availableUntil != null) ...[
                      Text('ld.availabilityLabel'.tr(),
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.deal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.deal.withValues(alpha: 0.3),
                              width: 0.5),
                        ),
                        child: Column(children: [
                          if (listing.availableFrom != null)
                            Row(children: [
                              const Icon(Icons.play_arrow,
                                  color: AppColors.deal, size: 16),
                              const SizedBox(width: 8),
                              Text('ld.fromColon'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _formatDateTime(listing.availableFrom!,
                                      listing.hasFromTime,
                                      context.locale.languageCode),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ]),
                          if (listing.availableFrom != null &&
                              listing.availableUntil != null)
                            const SizedBox(height: 8),
                          if (listing.availableUntil != null)
                            Row(children: [
                              const Icon(Icons.flag_outlined,
                                  color: AppColors.danger, size: 16),
                              const SizedBox(width: 8),
                              Text('ld.untilColon'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _formatDateTime(listing.availableUntil!,
                                      listing.hasUntilTime,
                                      context.locale.languageCode),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ]),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
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

class _HeroSection extends StatefulWidget {
  final ListingModel listing;
  final Color badgeColor;
  final String badgeLabel;
  const _HeroSection({
    required this.listing,
    required this.badgeColor,
    required this.badgeLabel,
  });

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  int _imageIndex = 0;
  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final badgeColor = widget.badgeColor;
    final badgeLabel = widget.badgeLabel;
    final hasImage = listing.imageUrls.isNotEmpty;
    return Stack(children: [
      SizedBox(
        width: double.infinity,
        height: 240,
        child: hasImage
            ? Stack(children: [
                PageView.builder(
                  itemCount: listing.imageUrls.length,
                  onPageChanged: (i) => setState(() => _imageIndex = i),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => context.push(
                        '/listing/${listing.id}/images?i=$i',
                        extra: List<String>.from(listing.imageUrls)),
                    child: CachedNetworkImage(
                      imageUrl: listing.imageUrls[i],
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          color: AppColors.surfaceVariant,
                          child: const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary, strokeWidth: 2))),
                      errorWidget: (_, __, ___) => const _GradientFallback(),
                    ),
                  ),
                ),
                if (listing.imageUrls.length > 1)
                  Positioned(
                    bottom: 14,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        listing.imageUrls.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _imageIndex ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _imageIndex
                                ? AppColors.primary
                                : Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (listing.imageUrls.length > 1)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.photo_library_outlined,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${_imageIndex + 1}/${listing.imageUrls.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ),
                  ),
              ])
            : const _GradientFallback(),
      ),
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
      Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        child: _CircleIconButton(
          icon: Icons.arrow_back,
          onTap: () => context.pop(),
        ),
      ),
      Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        right: 60,
        child: _SaveButton(listingId: listing.id),
      ),
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
                  leading:
                      const Icon(Icons.flag_outlined, color: AppColors.danger),
                  title: Text('ld.report'.tr(),
                      style: const TextStyle(color: AppColors.danger)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push(
                        '/report/listing/${listing.userId}/${listing.id}');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined,
                      color: AppColors.textSecondary),
                  title: Text('ld.share'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    final text =
                        '${listing.title}\n\n${listing.description}\n\n${'ld.onShareit'.tr()}';
                    SharePlus.instance.share(ShareParams(text: text));
                  },
                ),
              ]),
            );
          },
        ),
      ),
      Positioned(
        bottom: 12,
        right: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
        child: Icon(Icons.image_outlined, color: Colors.white54, size: 72),
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
        final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';

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
                        border: Border.all(color: AppColors.surface, width: 2),
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
                      const Icon(Icons.star, color: AppColors.deal, size: 13),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(1),
                          style: const TextStyle(
                              color: AppColors.deal,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Text('· $dealsCount deals',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
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

class _ActionButtons extends ConsumerWidget {
  final ListingModel listing;
  const _ActionButtons({required this.listing});

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('ld.deleteTitle'.tr(),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('ld.deleteBody'.tr(),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('common.delete'.tr(),
                  style: const TextStyle(color: AppColors.danger))),
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
            label: Text('profile.edit'.tr(),
                style: const TextStyle(color: AppColors.primary)),
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
            label: Text('common.delete'.tr(),
                style: const TextStyle(color: AppColors.danger)),
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
          onPressed:
              currentUid == null ? null : () => _startChat(context, currentUid),
          icon: const Icon(Icons.message_outlined,
              size: 18, color: AppColors.background),
          label: Text('ld.message'.tr(),
              style: const TextStyle(
                  color: AppColors.background, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        bool saved = false;
        if (snap.hasData && snap.data!.exists) {
          final ids = List<String>.from((snap.data!.data()
                  as Map<String, dynamic>?)?['savedListingIds'] ??
              []);
          saved = ids.contains(listingId);
        }
        return _CircleIconButton(
          icon: saved ? Icons.favorite : Icons.favorite_border,
          onTap: () async {
            await UserRepository().toggleSaved(uid, listingId, !saved);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text(saved ? 'ld.removedFav'.tr() : 'ld.savedFav'.tr()),
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
