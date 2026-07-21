import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/countries.dart';
import '../../../core/services/profile_gate.dart';
import '../providers/profile_provider.dart';

/// Ασφαλής αλλαγή κινητού:
///   1. **re-authentication** (κωδικός ή Google) — απαιτείται από τη Firebase για
///      sensitive operations, αλλιώς σκάει `requires-recent-login`,
///   2. OTP στο ΝΕΟ νούμερο → `updatePhoneNumber`,
///   3. ενημέρωση Firestore (`phone` + `phoneVerified: true`).
///
/// Με [gateMode] `true` η οθόνη λειτουργεί ως **υποχρεωτική πύλη επαλήθευσης**
/// (πρώτη φορά, π.χ. Google χρήστες που δεν πέρασαν ποτέ από OTP):
///   - **παραλείπεται το re-authentication** — δεν αλλάζει υπάρχον κινητό, το
///     προσθέτει για πρώτη φορά, οπότε δεν υπάρχει τίποτα να προστατευθεί,
///   - δεν επιτρέπεται back· μετά την επιτυχία πάει στον χάρτη.
class ChangePhoneScreen extends ConsumerStatefulWidget {
  final bool gateMode;
  const ChangePhoneScreen({super.key, this.gateMode = false});
  @override
  ConsumerState<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends ConsumerState<ChangePhoneScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String _countryCode = '+30';
  String? _verificationId;
  bool _loading = false;
  bool _codeSent = false;
  String? _error;

  final List<Map<String, String>> _countries = Countries.all;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  /// Έχει ήδη γίνει re-authentication σε αυτή τη ροή;
  bool _reauthenticated = false;

  bool _hasProvider(String id) =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == id) ??
      false;

  /// Ζητά επιβεβαίωση ταυτότητας. `true` = επιτυχία (ή δεν χρειάζεται).
  Future<bool> _reauthenticate() async {
    if (_reauthenticated) return true;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      if (_hasProvider('password')) {
        final password = await _askPassword();
        if (password == null) return false; // ακύρωση χρήστη
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
              email: user.email ?? '', password: password),
        );
      } else if (_hasProvider('google.com')) {
        final googleUser = await GoogleSignIn(
          serverClientId:
              '298536596181-ocikmg46hot2lqma65q54rbm8ibtnsjv.apps.googleusercontent.com',
        ).signIn();
        if (googleUser == null) return false; // ακύρωση χρήστη
        final googleAuth = await googleUser.authentication;
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          ),
        );
      } else {
        // Λογαριασμός μόνο με κινητό — δεν υπάρχει τρόπος re-auth από εδώ.
        // Συνεχίζουμε: αν το login είναι πρόσφατο, το updatePhoneNumber περνά.
        _reauthenticated = true;
        return true;
      }
      _reauthenticated = true;
      return true;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _error = (e.code == 'wrong-password' || e.code == 'invalid-credential')
            ? 'ce.wrongPassword'.tr()
            : 'reauth.failed'.tr();
      });
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _error = 'reauth.failed'.tr();
      });
      return false;
    }
  }

  /// Dialog κωδικού. Επιστρέφει `null` αν ο χρήστης ακυρώσει.
  Future<String?> _askPassword() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _ReauthPasswordDialog(),
    );
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || phone.length < 8) {
      setState(() => _error = 'reg.giveValidPhone'.tr());
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    // Βήμα 0: επιβεβαίωση ταυτότητας πριν από sensitive operation.
    // Σε gateMode παραλείπεται: ο χρήστης ΠΡΟΣΘΕΤΕΙ κινητό για πρώτη φορά (δεν
    // αλλάζει υπάρχον), οπότε δεν υπάρχει τίποτα να προστατευθεί — και το
    // login μόλις έγινε, άρα δεν σκάει `requires-recent-login`.
    if (!widget.gateMode && !await _reauthenticate()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    final fullPhone = '$_countryCode$phone';
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: fullPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (cred) async => _finalize(cred),
      verificationFailed: (e) {
        if (!mounted) return;
        setState(() {
          _error = e.message ?? 'otp.verifyError'.tr();
          _loading = false;
        });
      },
      codeSent: (verificationId, _) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _loading = false;
        });
      },
      codeAutoRetrievalTimeout: (verificationId) =>
          _verificationId = verificationId,
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty || _verificationId == null) {
      setState(() => _error = 'otp.giveOtp'.tr());
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!, smsCode: otp);
    await _finalize(cred);
  }

  Future<void> _finalize(PhoneAuthCredential credential) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw FirebaseAuthException(code: 'no-user');

      // 1) Ενημέρωση του κινητού στο Firebase Auth (re-verification).
      await user.updatePhoneNumber(credential);

      // ΚΡΙΣΙΜΟ: ανανέωσε το ID token ΠΡΙΝ γράψεις το `phoneVerified`.
      // Μετά το updatePhoneNumber, το τρέχον token μπορεί να μην περιέχει
      // ακόμα το claim `phone_number`. Τα Firestore rules θα απαιτούν αυτό το
      // claim για να δεχτούν `phoneVerified: true` — αλλιώς ένας τροποποιημένος
      // client θα δήλωνε «επαληθευμένος» χωρίς ποτέ να λάβει SMS.
      await user.getIdToken(true);

      // 2) Ενημέρωση του Firestore user document.
      // ΣΗΜΑΝΤΙΚΟ: το OTP μόλις απέδειξε την κατοχή του κινητού, οπότε θέτουμε
      // `phoneVerified: true`. Χωρίς αυτό, οι χρήστες (π.χ. Google sign-in που
      // ξεκινούν με phoneVerified:false) έμεναν «Μη επαληθευμένοι» για πάντα.
      final fullPhone = '$_countryCode${_phoneCtrl.text.trim()}';
      // Το ίδιο το κινητό είναι ευαίσθητο → private doc. Στο δημόσιο doc μένουν
      // μόνο οι σημαίες επαλήθευσης (τις δείχνει το προφίλ).
      await ref
          .read(userRepoProvider)
          .updatePrivate(user.uid, {'phone': fullPhone});
      await ref.read(userRepoProvider).update(user.uid, {
        'phoneVerified': true,
        'isVerified': true,
      });

      // Το gate ξεκλείδωσε (phoneVerified: true) → καθάρισε την cache.
      ProfileGate.invalidate();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('cp.updated'.tr()),
            backgroundColor: AppColors.offer,
          ),
        );
        // Σε gateMode δεν υπάρχει προηγούμενη οθόνη για pop.
        if (widget.gateMode) {
          context.go('/map');
        } else {
          context.pop();
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        switch (e.code) {
          case 'invalid-verification-code':
            _error = 'otp.wrongOtp'.tr();
            break;
          case 'credential-already-in-use':
          case 'account-exists-with-different-credential':
            _error = 'cp.phoneInUse'.tr();
            break;
          case 'requires-recent-login':
            _error = 'cp.requiresRecentLogin'.tr();
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

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: _countries
              .map((c) => ListTile(
                    leading:
                        Text(c['flag']!, style: const TextStyle(fontSize: 24)),
                    title: Text(c['name']!,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    trailing: Text(c['code']!,
                        style:
                            const TextStyle(color: AppColors.textSecondary)),
                    onTap: () {
                      setState(() => _countryCode = c['code']!);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gate = widget.gateMode;
    return PopScope(
      // Σε gateMode η επαλήθευση είναι υποχρεωτική → δεν επιτρέπεται back.
      canPop: !gate,
      child: Scaffold(
      appBar: AppBar(
        title: Text(gate ? 'cp.gateTitle'.tr() : 'cp.title'.tr()),
        automaticallyImplyLeading: !gate,
        actions: gate
            ? [
                TextButton(
                  onPressed: _loading
                      ? null
                      : () async {
                          ProfileGate.invalidate();
                          await FirebaseAuth.instance.signOut();
                          if (context.mounted) context.go('/login');
                        },
                  child: Text('settings.logout'.tr(),
                      style:
                          const TextStyle(color: AppColors.textSecondary)),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                _codeSent
                    ? 'cp.enterCode'.tr()
                    : (gate ? 'cp.gateIntro'.tr() : 'cp.enterNewPhone'.tr()),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              if (!_codeSent) ...[
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
                      decoration: const InputDecoration(hintText: '6901234567'),
                    ),
                  ),
                ]),
              ] else ...[
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                      hintText: '------', counterText: ''),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _loading ? null : (_codeSent ? _verifyOtp : _sendOtp),
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
                      : Text(_codeSent ? 'common.confirm'.tr() : 'otp.sendCode'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Dialog επανεπαλήθευσης με κωδικό — ξεχωριστό StatefulWidget ώστε ο
/// TextEditingController να ζει ΜΕΣΑ στο dialog. Αν ζούσε έξω (και γινόταν
/// dispose σε finally μόλις επέστρεφε το showDialog), το TextField έπεφτε πάνω
/// σε disposed controller κατά το exit animation → framework assertion.
class _ReauthPasswordDialog extends StatefulWidget {
  const _ReauthPasswordDialog();

  @override
  State<_ReauthPasswordDialog> createState() => _ReauthPasswordDialogState();
}

class _ReauthPasswordDialogState extends State<_ReauthPasswordDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('reauth.title'.tr(),
          style: const TextStyle(color: AppColors.textPrimary)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('reauth.body'.tr(),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 14),
        TextField(
          controller: _ctrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(labelText: 'ce.currentPassword'.tr()),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text('reauth.confirm'.tr(),
              style: const TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}
