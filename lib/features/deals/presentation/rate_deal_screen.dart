import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
          const SnackBar(
            content: Text('✅ Η αξιολόγησή σου καταχωρήθηκε!'),
            backgroundColor: AppColors.offer,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Αξιολόγηση')),
      body: _checking
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _alreadyRated
              ? _buildAlreadyRated()
              : _buildRatingForm(),
    );
  }

  Widget _buildAlreadyRated() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: AppColors.offer, size: 80),
          const SizedBox(height: 24),
          const Text('Έχεις ήδη αξιολογήσει αυτό το deal',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
              'Η αξιολόγηση μπορεί να γίνει μόνο μία φορά για κάθε deal.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.pop(),
            child: const Text('Επιστροφή'),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingForm() {
    return Padding(
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
          const SizedBox(height: 8),
          const Text('Δώσε αστέρια από 1-5',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                5,
                (i) => GestureDetector(
                      onTap: () => setState(() => _rating = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                            i < _rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: AppColors.deal,
                            size: 48),
                      ),
                    )),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: _loading || _rating == 0 ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.background))
                : const Text('Υποβολή αξιολόγησης'),
          ),
        ],
      ),
    );
  }
}
