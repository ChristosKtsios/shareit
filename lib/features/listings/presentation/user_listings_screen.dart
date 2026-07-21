import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/listing_card.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../data/listing_model.dart';
import '../data/listing_repository.dart';

/// Οι αγγελίες ΕΝΟΣ χρήστη — το «ShareIt» κουτί του προφίλ.
///
/// Ιδιωτικότητα: σε κλειστό προφίλ βλέπουν μόνο οι φίλοι. Ο έλεγχος γίνεται
/// ΕΔΩ (όχι μόνο κρύβοντας το κουμπί στο προφίλ), ώστε να μην παρακάμπτεται
/// με απευθείας πλοήγηση στη διαδρομή.
///
/// ΣΗΜ.: οι αγγελίες είναι ούτως ή άλλως δημόσιες σε χάρτη/αναζήτηση — αυτό
/// εδώ είναι θέμα συνέπειας με το «Posts», όχι πραγματική απόκρυψη.
class UserListingsScreen extends StatelessWidget {
  final String uid;
  const UserListingsScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMe = currentUid != null && currentUid == uid;

    return Scaffold(
      appBar: AppBar(title: Text('ulist.title'.tr())),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, userSnap) {
          if (!userSnap.hasData) return const ShimmerList(count: 4);

          final data = userSnap.data!.data() as Map<String, dynamic>? ?? {};
          final isPrivate = data['isPrivateProfile'] as bool? ?? false;
          final friends = List<String>.from(data['friends'] ?? []);
          // Ίδιος κανόνας με τον τοίχο/posts στο προφίλ.
          final canSee = isMe || !isPrivate || friends.contains(currentUid);

          if (!canSee) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline,
                      color: AppColors.textHint, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'ulist.privateProfile'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                ]),
              ),
            );
          }

          // Ο κάτοχος βλέπει και τις παγωμένες του· οι άλλοι μόνο ενεργές.
          final stream = isMe
              ? ListingRepository().watchUserListings(uid)
              : ListingRepository().watchUserActiveListings(uid);

          return StreamBuilder<List<ListingModel>>(
            stream: stream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const ShimmerList(count: 4);
              }
              final listings = snap.data ?? [];
              if (listings.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'ulist.emptyTitle'.tr(),
                  subtitle: isMe ? 'ulist.emptyMine'.tr() : null,
                  actionLabel: isMe ? 'mylist.createListing'.tr() : null,
                  onAction: isMe ? () => context.push('/listing/new') : null,
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: listings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final l = listings[i];
                  return ListingCard(
                    listing: l,
                    onTap: () => context.push('/listing/${l.id}'),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
