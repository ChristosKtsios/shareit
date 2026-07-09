import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/deal_provider.dart';

class RateDealScreen extends ConsumerStatefulWidget {
  final String dealId;
  const RateDealScreen({super.key, required this.dealId});
  @override
  ConsumerState<RateDealScreen> createState() => _RateDealScreenState();
}

class _RateDealScreenState extends ConsumerState<RateDealScreen> {
  double _rating = 0;
  bool _loading = false;
  bool _checking = true;
  bool _alreadyRated = false;

  @override
  void initState() {
    super.initState();
    _checkIfRated();
  }

  Future<void> _checkIfRated() async {
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final hasRated = await ref.read(dealRepoProvider).hasUserRated(
            dealId: widget.dealId,
            userId: uid,
          );
      if (mounted) {
        setState(() {
          _alreadyRated = hasRated;
          _checking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_rating == 0 || _alreadyRated) return;
    setState(() => _loading = true);
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    try {
      await ref.read(dealRepoProvider).rate(
            dealId: widget.dealId,
            raterUid: uid,
            rating: _rating,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('rate.submitted'.tr()),
            backgroundColor: AppColors.offer,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('rate.errorWith'.tr(namedArgs: {'e': '$e'}))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('rate.title'.tr())),
      body: _checking
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _alreadyRated
              ? _buildAlreadyRated()
              : _buildRatingForm(),
    );
  }

  Widget _buildAlreadyRated() {
    return SafeArea(
      top: false,
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: AppColors.offer, size: 80),
          const SizedBox(height: 24),
          Text('rate.alreadyTitle'.tr(),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
              'rate.alreadySub'.tr(),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.pop(),
            child: Text('rate.goBack'.tr()),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildRatingForm() {
    return SafeArea(
      top: false,
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('rate.howWentDeal'.tr(),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('rate.giveStars'.tr(),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
                5,
                (i) => GestureDetector(
                      onTap: () => setState(() => _rating = (i + 1).toDouble()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                            i < _rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: AppColors.deal,
                            size: 44),
                      ),
                    )),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading || _rating == 0 ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.background))
                  : Text('rate.submit'.tr()),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
