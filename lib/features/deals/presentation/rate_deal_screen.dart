import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  bool _loading  = false;

  Future<void> _submit() async {
    if (_rating == 0) return;
    setState(() => _loading = true);
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    try {
      await ref.read(dealRepoProvider).rate(
        dealId:   widget.dealId,
        raterUid: uid,
        rating:   _rating,
      );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Αξιολόγηση')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Πώς πήγε η ανταλλαγή;',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => GestureDetector(
                onTap: () => setState(() => _rating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    i < _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppColors.deal, size: 48),
                ),
              )),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _loading || _rating == 0 ? null : _submit,
              child: _loading
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background))
                  : const Text('Υποβολή αξιολόγησης'),
            ),
          ],
        ),
      ),
    );
  }
}