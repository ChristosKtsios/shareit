import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/password_strength.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_provider.dart';

/// Αλλαγή κωδικού με **re-authentication**.
///
/// ΚΡΙΣΙΜΟ: χωρίς έλεγχο του τρέχοντος κωδικού, κάποιος με πρόσβαση στο
/// ξεκλείδωτο κινητό μπορούσε — μέσα στο παράθυρο «recent login» της Firebase —
/// να θέσει νέο κωδικό ΧΩΡΙΣ να ξέρει τον παλιό, και στη συνέχεια να περάσει και
/// το re-auth της αλλαγής email/κινητού. Πλήρης κατάληψη λογαριασμού.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _currentCtrl    = TextEditingController();
  final _newPassCtrl    = TextEditingController();
  final _confirmCtrl    = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Ο κωδικός αλλάζει μόνο αν ο λογαριασμός ΕΧΕΙ κωδικό. Οι Google-only
  /// χρήστες δεν έχουν — τους το εξηγούμε αντί να αποτύχει η ενέργεια.
  bool get _hasPassword =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  Future<void> _submit() async {
    final currentPass = _currentCtrl.text;
    final newPass = _newPassCtrl.text.trim();

    if (currentPass.isEmpty) {
      setState(() => _error = 'authx.fillPassword'.tr());
      return;
    }
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw FirebaseAuthException(code: 'no-user');

      // ── Re-authentication με τον ΤΡΕΧΟΝΤΑ κωδικό (η ουσία της διόρθωσης) ──
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
            email: user.email ?? '', password: currentPass),
      );

      await ref.read(authRepoProvider).updatePassword(newPass);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('changePass.success'.tr())));
        context.pop();
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'wrong-password':
          case 'invalid-credential':
            _error = 'changePass.wrongCurrent'.tr();
            break;
          case 'weak-password':
            _error = 'reg.passwordHint'.tr();
            break;
          case 'too-many-requests':
            _error = 'authx.tooManyAttempts'.tr();
            break;
          case 'network-request-failed':
            _error = 'authx.networkError'.tr();
            break;
          default:
            _error = 'changePass.errorRelogin'.tr();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'changePass.errorRelogin'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.changePassword'.tr())),
      body: !_hasPassword
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.primary, size: 56),
                  const SizedBox(height: 20),
                  Text('changePass.googleNoPassword'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.5)),
                ],
              ),
            )
          : Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Τρέχων κωδικός (re-authentication) ──
          Text('changePass.currentPassword'.tr(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _currentCtrl, obscureText: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
                hintText: 'changePass.currentHint'.tr()),
          ),
          const SizedBox(height: 16),
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
      ),
    );
  }
}
