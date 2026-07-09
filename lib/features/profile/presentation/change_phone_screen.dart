import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/countries.dart';
import '../providers/profile_provider.dart';

/// Ασφαλής αλλαγή κινητού: στέλνει OTP στο ΝΕΟ νούμερο, το επαληθεύει και
/// ενημερώνει Firebase Auth (updatePhoneNumber) + το Firestore user document.
class ChangePhoneScreen extends ConsumerStatefulWidget {
  const ChangePhoneScreen({super.key});
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

      // 2) Ενημέρωση του Firestore user document.
      final fullPhone = '$_countryCode${_phoneCtrl.text.trim()}';
      await ref.read(userRepoProvider).update(user.uid, {'phone': fullPhone});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('cp.updated'.tr()),
            backgroundColor: AppColors.offer,
          ),
        );
        context.pop();
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
      builder: (_) => ListView(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('cp.title'.tr())),
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
                    : 'cp.enterNewPhone'.tr(),
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
    );
  }
}
