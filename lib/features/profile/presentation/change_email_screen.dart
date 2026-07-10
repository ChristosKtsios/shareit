import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/data/auth_repository.dart';

/// Ασφαλής αλλαγή email:
///   1. re-authentication με τον τρέχοντα κωδικό (απαιτεί η Firebase για
///      sensitive operations — αλλιώς `requires-recent-login`),
///   2. `verifyBeforeUpdateEmail` → σύνδεσμος επιβεβαίωσης στο **νέο** email.
///
/// Το Auth email αλλάζει **μόνο** αφού ο χρήστης πατήσει τον σύνδεσμο, γι' αυτό
/// ΔΕΝ γράφουμε τώρα το Firestore. Ο συγχρονισμός γίνεται lazily (βλ.
/// `edit_profile_screen`), μόλις το `user.email` αλλάξει πραγματικά.
///
/// Σημείωση: χρησιμοποιούμε `verifyBeforeUpdateEmail` και ΟΧΙ το deprecated
/// `updateEmail`, που άλλαζε το email χωρίς απόδειξη κατοχής.
class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Το email μπορεί να αλλάξει από εδώ μόνο αν ο λογαριασμός έχει κωδικό.
  /// Οι Google-only χρήστες το διαχειρίζονται από τον λογαριασμό Google.
  bool get _hasPassword =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  bool get _isGoogle =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == 'google.com') ??
      false;

  Future<void> _submit() async {
    final password = _passwordCtrl.text;
    final newEmail = _emailCtrl.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    final currentEmail = user?.email ?? '';

    if (password.isEmpty) {
      setState(() => _error = 'authx.fillPassword'.tr());
      return;
    }
    if (!AuthRepository.isValidEmail(newEmail)) {
      setState(() => _error = 'authx.invalidEmail'.tr());
      return;
    }
    if (newEmail.toLowerCase() == currentEmail.toLowerCase()) {
      setState(() => _error = 'ce.sameEmail'.tr());
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (user == null) throw FirebaseAuthException(code: 'no-user');

      // 1) Re-authentication με τον τρέχοντα κωδικό.
      final cred = EmailAuthProvider.credential(
          email: currentEmail, password: password);
      await user.reauthenticateWithCredential(cred);

      // 2) Σύνδεσμος επιβεβαίωσης στο ΝΕΟ email (το Auth email αλλάζει μόνο
      //    όταν πατηθεί ο σύνδεσμος).
      await user.verifyBeforeUpdateEmail(newEmail);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent = true;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        switch (e.code) {
          case 'wrong-password':
          case 'invalid-credential':
            _error = 'ce.wrongPassword'.tr();
            break;
          case 'email-already-in-use':
            _error = 'ce.emailInUse'.tr();
            break;
          case 'invalid-email':
            _error = 'authx.invalidEmail'.tr();
            break;
          case 'requires-recent-login':
          case 'user-token-expired':
            _error = 'ce.relogin'.tr();
            break;
          case 'too-many-requests':
            _error = 'authx.tooManyAttempts'.tr();
            break;
          case 'network-request-failed':
            _error = 'authx.networkError'.tr();
            break;
          default:
            _error = e.message ?? 'fp.somethingWrong'.tr();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'common.errorGeneric'.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ce.title'.tr())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: _sent
              ? _buildSent()
              : (!_hasPassword ? _buildBlocked() : _buildForm()),
        ),
      ),
    );
  }

  /// Google-only (ή χωρίς κωδικό) → δεν αλλάζει email από την εφαρμογή.
  Widget _buildBlocked() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.info_outline, color: AppColors.primary, size: 56),
        const SizedBox(height: 20),
        Text(
          _isGoogle ? 'ce.googleManaged'.tr() : 'ce.noPassword'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildSent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mark_email_read_outlined,
            color: AppColors.offer, size: 56),
        const SizedBox(height: 20),
        Text('ce.sentTitle'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(
          'ce.sentBody'.tr(namedArgs: {'email': _emailCtrl.text.trim()}),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text('deals.back'.tr()),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'ce.intro'.tr(),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            textInputAction: TextInputAction.next,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(labelText: 'ce.currentPassword'.tr()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(labelText: 'ce.newEmail'.tr()),
            onSubmitted: (_) => _loading ? null : _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style: const TextStyle(
                      color: AppColors.danger, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.background))
                : Text('ce.send'.tr()),
          ),
        ],
      ),
    );
  }
}
