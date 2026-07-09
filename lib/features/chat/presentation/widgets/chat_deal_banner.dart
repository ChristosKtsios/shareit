import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/date_helpers.dart';
import '../../../deals/data/deal_model.dart';

class ChatDealBanner extends StatefulWidget {
  final DealModel deal;
  const ChatDealBanner({super.key, required this.deal});
  @override
  State<ChatDealBanner> createState() => _ChatDealBannerState();
}

class _ChatDealBannerState extends State<ChatDealBanner> {
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

    return GestureDetector(
      onTap: () => context.push('/rate-deal/${widget.deal.id}'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 10),
        color: color.withValues(alpha: 0.12),
        child: Row(children: [
          Icon(
            expired
                ? Icons.check_circle_outline
                : Icons.handshake_outlined,
            color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            expired ? AppStrings.dealDone : AppStrings.dealActive,
            style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
          const Spacer(),
          if (!expired)
            Text(
              DateHelpers.formatTimer(_remaining),
              style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            )
          else
            Text('dealbanner.rate'.tr(),
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}