import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_helpers.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../data/deal_model.dart';
import '../../providers/deal_provider.dart';

class DealProposalCard extends ConsumerWidget {
  final DealModel deal;

  const DealProposalCard({super.key, required this.deal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProvider)?.uid ?? '';
    final isUser1 = deal.user1Uid == currentUid;
    final myProposal = isUser1 ? deal.proposal1 : deal.proposal2;
    final otherProposal = isUser1 ? deal.proposal2 : deal.proposal1;
    final otherUid = isUser1 ? deal.user2Uid : deal.user1Uid;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.deal.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.deal.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Icon(Icons.handshake_outlined,
                color: AppColors.deal, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(deal.listingTitle,
                    style: const TextStyle(
                        color: AppColors.deal,
                        fontSize: 14,
                        fontWeight: FontWeight.w600))),
            _StatusBadge(deal: deal),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (myProposal != null) ...[
                Text('dcard.yourProposal'.tr(),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                _ProposalDetails(proposal: myProposal),
                const SizedBox(height: 12),
              ],
              if (otherProposal != null) ...[
                Text('dcard.otherProposal'.tr(),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                _ProposalDetails(proposal: otherProposal),
                const SizedBox(height: 12),
              ],
              if (deal.status == DealStatus.pending) ...[
                if (otherProposal != null && myProposal?.accepted != true) ...[
                  ElevatedButton(
                    onPressed: () async {
                      await ref.read(dealRepoProvider).acceptProposal(
                            dealId: deal.id,
                            userId: currentUid,
                          );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deal,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: Text('dcard.agree'.tr()),
                  ),
                  const SizedBox(height: 8),
                ],
                if (myProposal == null)
                  OutlinedButton(
                    onPressed: () {
                      context.push(
                        '/deal-proposal/${deal.chatId}'
                        '?listingId=${deal.listingId}'
                        '&listingTitle=${Uri.encodeComponent(deal.listingTitle)}'
                        '&otherUserUid=$otherUid'
                        '&dealId=${deal.id}',
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('dcard.sendYourProposal'.tr(),
                        style: const TextStyle(color: AppColors.primary)),
                  ),
                if (myProposal != null && otherProposal == null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.textHint, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'dcard.waitOther'.tr(),
                          style: const TextStyle(
                              color: AppColors.textHint, fontSize: 11),
                        ),
                      ),
                    ]),
                  ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

class _ProposalDetails extends StatelessWidget {
  final DealProposal proposal;
  const _ProposalDetails({required this.proposal});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Row(
            icon: Icons.label_outline,
            text: proposal.title,
            bold: true,
          ),
          const SizedBox(height: 4),
          if (proposal.details.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                proposal.details,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              ),
            ),
          ],
          _Row(
            icon: Icons.event_available,
            text: 'dcard.startAt'.tr(namedArgs: {
              'v': '${DateHelpers.formatDate(proposal.startDate)} '
                  '${proposal.startDate.hour.toString().padLeft(2, '0')}:'
                  '${proposal.startDate.minute.toString().padLeft(2, '0')}'
            }),
          ),
          const SizedBox(height: 2),
          _Row(
            icon: Icons.event_busy,
            text: 'dcard.endAt'.tr(namedArgs: {
              'v': '${DateHelpers.formatDate(proposal.endDate)} '
                  '${proposal.endDate.hour.toString().padLeft(2, '0')}:'
                  '${proposal.endDate.minute.toString().padLeft(2, '0')}'
            }),
          ),
          if (proposal.accepted) ...[
            const SizedBox(height: 4),
            _Row(
              icon: Icons.check_circle_outline,
              text: 'dcard.accepted'.tr(),
              color: AppColors.offer,
            ),
          ],
        ]),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool bold;
  const _Row({
    required this.icon,
    required this.text,
    this.color = AppColors.textSecondary,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.normal))),
        ]),
      );
}

class _StatusBadge extends StatelessWidget {
  final DealModel deal;
  const _StatusBadge({required this.deal});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (deal.status) {
      case DealStatus.pending:
        color = AppColors.deal;
        label = 'chatx.statusPending'.tr();
        break;
      case DealStatus.accepted:
        color = AppColors.offer;
        label = 'dcard.statusAccepted'.tr();
        break;
      case DealStatus.active:
        color = AppColors.offer;
        label = 'chatx.statusActive'.tr();
        break;
      case DealStatus.completed:
        color = AppColors.primary;
        label = 'deal.done'.tr();
        break;
      case DealStatus.cancelled:
        color = AppColors.danger;
        label = 'deals.cancelled'.tr();
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
