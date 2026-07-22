import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/legal_urls.dart';
import '../../../core/utils/display_name.dart';
import '../providers/auth_provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/password_strength.dart';
import '../data/auth_repository.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _passConfirm = TextEditingController();

  bool _loading = false;
  bool _showPass = false;
  bool _showPassConfirm = false;
  bool _ageAccepted = false;
  bool _termsAccepted = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _passConfirm.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _continueToVerification() async {
    setState(() => _error = null);

    // Το όνομα είναι προαιρετικό: αν λείπει, το βγάζουμε από το email
    // («giorgos.pap@…» → «Giorgos Pap»). Έτσι η εγγραφή είναι πιο γρήγορη και
    // κανείς δεν εμφανίζεται ποτέ ως σκέτο «Χρήστης».
    if (!AuthRepository.isValidEmail(_email.text)) {
      setState(() => _error = 'reg.giveValidEmail'.tr());
      return;
    }
    // Όνομα/επώνυμο από το email: «giorgos.papadopoulos@…» → «Giorgos
    // Papadopoulos». Ο χρήστης μπορεί να τα διορθώσει από το Προφίλ.
    final (firstName, lastName) = DisplayName.from(email: _email.text.trim());
    if (firstName.isEmpty) {
      setState(() => _error = 'reg.fillName'.tr());
      return;
    }
    final pass = _pass.text.trim();
    final passError = AuthRepository.validatePassword(pass);
    if (passError != null) {
      setState(() => _error = passError);
      return;
    }

    if (pass != _passConfirm.text.trim()) {
      setState(() => _error = 'reg.passwordsMismatch'.tr());
      return;
    }

    if (!_ageAccepted) {
      setState(() => _error = 'reg.mustConfirm18'.tr());
      return;
    }

    if (!_termsAccepted) {
      setState(() => _error = 'reg.mustAcceptTermsPolicy'.tr());
      return;
    }

    setState(() => _loading = true);
    try {
      // Η εγγραφή είναι ΠΑΝΤΑ email + κωδικός. Καμία άλλη ερώτηση: ο χρήστης
      // μπαίνει αμέσως ως «μη επαληθευμένος» και συμπληρώνει ό,τι θέλει (φωτο,
      // όνομα, κινητό) από το Προφίλ → Επεξεργασία, όποτε θέλει.
      await ref.read(authRepoProvider).registerWithEmail(
            email: _email.text.trim(),
            password: pass,
            firstName: firstName,
            lastName: lastName,
          );
      if (mounted) context.go('/map');
    } catch (e) {
      setState(() => _error = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.signUp)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: AppStrings.email,
                prefixIcon: Icon(Icons.email_outlined,
                    color: AppColors.textSecondary, size: 20),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _pass,
              obscureText: !_showPass,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: AppStrings.password,
                prefixIcon: const Icon(Icons.lock_outline,
                    color: AppColors.textSecondary, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                      _showPass ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textSecondary,
                      size: 20),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            PasswordStrengthIndicator(password: _pass.text),
            const SizedBox(height: 4),
            Text(
              'reg.passwordHint'.tr(),
              style: const TextStyle(color: AppColors.textHint, fontSize: 11),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _passConfirm,
              obscureText: !_showPassConfirm,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'reg.confirmPassword'.tr(),
                prefixIcon: const Icon(Icons.lock_outline,
                    color: AppColors.textSecondary, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                      _showPassConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.textSecondary,
                      size: 20),
                  onPressed: () =>
                      setState(() => _showPassConfirm = !_showPassConfirm),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ΝΕΟ: Age verification checkbox
            InkWell(
              onTap: () => setState(() => _ageAccepted = !_ageAccepted),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _ageAccepted,
                        onChanged: (v) =>
                            setState(() => _ageAccepted = v ?? false),
                        activeColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'authx.age18'.tr(),
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                          ),
                        ),
                      ),
                    ]),
              ),
            ),

            // ΝΕΟ: Terms acceptance checkbox με links
            InkWell(
              onTap: () => setState(() => _termsAccepted = !_termsAccepted),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _termsAccepted,
                        onChanged: (v) =>
                            setState(() => _termsAccepted = v ?? false),
                        activeColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  height: 1.4),
                              children: [
                                TextSpan(text: 'authx.acceptThe'.tr()),
                                TextSpan(
                                  text: 'authx.termsOfUse'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => _openUrl(LegalUrls.terms(
                                        context.locale.languageCode)),
                                ),
                                TextSpan(text: 'authx.andThe'.tr()),
                                TextSpan(
                                  text: 'authx.privacyPolicy'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => _openUrl(LegalUrls.privacy(
                                        context.locale.languageCode)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ]),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 13))),
                ]),
              ),
            ],
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _loading ? null : _continueToVerification,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.background))
                  : Text('authx.continue'.tr()),
            ),
            const SizedBox(height: 16),

            TextButton(
              onPressed: () => context.pop(),
              child: Text('${AppStrings.hasAccount} ${AppStrings.login}'),
            ),
          ]),
        ),
      ),
    );
  }
}
