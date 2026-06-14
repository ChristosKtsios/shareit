import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _agreed = false;

  static const String _confirmWord = 'ΔΙΑΓΡΑΦΗ';

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    setState(() => _loading = true);

    try {
      // Cloud Function call
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('deleteUserAccount');
      final result = await callable.call();

      if (!mounted) return;

      final data = result.data as Map<dynamic, dynamic>?;
      final success = data?['success'] == true;

      if (success) {
        // Logout local state — το auth state ήδη έχει διαγραφεί στον server
        try {
          await ref.read(authRepoProvider).logout();
        } catch (_) {}

        if (!mounted) return;

        // GoRouter redirect θα πάει στο /login αυτόματα
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ο λογαριασμός σου διαγράφηκε.'),
            backgroundColor: AppColors.offer,
          ),
        );

        // Καθαρίζουμε όλο το navigation stack
        if (mounted) {
          context.go('/login');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Κάτι πήγε στραβά. Δοκίμασε ξανά.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Σφάλμα: ${e.message ?? e.code}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Σφάλμα: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete =
        _agreed && _confirmCtrl.text.trim().toUpperCase() == _confirmWord;

    return Scaffold(
      appBar: AppBar(title: const Text('Διαγραφή λογαριασμού')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.4), width: 1),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.warning_amber_rounded,
                          color: AppColors.danger, size: 22),
                      SizedBox(width: 8),
                      Text('Προσοχή',
                          style: TextStyle(
                              color: AppColors.danger,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ]),
                    SizedBox(height: 8),
                    Text(
                      'Η διαγραφή του λογαριασμού είναι μόνιμη και δεν '
                      'μπορεί να αναιρεθεί.',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text('Τι θα διαγραφεί',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),

              _DeleteItem('Όλες οι αγγελίες σου'),
              _DeleteItem('Όλες οι συνομιλίες σου'),
              _DeleteItem('Όλα τα deals και αξιολογήσεις'),
              _DeleteItem('Οι φωτογραφίες προφίλ σου'),
              _DeleteItem('Οι φιλίες και αιτήματα φιλίας'),
              _DeleteItem('Τα στοιχεία του λογαριασμού σου'),

              const SizedBox(height: 24),

              // Checkbox συμφωνίας
              Row(children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  activeColor: AppColors.danger,
                ),
                const Expanded(
                  child: Text(
                    'Καταλαβαίνω ότι η διαγραφή είναι μόνιμη και δεν '
                    'μπορεί να αναιρεθεί.',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              const Text(
                'Για επιβεβαίωση, πληκτρολόγησε «$_confirmWord»:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: _confirmWord,
                ),
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: canDelete && !_loading ? _deleteAccount : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.surfaceVariant,
                  disabledForegroundColor: AppColors.textHint,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Διαγραφή λογαριασμού',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),

              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => context.pop(),
                  child: const Text('Άκυρο',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteItem extends StatelessWidget {
  final String text;
  const _DeleteItem(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Icon(Icons.close, color: AppColors.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
        ]),
      );
}
