import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/profile_provider.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Εισάγαγε τον κωδικό σου για επιβεβαίωση.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Τελική επιβεβαίωση',
            style: TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w700)),
        content: const Text(
            'Είσαι απόλυτα σίγουρος; Ο λογαριασμός σου και όλα τα δεδομένα σου '
            'θα διαγραφούν μόνιμα. Αυτή η ενέργεια δεν μπορεί να αναιρεθεί.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Άκυρο')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Διαγραφή',
                style: TextStyle(color: AppColors.danger,
                    fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() { _loading = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid  = user.uid;

      // Re-authenticate πριν τη διαγραφή
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _passwordCtrl.text,
      );
      await user.reauthenticateWithCredential(credential);

      // Σήμανση ως deleted στο Firestore
      await ref.read(userRepoProvider).update(uid, {
        'deleted': true,
        'deletedAt': DateTime.now().toIso8601String(),
      });

      // Διαγραφή από Firebase Auth
      await user.delete();

      if (mounted) context.go('/login');
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'wrong-password') {
          _error = 'Λάθος κωδικός. Δοκίμασε ξανά.';
        } else {
          _error = e.message ?? 'Σφάλμα. Δοκίμασε ξανά.';
        }
      });
    } catch (e) {
      setState(() => _error = 'Σφάλμα: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Διαγραφή λογαριασμού')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Warning icon
              Center(child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: AppColors.danger, size: 44),
              )),
              const SizedBox(height: 24),

              // Title
              const Center(child: Text('Διαγραφή λογαριασμού',
                  style: TextStyle(color: AppColors.textPrimary,
                      fontSize: 22, fontWeight: FontWeight.w700))),
              const SizedBox(height: 12),

              // Warning text
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Αυτή η ενέργεια θα:',
                        style: TextStyle(color: AppColors.danger,
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    SizedBox(height: 8),
                    _WarningItem(text: 'Διαγράψει μόνιμα τον λογαριασμό σου'),
                    _WarningItem(text: 'Διαγράψει όλες τις αγγελίες σου'),
                    _WarningItem(text: 'Διαγράψει όλες τις συνομιλίες σου'),
                    _WarningItem(text: 'Δεν μπορεί να αναιρεθεί'),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Password confirmation
              const Text('Εισάγαγε τον κωδικό σου για επιβεβαίωση:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordCtrl,
                obscureText: !_showPass,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Κωδικός',
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: AppColors.textSecondary, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_showPass
                        ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary, size: 20),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: AppColors.danger, fontSize: 13)),
              ],
              const Spacer(),

              // Delete button
              OutlinedButton.icon(
                onPressed: _loading ? null : _deleteAccount,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.danger))
                    : const Icon(Icons.delete_forever,
                        color: AppColors.danger, size: 20),
                label: const Text('Διαγραφή λογαριασμού',
                    style: TextStyle(color: AppColors.danger,
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),

              // Cancel button
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Άκυρο'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningItem extends StatelessWidget {
  final String text;
  const _WarningItem({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      const Icon(Icons.close, color: AppColors.danger, size: 14),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 13)),
    ]),
  );
}