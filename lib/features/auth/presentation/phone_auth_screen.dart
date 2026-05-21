import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  /// Optional extra data when coming from RegisterScreen.
  /// Expected keys: mode, firstName, lastName, email, phone, password, profilePhotoPath
  final Map<String, dynamic>? registerData;

  const PhoneAuthScreen({super.key, this.registerData});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String _countryCode = '+30';
  String? _verificationId;
  bool _loading = false;
  bool _codeSent = false;
  String? _error;

  bool get _isRegisterMode => widget.registerData?['mode'] == 'register';
  String get _registerPhone => widget.registerData?['phone'] ?? '';

  final List<Map<String, String>> _countries = [
    {'code': '+30', 'flag': '🇬🇷', 'name': 'Ελλάδα'},
    {'code': '+357', 'flag': '🇨🇾', 'name': 'Κύπρος'},
    {'code': '+46', 'flag': '🇸🇪', 'name': 'Σουηδία'},
    {'code': '+47', 'flag': '🇳🇴', 'name': 'Νορβηγία'},
    {'code': '+45', 'flag': '🇩🇰', 'name': 'Δανία'},
    {'code': '+358', 'flag': '🇫🇮', 'name': 'Φινλανδία'},
    {'code': '+49', 'flag': '🇩🇪', 'name': 'Γερμανία'},
    {'code': '+33', 'flag': '🇫🇷', 'name': 'Γαλλία'},
    {'code': '+39', 'flag': '🇮🇹', 'name': 'Ιταλία'},
    {'code': '+34', 'flag': '🇪🇸', 'name': 'Ισπανία'},
    {'code': '+31', 'flag': '🇳🇱', 'name': 'Ολλανδία'},
    {'code': '+44', 'flag': '🇬🇧', 'name': 'Ηνωμένο Βασίλειο'},
    {'code': '+1', 'flag': '🇺🇸', 'name': 'ΗΠΑ'},
  ];

  @override
  void initState() {
    super.initState();
    // Αν είμαστε σε register mode, στείλε αυτόματα OTP στο κινητό που έχουμε ήδη
    if (_isRegisterMode && _registerPhone.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendOtpToPhone(_registerPhone);
      });
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtpToPhone(String fullPhone) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: fullPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-verification (Android only, σπάνια)
        await _finalizeAuth(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() {
          _error = _mapAuthError(e);
          _loading = false;
          _codeSent = false;
        });
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _loading = false;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  /// Όταν ο χρήστης πατήσει "Αποστολή κωδικού" σε standalone phone-only mode
  Future<void> _sendOtpFromForm() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Δώσε αριθμό κινητού.');
      return;
    }
    final fullPhone = '$_countryCode$phone';
    await _sendOtpToPhone(fullPhone);
  }

  /// Επιβεβαίωση OTP — Καταχωρεί ή απλά συνδέει
  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty || _verificationId == null) {
      setState(() => _error = 'Δώσε τον κωδικό OTP.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      await _finalizeAuth(credential);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = _mapAuthError(e);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Σφάλμα: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _finalizeAuth(PhoneAuthCredential credential) async {
    if (_isRegisterMode) {
      // === REGISTER MODE ===
      // 1) Πρώτα κάνε sign-in με το phone credential για να επιβεβαιώσουμε ότι το OTP είναι σωστό
      await FirebaseAuth.instance.signInWithCredential(credential);

      // 2) Αμέσως κάνε sign-out (γιατί θα δημιουργήσουμε λογαριασμό με email/password)
      await FirebaseAuth.instance.signOut();

      // 3) Τώρα δημιούργησε τον πραγματικό λογαριασμό με όλα τα στοιχεία
      final data = widget.registerData!;
      final photoPath = data['profilePhotoPath'] as String?;

      try {
        await ref.read(authRepoProvider).registerWithPhoneVerified(
              email: data['email'],
              password: data['password'],
              firstName: data['firstName'],
              lastName: data['lastName'],
              phone: data['phone'],
              profilePhoto: photoPath != null ? File(photoPath) : null,
            );

        if (mounted) context.go('/map');
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        setState(() {
          _error = _mapAuthError(e);
          _loading = false;
        });
      }
    } else {
      // === STANDALONE PHONE LOGIN MODE ===
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) context.go('/map');
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'Λάθος κωδικός OTP. Δοκίμασε ξανά.';
      case 'invalid-verification-id':
      case 'session-expired':
        return 'Ο κωδικός OTP έληξε. Στείλε ξανά κωδικό.';
      case 'invalid-phone-number':
        return 'Μη έγκυρος αριθμός κινητού.';
      case 'too-many-requests':
        return 'Πολλές προσπάθειες. Δοκίμασε αργότερα.';
      case 'email-already-in-use':
        return 'Υπάρχει ήδη λογαριασμός με αυτό το email.';
      case 'quota-exceeded':
        return 'Υπερβήκαμε το ημερήσιο όριο SMS. Δοκίμασε αύριο.';
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return 'Πρόβλημα ρύθμισης app. Επικοινώνησε με τον διαχειριστή.';
      default:
        return e.message ?? 'Σφάλμα επαλήθευσης.';
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
      appBar: AppBar(
        title:
            Text(_isRegisterMode ? 'Επιβεβαίωση κινητού' : 'Σύνδεση με κινητό'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Text(
                _isRegisterMode
                    ? 'Σχεδόν τελειώσαμε!'
                    : (_codeSent
                        ? 'Εισάγαγε τον κωδικό OTP'
                        : 'Εισάγαγε τον αριθμό κινητού σου'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _isRegisterMode
                    ? 'Στείλαμε κωδικό 6 ψηφίων στο $_registerPhone.\nΒάλε τον για να επιβεβαιώσουμε το κινητό σου.'
                    : (_codeSent
                        ? 'Στείλαμε κωδικό 6 ψηφίων στο $_countryCode ${_phoneCtrl.text}'
                        : 'Θα σου στείλουμε κωδικό επαλήθευσης SMS.'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),

              // === REGISTER MODE: μόνο OTP field ===
              if (_isRegisterMode) ...[
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: '------',
                    counterText: '',
                  ),
                ),
              ]
              // === STANDALONE MODE: phone field ή OTP field ανάλογα με στάδιο ===
              else if (!_codeSent) ...[
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
              ] else ...[
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: '------',
                    counterText: '',
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 8),
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
                              color: AppColors.danger, fontSize: 13)),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _loading
                    ? null
                    : (_isRegisterMode || _codeSent
                        ? _verifyOtp
                        : _sendOtpFromForm),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background))
                    : Text(_isRegisterMode || _codeSent
                        ? 'Επαλήθευση & Δημιουργία λογαριασμού'
                        : 'Αποστολή κωδικού'),
              ),

              // Resend OTP button (only when code already sent)
              if ((_isRegisterMode || _codeSent) && !_loading) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () {
                      _otpCtrl.clear();
                      setState(() => _error = null);
                      _sendOtpToPhone(_isRegisterMode
                          ? _registerPhone
                          : '$_countryCode${_phoneCtrl.text}');
                    },
                    child: const Text('Ξαναστείλε κωδικό',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ),
                ),
              ],

              if (_codeSent && !_isRegisterMode) ...[
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _codeSent = false;
                      _otpCtrl.clear();
                      _error = null;
                    }),
                    child: const Text('Αλλαγή αριθμού',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
