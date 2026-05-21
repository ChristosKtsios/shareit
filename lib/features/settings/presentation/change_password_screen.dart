import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _newPassCtrl    = TextEditingController();
  final _confirmCtrl    = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _newPassCtrl.dispose(); _confirmCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final newPass = _newPassCtrl.text;
    if (newPass.length < 6) {
      setState(() => _error = 'Ο κωδικός πρέπει να έχει τουλάχιστον 6 χαρακτήρες.');
      return;
    }
    if (newPass != _confirmCtrl.text) {
      setState(() => _error = 'Οι κωδικοί δεν ταιριάζουν.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepoProvider).updatePassword(newPass);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ο κωδικός άλλαξε επιτυχώς.')));
        context.pop();
      }
    } catch (_) {
      setState(() => _error = 'Σφάλμα. Μπορεί να χρειαστείς να συνδεθείς ξανά.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Αλλαγή κωδικού')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Νέος κωδικός',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _newPassCtrl, obscureText: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: 'Τουλάχιστον 6 χαρακτήρες'),
          ),
          const SizedBox(height: 16),
          const Text('Επιβεβαίωση κωδικού',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _confirmCtrl, obscureText: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(hintText: 'Ξανά τον ίδιο κωδικό'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                : const Text('Αλλαγή κωδικού'),
          ),
        ]),
      ),
    );
  }
}
