import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/deal_model.dart';
import '../providers/deal_provider.dart';

class DealReviewScreen extends ConsumerStatefulWidget {
  final String dealId;
  const DealReviewScreen({super.key, required this.dealId});

  @override
  ConsumerState<DealReviewScreen> createState() => _DealReviewScreenState();
}

class _DealReviewScreenState extends ConsumerState<DealReviewScreen> {
  bool _processing = false;

  Future<void> _accept(DealModel deal, String myUid) async {
    setState(() => _processing = true);
    try {
      await ref.read(dealRepoProvider).acceptProposal(
            dealId: deal.id,
            userId: myUid,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('deals.agreed'.tr()),
            backgroundColor: AppColors.offer,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${'common.error'.tr()}: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject(DealModel deal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('deals.rejectProposalQ'.tr(),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('deals.willCancel'.tr(),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('deals.reject'.tr(),
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _processing = true);
    try {
      await ref.read(dealRepoProvider).cancel(deal.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('chatx.proposalRejected'.tr())));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${'common.error'.tr()}: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Ακύρωση από τον ΑΠΟΣΤΟΛΕΑ — μόνο όσο η πρόταση είναι pending.
  Future<void> _cancel(DealModel deal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('deals.cancelProposalQ'.tr(),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('deals.cancelProposalBody'.tr(),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('deals.back'.tr(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('deals.cancelProposal'.tr(),
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _processing = true);
    try {
      await ref.read(dealRepoProvider).cancel(deal.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('deals.proposalCancelled'.tr())));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${'common.error'.tr()}: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(currentUserProvider)?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: Text('msg.dealProposal'.tr())),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('deals')
            .doc(widget.dealId)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (!snap.data!.exists) {
            return Center(
                child: Text('deals.dealNotFound'.tr(),
                    style: const TextStyle(color: AppColors.textSecondary)));
          }
          final deal = DealModel.fromFirestore(snap.data!);
          final isMe = deal.user1Uid == myUid || deal.user2Uid == myUid;
          final isUser1 = deal.user1Uid == myUid;
          final myProposal = isUser1 ? deal.proposal1 : deal.proposal2;
          final otherProposal = isUser1 ? deal.proposal2 : deal.proposal1;
          DealProposal? displayProposal;
          if (myProposal != null && myProposal.title.isNotEmpty) {
            displayProposal = myProposal;
          } else if (otherProposal != null && otherProposal.title.isNotEmpty) {
            displayProposal = otherProposal;
          } else {
            displayProposal = myProposal ?? otherProposal;
          }
          if (displayProposal == null) {
            return Center(
                child: Text('deals.noProposalYet'.tr(),
                    style: const TextStyle(color: AppColors.textSecondary)));
          }
          final iAmSender = myProposal != null &&
              myProposal.accepted &&
              (otherProposal == null || !otherProposal.accepted);
          final iAmReceiver = otherProposal != null &&
              otherProposal.accepted &&
              (myProposal == null || !myProposal.accepted);
          final isActive = deal.status == DealStatus.active;
          final isCompleted = deal.status == DealStatus.completed;
          final isCancelled = deal.status == DealStatus.cancelled;
          final canAct =
              isMe && iAmReceiver && !isActive && !isCompleted && !isCancelled;
          // Ο αποστολέας μπορεί να ακυρώσει ΜΟΝΟ όσο εκκρεμεί (pending) —
          // δηλαδή πριν ο παραλήπτης αποδεχτεί (active) ή απορρίψει (cancelled).
          final canCancel =
              isMe && iAmSender && !isActive && !isCompleted && !isCancelled;
          return Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (isActive)
                    _StatusBanner(
                        icon: Icons.check_circle,
                        label: 'deals.activeDeal'.tr(),
                        color: AppColors.offer),
                  if (isCompleted)
                    _StatusBanner(
                        icon: Icons.task_alt,
                        label: 'deals.completed'.tr(),
                        color: AppColors.primary),
                  if (isCancelled)
                    _StatusBanner(
                        icon: Icons.cancel,
                        label: 'deals.cancelled'.tr(),
                        color: AppColors.danger),
                  if (isActive || isCompleted || isCancelled)
                    const SizedBox(height: 16),
                  Text('deals.title'.tr(),
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text(displayProposal.title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.3)),
                  const SizedBox(height: 20),
                  Text('deals.details'.tr(),
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(displayProposal.details,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            height: 1.5)),
                  ),
                  const SizedBox(height: 20),
                  _DateRow(
                      icon: Icons.event_available,
                      label: 'deals.start'.tr(),
                      value: _formatDateTime(displayProposal.startDate)),
                  const SizedBox(height: 10),
                  _DateRow(
                      icon: Icons.event_busy,
                      label: 'deals.end'.tr(),
                      value: _formatDateTime(displayProposal.endDate),
                      color: AppColors.deal),
                  if (iAmSender && !isActive && !isCompleted && !isCancelled)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.deal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.deal.withValues(alpha: 0.4),
                              width: 1),
                        ),
                        child: Row(children: [
                          const Icon(Icons.hourglass_top,
                              color: AppColors.deal, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('deals.sentWaiting'.tr(),
                                style: const TextStyle(
                                    color: AppColors.deal,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ),
                  if (isActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.offer.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle,
                              color: AppColors.offer, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('deals.bothAgreed'.tr(),
                                style: const TextStyle(
                                    color: AppColors.offer,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            if (canAct)
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                        top: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _processing ? null : () => _reject(deal),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                            minimumSize: const Size.fromHeight(48)),
                        child: Text('deals.rejectCaps'.tr(),
                            style: const TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _processing ? null : () => _accept(deal, myUid),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.offer,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48)),
                        child: _processing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text('deals.agreeCaps'.tr(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ),
            if (canCancel)
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                        top: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: OutlinedButton.icon(
                    onPressed: _processing ? null : () => _cancel(deal),
                    icon: _processing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.danger))
                        : const Icon(Icons.cancel_outlined,
                            color: AppColors.danger),
                    label: Text('deals.cancelProposalCaps'.tr(),
                        style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.danger),
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatusBanner(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1)),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _DateRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _DateRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: (color ?? AppColors.primary).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color ?? AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ]);
}
