import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../deals/data/deal_repository.dart';

class DealBottomSheet extends StatelessWidget {
  final String chatId;
  final String listingId;
  final String listingTitle;
  final String ownerUid;
  final String seekerUid;

  const DealBottomSheet({
    super.key,
    required this.chatId,
    required this.listingId,
    required this.listingTitle,
    required this.ownerUid,
    required this.seekerUid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Κλείσιμο Deal',
              style: TextStyle(color: AppColors.textPrimary,
                  fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Διάλεξε τη διάρκεια της ανταλλαγής:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 16),
          ...[
            ('1 μέρα',      const Duration(days: 1)),
            ('3 μέρες',     const Duration(days: 3)),
            ('1 εβδομάδα',  const Duration(days: 7)),
            ('2 εβδομάδες', const Duration(days: 14)),
          ].map((e) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.$1,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            trailing: const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
            onTap: () async {
              Navigator.pop(context);
              await DealRepository().create(
                chatId:       chatId,
                listingId:    listingId,
                listingTitle: listingTitle,
                user1Uid:     ownerUid,
                user2Uid:     seekerUid,
              );
            },
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}