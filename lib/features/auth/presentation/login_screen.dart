import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/profile_gate.dart';
import '../../profile/data/user_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/countries.dart';
import '../../../core/constants/app_strings.dart';
import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';

enum _LoginMode { email, phone }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  _LoginMode _mode = _LoginMode.email;
  String _countryCode = '+30';
  bool _loading = false;
  bool _showPass = false;
  String? _error;

  final List<Map<String, String>> _countries = Countries.all;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _login() async {
    if (_mode == _LoginMode.email) {
      if (_emailCtrl.text.trim().isEmpty) {
        setState(() => _error = 'authx.fillEmail'.tr());
        return;
      }
      if (!AuthRepository.isValidEmail(_emailCtrl.text)) {
        setState(() => _error = 'authx.invalidEmail'.tr());
        return;
      }
    } else {
      if (_phoneCtrl.text.trim().isEmpty) {
        setState(() => _error = 'authx.fillPhone'.tr());
        return;
      }
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'authx.fillPassword'.tr());
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final pass = _passwordCtrl.text.trim();
      if (_mode == _LoginMode.email) {
        await ref.read(authRepoProvider).loginWithEmail(
              _emailCtrl.text.trim(),
              pass,
            );
      } else {
        final fullPhone = '$_countryCode${_phoneCtrl.text.trim()}';
        await ref.read(authRepoProvider).loginWithPhone(
              fullPhone,
              pass,
            );
      }
      if (mounted) context.go('/map');
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
          case 'no-email':
            _error = _mode == _LoginMode.email
                ? 'authx.noAccountEmail'.tr()
                : 'authx.noAccountPhone'.tr();
            break;
          case 'wrong-password':
            _error = 'authx.wrongPassword'.tr();
            break;
          case 'invalid-credential':
            _error = _mode == _LoginMode.email
                ? 'authx.wrongEmailOrPass'.tr()
                : 'authx.wrongPhoneOrPass'.tr();
            break;
          case 'invalid-email':
            _error = 'authx.invalidEmail'.tr();
            break;
          case 'user-disabled':
            _error = 'authx.accountDisabled'.tr();
            break;
          case 'operation-not-allowed':
            _error = 'authx.emailLoginUnavailable'.tr();
            break;
          case 'too-many-requests':
            _error = 'authx.tooManyAttempts'.tr();
            break;
          case 'network-request-failed':
            _error = 'authx.networkError'.tr();
            break;
          default:
            _error = AppStrings.errorGeneric;
        }
      });
    } catch (e) {
      setState(() => _error = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _showTermsDialog() async {
    bool ageOk = false;
    bool termsOk = false;
    bool? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('authx.beforeContinue'.tr(),
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'authx.confirmFollowing'.tr(),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setDialogState(() => ageOk = !ageOk),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: ageOk,
                        onChanged: (v) =>
                            setDialogState(() => ageOk = v ?? false),
                        activeColor: AppColors.primary,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text('authx.age18'.tr(),
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13)),
                        ),
                      ),
                    ]),
              ),
            ),
            InkWell(
              onTap: () => setDialogState(() => termsOk = !termsOk),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: termsOk,
                        onChanged: (v) =>
                            setDialogState(() => termsOk = v ?? false),
                        activeColor: AppColors.primary,
                      ),
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
                                        'https://shareit-6cfa0.web.app/terms.html'),
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
                                        'https://shareit-6cfa0.web.app/privacy_policy.html'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ]),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                result = false;
                Navigator.pop(dialogContext);
              },
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: (ageOk && termsOk)
                  ? () {
                      result = true;
                      Navigator.pop(dialogContext);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.3),
              ),
              child: Text('authx.continue'.tr(),
                  style: TextStyle(color: AppColors.background)),
            ),
          ],
        ),
      ),
    );

    return result == true;
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final googleUser = await GoogleSignIn(
        // Ρητό web client ID (client_type 3 από το google-services.json) ώστε
        // να παίρνουμε πάντα idToken για το Firebase Auth.
        serverClientId:
            '298536596181-ocikmg46hot2lqma65q54rbm8ibtnsjv.apps.googleusercontent.com',
      ).signIn();
      if (googleUser == null) {
        // Ο χρήστης ακύρωσε το popup.
        setState(() => _loading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        setState(() {
          _loading = false;
          _error = 'authx.googleError'.tr();
        });
        return;
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        final db = FirebaseFirestore.instance;
        final docRef = db.collection('users').doc(user.uid);
        final doc = await docRef.get();

        // Αν είναι νέος χρήστης — ζητάμε αποδοχή terms
        if (!doc.exists) {
          if (!mounted) return;
          final accepted = await _showTermsDialog();
          if (!accepted) {
            // Ο χρήστης δεν αποδέχτηκε — διαγραφή του Firebase Auth user
            try {
              await user.delete();
            } catch (_) {
              await FirebaseAuth.instance.signOut();
            }
            await GoogleSignIn().signOut();
            setState(() {
              _loading = false;
              _error = 'authx.mustAcceptTerms'.tr();
            });
            return;
          }

          // Δημιουργία profile
          final displayName = user.displayName ?? googleUser.displayName ?? '';
          final parts = displayName.trim().split(' ');
          final firstName = parts.isNotEmpty ? parts.first : '';
          final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

          // ΠΡΟΣΟΧΗ: email/phone ΔΕΝ μπαίνουν στο δημόσιο doc — πάνε στο
          // users/{uid}/private/data (το δημόσιο doc το διαβάζουν όλοι).
          await docRef.set({
            'uid': user.uid,
            'firstName': firstName,
            'lastName': lastName,
            'photoUrl': user.photoURL ?? googleUser.photoUrl,
            'avatarUrl': user.photoURL ?? googleUser.photoUrl,
            'rating': 0.0,
            'ratingCount': 0,
            'isVerified': true,
            'phoneVerified': false,
            'blockedUids': [],
            'savedListingIds': [],
            'friends': [],
            'dealsCount': 0,
            'isPrivateProfile': false,
            'showOnlineStatus': true,
            'termsAcceptedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          });

          await UserRepository.privateRef(user.uid).set({
            'email': user.email ?? googleUser.email,
            'phone': user.phoneNumber ?? '',
          }, SetOptions(merge: true));

          // Το doc μόλις δημιουργήθηκε → αποθήκευσε τώρα το FCM token (το
          // FcmService.init είχε τρέξει πριν υπάρξει doc, με update-only write).
          await FcmService.syncToken(user.uid);

          // Το doc υπάρχει πλέον → ο router να το ξαναδιαβάσει, ώστε να πιάσει
          // την υποχρεωτική επαλήθευση κινητού (phoneVerified: false).
          ProfileGate.invalidate();
        } else {
          // Το email μπορεί να άλλαξε στο Google → κράτα το private doc συγχρονισμένο.
          final googleEmail = user.email ?? googleUser.email;
          if (googleEmail.isNotEmpty) {
            await UserRepository.privateRef(user.uid)
                .set({'email': googleEmail}, SetOptions(merge: true));
          }

          // Υπάρχων χρήστης — ενημέρωση μόνο αν λείπει firstName
          final data = doc.data() as Map<String, dynamic>;
          final existingFirstName = (data['firstName'] as String? ?? '').trim();
          if (existingFirstName.isEmpty) {
            final displayName =
                user.displayName ?? googleUser.displayName ?? '';
            final parts = displayName.trim().split(' ');
            final firstName = parts.isNotEmpty ? parts.first : '';
            final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
            if (firstName.isNotEmpty) {
              // ΔΕΝ πειράζουμε photoUrl/avatarUrl — μπορεί ο χρήστης να έχει
              // ανεβάσει δικό του avatar· δεν το αντικαθιστούμε με το Google.
              await docRef.set({
                'firstName': firstName,
                'lastName': lastName,
              }, SetOptions(merge: true));
            }
          }
        }
      }

      if (mounted) context.go('/map');
    } catch (e) {
      setState(() => _error = 'authx.googleError'.tr());
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
      builder: (_) => ListView.builder(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text(AppStrings.appName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontSize: 36,
                      letterSpacing: -1)),
              const SizedBox(height: 8),
              Text('authx.exchangesNearYou'.tr(),
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 15)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _mode = _LoginMode.email;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _mode == _LoginMode.email
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Email',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _mode == _LoginMode.email
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _mode = _LoginMode.phone;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _mode == _LoginMode.phone
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(AppStrings.phone,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _mode == _LoginMode.phone
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              if (_mode == _LoginMode.email) ...[
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: AppStrings.email,
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: AppColors.textSecondary, size: 20),
                  ),
                ),
              ] else ...[
                Row(children: [
                  GestureDetector(
                    onTap: _showCountryPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
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
                      controller: _phoneCtrl,
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
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: !_showPass,
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push('/forgot-password'),
                  child: Text('authx.forgotPassword'.tr(),
                      style: TextStyle(color: AppColors.primary, fontSize: 13)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
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
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background))
                    : Text(AppStrings.login),
              ),
              const SizedBox(height: 24),
              Row(children: [
                const Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('authx.orContinueWith'.tr(),
                      style:
                          TextStyle(color: AppColors.textHint, fontSize: 12)),
                ),
                Expanded(child: Divider(color: AppColors.border)),
              ]),
              const SizedBox(height: 20),
              _SocialButton(
                icon: Icons.g_mobiledata,
                label: 'authx.googleSignIn'.tr(),
                color: const Color(0xFFDB4437),
                onTap: _loading ? null : _loginWithGoogle,
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => context.push('/register'),
                  child: Text(
                      '${AppStrings.noAccount} ${AppStrings.signUp}'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
