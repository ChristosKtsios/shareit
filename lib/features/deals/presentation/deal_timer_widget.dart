import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_helpers.dart';
import '../data/deal_model.dart';

class DealTimerWidget extends StatefulWidget {
  final DealModel deal;
  final bool compact;
  const DealTimerWidget({super.key, required this.deal, this.compact = false});
  @override
  State<DealTimerWidget> createState() => _DealTimerWidgetState();
}

class _DealTimerWidgetState extends State<DealTimerWidget> {
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
    final color   = expired ? AppColors.danger : AppColors.deal;

    if (widget.compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          expired ? 'Έληξε' : DateHelpers.formatTimer(_remaining),
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.1),
      child: Row(children: [
        Icon(Icons.handshake_outlined, color: color, size: 18),
        const SizedBox(width: 8),
        Text('Deal ενεργό',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(
          expired ? 'Ολοκληρώθηκε' : DateHelpers.formatTimer(_remaining),
          style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ]),
    );
  }
}
