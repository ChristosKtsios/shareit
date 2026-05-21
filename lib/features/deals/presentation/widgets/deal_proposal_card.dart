import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final isUser1    = deal.user1Uid == currentUid;
    final myProposal = isUser1 ? deal.proposal1 : deal.proposal2;
    final otherProposal = isUser1 ? deal.proposal2 : deal.proposal1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.deal.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.deal.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Icon(Icons.handshake_outlined,
                color: AppColors.deal, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(deal.listingTitle,
                style: const TextStyle(
                    color: AppColors.deal,
                    fontSize: 14,
                    fontWeight: FontWeight.w600))),
            _StatusBadge(deal: deal, currentUid: currentUid),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Η πρότασή μου
              if (myProposal != null) ...[
                const Text('Η πρότασή σου:',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                _ProposalDetails(proposal: myProposal),
                const SizedBox(height: 12),
              ],

              // Πρόταση άλλου χρήστη
              if (otherProposal != null) ...[
                const Text('Πρόταση άλλου χρήστη:',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                _ProposalDetails(proposal: otherProposal),
                const SizedBox(height: 12),
              ],

              // Κουμπιά
              if (deal.status == DealStatus.pending) ...[
                // Αν ο άλλος έχει στείλει πρόταση και εγώ δεν έχω αποδεχτεί
                if (otherProposal != null &&
                    myProposal?.accepted != true)
                  ElevatedButton(
                    onPressed: () async {
                      await ref.read(dealRepoProvider)
                          .acceptProposal(
                            dealId: deal.id,
                            userId: currentUid,
                          );
                    },
                    child: const Text('Αποδοχή πρότασης'),
                  ),

                // Αν δεν έχω στείλει πρόταση ακόμα
                if (myProposal == null)
                  OutlinedButton(
                    onPressed: () {
                      // Navigate to proposal screen
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Στείλε την πρότασή σου',
                        style: TextStyle(color: AppColors.primary)),
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
      _Row(icon: Icons.info_outline,     text: proposal.reason),
      _Row(icon: Icons.arrow_upward,     text: 'Δίνει: ${proposal.iGive}'),
      _Row(icon: Icons.arrow_downward,   text: 'Παίρνει: ${proposal.iReceive}'),
      _Row(icon: Icons.schedule,
          text: 'Παράδοση: ${DateHelpers.formatDate(proposal.deliveryAt)} '
              '${proposal.deliveryAt.hour.toString().padLeft(2, '0')}:'
              '${proposal.deliveryAt.minute.toString().padLeft(2, '0')}'),
      if (proposal.withPayment && proposal.amount != null)
        _Row(icon: Icons.euro,
            text: 'Με πληρωμή: ${proposal.amount!.toStringAsFixed(2)}€'),
      if (proposal.accepted)
        const _Row(icon: Icons.check_circle_outline,
            text: 'Αποδεκτή', color: AppColors.offer),
    ]),
  );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Row({
    required this.icon,
    required this.text,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text,
          style: TextStyle(color: color, fontSize: 12))),
    ]),
  );
}

class _StatusBadge extends StatelessWidget {
  final DealModel deal;
  final String currentUid;
  const _StatusBadge({required this.deal, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (deal.status) {
      case DealStatus.pending:
        color = AppColors.deal;
        label = 'Εκκρεμεί';
        break;
      case DealStatus.active:
        color = AppColors.offer;
        label = 'Ενεργό';
        break;
      case DealStatus.completed:
        color = AppColors.primary;
        label = 'Ολοκληρώθηκε';
        break;
      case DealStatus.cancelled:
        color = AppColors.danger;
        label = 'Ακυρώθηκε';
        break;
      default:
        color = AppColors.textSecondary;
        label = '';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}