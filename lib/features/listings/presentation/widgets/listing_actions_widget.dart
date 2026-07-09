import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../data/listing_model.dart';
import '../../data/listing_repository.dart';
import '../../../chat/data/chat_repository.dart';

class ListingActionsWidget extends ConsumerWidget {
  final ListingModel listing;
  const ListingActionsWidget({super.key, required this.listing});

  Future<void> _startChat(BuildContext context, String currentUid) async {
    final chatId = await ChatRepository().getOrCreate(
      currentUid: currentUid,
      otherUid: listing.userId,
      listingId: listing.id,
      listingTitle: listing.title,
      otherUserName: listing.userFirstName,
    );
    if (context.mounted) context.push('/chat/$chatId');
  }

  Future<void> _deleteListing(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('ld.deleteTitle'.tr(),
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('lact.deleteConfirmBody'.tr(),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('common.cancel'.tr())),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid;
    final isOwner = listing.userId == currentUid;

    if (isOwner) {
      return Column(children: [
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => _deleteListing(context),
          icon: const Icon(Icons.delete_outline,
              size: 18, color: AppColors.danger),
          label: Text('ld.deleteTitle'.tr(),
              style: const TextStyle(color: AppColors.danger)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.danger),
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ]);
    }

    // Άλλος χρήστης — Chat + Profile
    return Column(children: [
      const SizedBox(height: 28),

      // Στείλε μήνυμα
      ElevatedButton.icon(
        onPressed:
            currentUid == null ? null : () => _startChat(context, currentUid),
        icon: const Icon(Icons.chat_bubble_outline, size: 18),
        label: Text('lact.sendMessage'.tr()),
      ),
      const SizedBox(height: 12),

      // Δες προφίλ
      OutlinedButton.icon(
        onPressed: () => context.push('/profile/${listing.userId}'),
        icon: const Icon(Icons.person_outline,
            size: 18, color: AppColors.primary),
        label: Text('lact.viewProfile'.tr(),
            style: const TextStyle(color: AppColors.primary)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(double.infinity, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ]);
  }
}
