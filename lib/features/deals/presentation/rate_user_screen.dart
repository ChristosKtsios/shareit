import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/deal_provider.dart';

class RateUserScreen extends ConsumerStatefulWidget {
  final String dealId;
  final String targetName;
  final String targetInitials;

  const RateUserScreen({
    super.key,
    required this.dealId,
    required this.targetName,
    required this.targetInitials,
  });

  @override
  ConsumerState<RateUserScreen> createState() => _RateUserScreenState();
}

class _RateUserScreenState extends ConsumerState<RateUserScreen> {
  double _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Διάλεξε αριθμό αστεριών πρώτα.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final uid = ref.read(currentUserProvider)!.uid;
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
      appBar: AppBar(
        title: const Text('Αξιολόγηση'),
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 20),
          UserAvatar(initials: widget.targetInitials, radius: 36),
          const SizedBox(height: 16),
          Text(widget.targetName,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Πώς ήταν η ανταλλαγή;',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 32),

          // Stars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => GestureDetector(
              onTap: () => setState(() => _rating = i + 1.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  i < _rating ? Icons.star : Icons.star_border,
                  color: AppColors.deal, size: 44),
              ),
            )),
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
                hintText: 'Γράψε ένα σχόλιο (προαιρετικό)...'),
          ),
          const Spacer(),

          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.background))
                : const Text('Υποβολή αξιολόγησης'),
          ),
        ]),
      ),
    );
  }
}