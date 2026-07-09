import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/password_strength.dart';
import '../../auth/data/auth_repository.dart';
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
    final newPass = _newPassCtrl.text.trim();
    // Ίδιοι κανόνες με την εγγραφή (8 χαρ., κεφαλαίο, αριθμό, σύμβολο).
    final passError = AuthRepository.validatePassword(newPass);
    if (passError != null) {
      setState(() => _error = passError);
      return;
    }
    if (newPass != _confirmCtrl.text.trim()) {
      setState(() => _error = 'changePass.passwordsMismatch'.tr());
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepoProvider).updatePassword(newPass);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('changePass.success'.tr())));
        context.pop();
      }
    } catch (_) {
      setState(() => _error = 'changePass.errorRelogin'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.changePassword'.tr())),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('changePass.newPassword'.tr(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _newPassCtrl, obscureText: true,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
                hintText: 'changePass.passwordHint'.tr()),
          ),
          PasswordStrengthIndicator(password: _newPassCtrl.text),
          const SizedBox(height: 16),
          Text('changePass.confirmPassword'.tr(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _confirmCtrl, obscureText: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(hintText: 'changePass.confirmHint'.tr()),
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
                : Text('settings.changePassword'.tr()),
          ),
        ]),
      ),
    );
  }
}
