import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_helpers.dart';
import '../../data/deal_model.dart';

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

  @override
  Widget build(BuildContext context) {
    final expired = _remaining.isNegative;
    final isCompleted = widget.deal.status == DealStatus.completed;
    final color =
        (expired || isCompleted) ? AppColors.primary : AppColors.offer;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Icon(
                isCompleted
                    ? Icons.check_circle
                    : expired
                        ? Icons.timer_off
                        : Icons.handshake_outlined,
                color: color,
                size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(widget.deal.displayTitle,
                    style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isCompleted
                    ? 'deal.done'.tr()
                    : expired
                        ? 'dcard.processing'.tr()
                        : DateHelpers.formatTimer(_remaining),
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.deal.displayDetails.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    widget.deal.displayDetails,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (widget.deal.endDate != null)
                _InfoRow(
                  icon: Icons.event_outlined,
                  text: 'dcard.endAt'.tr(namedArgs: {
                    'v': '${DateHelpers.formatDate(widget.deal.endDate!)} '
                        '${widget.deal.endDate!.hour.toString().padLeft(2, '0')}:'
                        '${widget.deal.endDate!.minute.toString().padLeft(2, '0')}'
                  }),
                  color: color,
                ),
              if (expired && !isCompleted) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.textHint, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'dcard.autoComplete'.tr(),
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 11),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                  onPressed: () => context.push('/chat/${widget.deal.chatId}'),
                  icon: const Icon(Icons.chat_bubble_outline,
                      size: 16, color: AppColors.primary),
                  label: Text('chatx.conversation'.tr(),
                      style: const TextStyle(color: AppColors.primary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
                const SizedBox(width: 10),
                if (isCompleted)
                  Expanded(
                      child: ElevatedButton.icon(
                    onPressed: () =>
                        context.push('/rate-deal/${widget.deal.id}'),
                    icon: const Icon(Icons.star_outline, size: 16),
                    label: Text('chatx.statusRate'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ))
                else
                  Expanded(
                      child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      expired ? 'dcard.soon'.tr() : 'dcard.inProgress'.tr(),
                      style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
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
        Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12))),
      ]);
}
