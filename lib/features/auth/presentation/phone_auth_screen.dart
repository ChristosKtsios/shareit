import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/countries.dart';
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

  final List<Map<String, String>> _countries = Countries.all;

  @override
  void initState() {
    super.initState();
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

  Future<void> _sendOtpFromForm() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'otp.givePhone'.tr());
      return;
    }
    final fullPhone = '$_countryCode$phone';
    await _sendOtpToPhone(fullPhone);
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

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      await _finalizeAuth(credential);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapAuthError(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${'common.error'.tr()}: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _finalizeAuth(PhoneAuthCredential credential) async {
    if (_isRegisterMode) {
      // === REGISTER MODE ===
      final data = widget.registerData!;
      final photoPath = data['profilePhotoPath'] as String?;

      // ΚΡΙΣΙΜΟ: κράτα το repo ΠΡΙΝ το sign-in. Μόλις γίνει signInWithCredential,
      // ο χρήστης γίνεται logged-in και το router redirect μας πλοηγεί στο /map,
      // κάνοντας dispose αυτό το widget. Αν διαβάζαμε το ref ΜΕΤΑ, θα ήταν άκυρο
      // και το link email/password + το προφίλ ΔΕΝ θα γράφονταν — αφήνοντας
      // λογαριασμό phone-only (το email login θα αποτύγχανε).
      final authRepo = ref.read(authRepoProvider);

      // 1) Sign-in με phone credential — ο user μένει συνδεδεμένος
      await FirebaseAuth.instance.signInWithCredential(credential);

      try {
        // 2) Link email/password + δημιουργία Firestore document
        await authRepo.registerWithPhoneVerified(
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
        // Αν αποτύχει το link, κάνε signOut για να μην μείνει στον αέρα
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = '${'common.error'.tr()}: ${e.toString()}';
          _loading = false;
        });
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
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
        return 'otp.wrongOtp'.tr();
      case 'invalid-verification-id':
      case 'session-expired':
        return 'otp.otpExpired'.tr();
      case 'invalid-phone-number':
        return 'otp.invalidPhone'.tr();
      case 'too-many-requests':
        return 'otp.tooManyTries'.tr();
      case 'email-already-in-use':
      case 'credential-already-in-use':
        return 'reg.emailExists'.tr();
      case 'phone-already-in-use':
        return 'reg.phoneExists'.tr();
      case 'quota-exceeded':
        return 'otp.smsQuota'.tr();
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return 'otp.appConfig'.tr();
      default:
        return e.message ?? 'otp.verifyError'.tr();
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
            Text(_isRegisterMode
                ? 'otp.confirmPhone'.tr()
                : 'otp.phoneLogin'.tr()),
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
                    ? 'otp.almostDone'.tr()
                    : (_codeSent
                        ? 'otp.enterOtp'.tr()
                        : 'otp.enterPhone'.tr()),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _isRegisterMode
                    ? 'otp.sentToRegister'
                        .tr(namedArgs: {'phone': _registerPhone})
                    : (_codeSent
                        ? 'otp.sentTo'.tr(namedArgs: {
                            'phone': '$_countryCode ${_phoneCtrl.text}'
                          })
                        : 'otp.willSend'.tr()),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
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
              ] else if (!_codeSent) ...[
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
                        ? 'otp.verifyAndCreate'.tr()
                        : 'otp.sendCode'.tr()),
              ),
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
                    child: Text('otp.resendCode'.tr(),
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
                    child: Text('otp.changeNumber'.tr(),
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
