import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../deals/data/deal_repository.dart';
import '../../providers/chat_provider.dart';

class ChatDealBottomSheet extends ConsumerWidget {
  final String chatId;
  final String listingId;
  final String listingTitle;
  final String ownerUid;
  final String seekerUid;

  const ChatDealBottomSheet({
    super.key,
    required this.chatId,
    required this.listingId,
    required this.listingTitle,
    required this.ownerUid,
    required this.seekerUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durations = [
      ('dealsheet.day1'.tr(),   const Duration(days: 1)),
      ('dealsheet.days3'.tr(),  const Duration(days: 3)),
      ('dealsheet.week1'.tr(),  const Duration(days: 7)),
      ('dealsheet.weeks2'.tr(), const Duration(days: 14)),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 20),
          Text('deal.close'.tr(),
              style: const TextStyle(color: AppColors.textPrimary,
                  fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('dealsheet.chooseDuration'.tr(),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 16),
          ...durations.map((e) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.deal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.timer_outlined,
                  color: AppColors.deal, size: 20),
            ),
            title: Text(e.$1,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            trailing: const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
            onTap: () async {
              Navigator.pop(context);
              final uid = ref.read(currentUserProvider)?.uid ?? '';
              await DealRepository().create(
                chatId:       chatId,
                listingId:    listingId,
                listingTitle: listingTitle,
                user1Uid:     ownerUid,
                user2Uid:     seekerUid,
              );
              await ref.read(chatRepoProvider).sendDealClosedMessage(
                chatId:   chatId,
                senderId: uid,
                durationDays: e.$2.inDays,
              );
            },
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}