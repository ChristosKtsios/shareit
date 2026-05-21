import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../data/listing_model.dart';
import '../../data/listing_repository.dart';

class ListingActionsWidget extends ConsumerWidget {
  final ListingModel listing;
  const ListingActionsWidget({super.key, required this.listing});

  Future<void> _startChat(
      BuildContext context, String currentUid) async {
    final db = FirebaseFirestore.instance;
    final existing = await db.collection('chats')
        .where('listingId', isEqualTo: listing.id)
        .where('participants', arrayContains: currentUid)
        .limit(1).get();

    String chatId;
    if (existing.docs.isNotEmpty) {
      chatId = existing.docs.first.id;
    } else {
      final doc = await db.collection('chats').add({
        'listingId':    listing.id,
        'listingTitle': listing.title,
        'participants': [currentUid, listing.userId],
        'otherUserName': listing.userFirstName,
        'lastMessage':  '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unread': false,
      });
      chatId = doc.id;
    }
    if (context.mounted) context.push('/chat/$chatId');
  }

  Future<void> _deleteListing(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Διαγραφή αγγελίας',
            style: TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w700)),
        content: const Text('Είσαι σίγουρος;',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Άκυρο')),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid;
    final isOwner    = listing.userId == currentUid;

    if (isOwner) {
      return Column(children: [
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => _deleteListing(context),
          icon: const Icon(Icons.delete_outline,
              size: 18, color: AppColors.danger),
          label: const Text('Διαγραφή αγγελίας',
              style: TextStyle(color: AppColors.danger)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.danger),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ]);
    }

    // Άλλος χρήστης — Chat + Profile
    return Column(children: [
      const SizedBox(height: 28),

      // Στείλε μήνυμα
      ElevatedButton.icon(
        onPressed: currentUid == null
            ? null
            : () => _startChat(context, currentUid),
        icon: const Icon(Icons.chat_bubble_outline, size: 18),
        label: const Text('Στείλε μήνυμα'),
      ),
      const SizedBox(height: 12),

      // Δες προφίλ
      OutlinedButton.icon(
        onPressed: () => context.push('/profile/${listing.userId}'),
        icon: const Icon(Icons.person_outline,
            size: 18, color: AppColors.primary),
        label: const Text('Δες το προφίλ',
            style: TextStyle(color: AppColors.primary)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ]);
  }
}