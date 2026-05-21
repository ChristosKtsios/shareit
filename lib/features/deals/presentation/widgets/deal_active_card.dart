import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_helpers.dart';
import '../../data/deal_model.dart';
import '../../providers/deal_provider.dart';

class DealActiveCard extends ConsumerStatefulWidget {
  final DealModel deal;
  const DealActiveCard({super.key, required this.deal});
  @override
  ConsumerState<DealActiveCard> createState() => _DealActiveCardState();
}

class _DealActiveCardState extends ConsumerState<DealActiveCard> {
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.deal.remaining;
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _remaining = widget.deal.remaining);
      if (!_remaining.isNegative) _tick();
    });
  }

  Future<void> _complete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Ολοκλήρωση Deal',
            style: TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w700)),
        content: const Text(
            'Επιβεβαιώνεις ότι η ανταλλαγή ολοκληρώθηκε;',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Όχι')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ναι, ολοκληρώθηκε',
                style: TextStyle(color: AppColors.offer))),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(dealRepoProvider).complete(widget.deal.id);
    if (mounted) context.push('/rate-deal/${widget.deal.id}');
  }

  @override
  Widget build(BuildContext context) {
    final expired    = _remaining.isNegative;
    final color      = expired ? AppColors.danger : AppColors.offer;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(children: [

        // Header με timer
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16)),
          ),
          child: Row(children: [
            Icon(
              expired
                  ? Icons.check_circle_outline
                  : Icons.handshake_outlined,
              color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.deal.listingTitle,
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600))),
            // Timer
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                expired
                    ? 'Έληξε'
                    : DateHelpers.formatTimer(_remaining),
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [
                      FontFeature.tabularFigures()
                    ]),
              ),
            ),
          ]),
        ),

        // Details
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Ημερομηνία παράδοσης
              if (widget.deal.deliveryAt != null)
                _InfoRow(
                  icon: Icons.event_outlined,
                  text: 'Παράδοση: '
                      '${DateHelpers.formatDate(widget.deal.deliveryAt!)} '
                      '${widget.deal.deliveryAt!.hour.toString().padLeft(2, '0')}:'
                      '${widget.deal.deliveryAt!.minute.toString().padLeft(2, '0')}',
                  color: color,
                ),
              const SizedBox(height: 12),

              // Κουμπιά
              Row(children: [

                // Chat button
                Expanded(child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/chat/${widget.deal.chatId}'),
                  icon: const Icon(Icons.chat_bubble_outline,
                      size: 16, color: AppColors.primary),
                  label: const Text('Συνομιλία',
                      style: TextStyle(color: AppColors.primary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
                const SizedBox(width: 10),

                // Complete button
                Expanded(child: ElevatedButton.icon(
                  onPressed: _complete,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Ολοκλήρωση'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: color),
    const SizedBox(width: 6),
    Expanded(child: Text(text,
        style: TextStyle(color: color, fontSize: 12))),
  ]);
}