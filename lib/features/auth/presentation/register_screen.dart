import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/legal_urls.dart';
import '../../../core/constants/countries.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/password_strength.dart';
import '../data/auth_repository.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _passConfirm = TextEditingController();

  String _countryCode = '+30';
  bool _loading = false;
  bool _showPass = false;
  bool _showPassConfirm = false;
  bool _ageAccepted = false;
  bool _termsAccepted = false;
  String? _error;

  File? _profilePhoto;

  final List<Map<String, String>> _countries = Countries.all;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    _passConfirm.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _profilePhoto = File(picked.path));
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _continueToVerification() async {
    setState(() => _error = null);

    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      setState(() => _error = 'reg.fillName'.tr());
      return;
    }
    if (!AuthRepository.isValidEmail(_email.text)) {
      setState(() => _error = 'reg.giveValidEmail'.tr());
      return;
    }
    if (_phone.text.trim().isEmpty || _phone.text.trim().length < 8) {
      setState(() => _error = 'reg.giveValidPhone'.tr());
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
      setState(
          () => _error = 'reg.mustAcceptTermsPolicy'.tr());
      return;
    }

    setState(() => _loading = true);
    try {
      final fullPhone = '$_countryCode${_phone.text.trim()}';
      final email = _email.text.trim();

      // Έλεγχος ΠΡΙΝ το OTP: υπάρχει ήδη λογαριασμός με αυτό το email/κινητό;
      // Γίνεται server-side (Cloud Function με admin) — δεν χρειάζεται sign-in
      // ούτε να σπαταλήσουμε OTP.
      try {
        final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('checkAccountExists')
            .call({'email': email, 'phone': fullPhone});
        final data = Map<String, dynamic>.from(res.data as Map);
        if (data['phoneExists'] == true) {
          setState(() {
            _error = 'reg.phoneExists'.tr();
            _loading = false;
          });
          return;
        }
        if (data['emailExists'] == true) {
          setState(() {
            _error = 'reg.emailExists'.tr();
            _loading = false;
          });
          return;
        }
      } catch (_) {
        // Αν ο έλεγχος αποτύχει (πχ δίκτυο), συνεχίζουμε — τα post-OTP
        // safeguards στο registerWithPhoneVerified θα πιάσουν τυχόν διπλό.
      }

      if (!mounted) return;
      context.push('/phone-auth', extra: {
        'mode': 'register',
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'email': _email.text.trim(),
        'phone': fullPhone,
        'password': pass,
        'profilePhotoPath': _profilePhoto?.path,
      });
    } catch (e) {
      setState(() => _error = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        top: false,
        child: ListView.builder(
          itemCount: _countries.length,
          itemBuilder: (_, i) {
            final c = _countries[i];
            return ListTile(
              leading: Text(c['flag']!, style: const TextStyle(fontSize: 24)),
              title: Text(c['name']!,
                  style: const TextStyle(color: AppColors.textPrimary)),
              trailing: Text(c['code']!,
                  style: const TextStyle(color: AppColors.textSecondary)),
              onTap: () {
                setState(() => _countryCode = c['code']!);
                Navigator.pop(context);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.signUp)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(children: [
            GestureDetector(
              onTap: _pickPhoto,
              child: Stack(children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceVariant,
                    border: Border.all(color: AppColors.border, width: 1),
                    image: _profilePhoto != null
                        ? DecorationImage(
                            image: FileImage(_profilePhoto!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _profilePhoto == null
                      ? const Icon(Icons.person_outline,
                          color: AppColors.textSecondary, size: 40)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 16),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Text('reg.photoOptional'.tr(),
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
            const SizedBox(height: 24),

            Row(children: [
              Expanded(
                child: TextField(
                  controller: _first,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration:
                      InputDecoration(hintText: AppStrings.firstName),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _last,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration:
                      InputDecoration(hintText: AppStrings.lastName),
                ),
              ),
            ]),
            const SizedBox(height: 12),

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

            Row(children: [
              GestureDetector(
                onTap: _showCountryPicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Row(children: [
                    Text(_countryCode,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down,
                        color: AppColors.textSecondary, size: 18),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '6901234567',
                    prefixIcon: Icon(Icons.phone_outlined,
                        color: AppColors.textSecondary, size: 20),
                  ),
                ),
              ),
            ]),
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
                                    ..onTap = () => _openUrl(
                                        LegalUrls.terms(context.locale.languageCode)),
                                ),
                                TextSpan(text: 'authx.andThe'.tr()),
                                TextSpan(
                                  text: 'authx.privacyPolicy'.tr(),
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => _openUrl(
                                        LegalUrls.privacy(context.locale.languageCode)),
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
