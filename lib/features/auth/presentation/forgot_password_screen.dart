import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../data/auth_repository.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Method { email, phone }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;
  _Method _method = _Method.email;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_method == _Method.email) {
        final email = _emailCtrl.text.trim();
        if (email.isEmpty) {
          setState(() {
            _loading = false;
            _error = 'authx.fillEmail'.tr();
          });
          return;
        }
        if (!AuthRepository.isValidEmail(email)) {
          setState(() {
            _loading = false;
            _error = 'authx.invalidEmail'.tr();
          });
          return;
        }
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (mounted) setState(() => _sent = true);
      } else {
        // Phone method: αναζητούμε email από Firestore με βάση το phone
        var phone = _phoneCtrl.text.trim();
        if (phone.isEmpty) {
          setState(() {
            _loading = false;
            _error = 'fp.fillPhone'.tr();
          });
          return;
        }
        // Auto +30 αν δεν αρχίζει με +
        if (!phone.startsWith('+')) phone = '+30$phone';

        // Το email βρίσκεται server-side (Cloud Function με admin) — δεν
        // μπορούμε να κάνουμε query στους users χωρίς σύνδεση.
        final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('getEmailByPhone')
            .call({'phone': phone});
        final data = Map<String, dynamic>.from(res.data as Map);
        final email = data['email'] as String?;
        final accountExists = data['accountExists'] == true;

        if (email == null || email.isEmpty) {
          setState(() {
            _loading = false;
            // Ξεχωρίζουμε "δεν υπάρχει" από "υπάρχει αλλά ημιτελής (half-account)".
            _error = accountExists
                ? 'fp.accountIncomplete'.tr()
                : 'fp.noAccountPhone'.tr();
          });
          return;
        }

        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (mounted) setState(() => _sent = true);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _error = 'fp.noAccountCreds'.tr();
            break;
          case 'invalid-email':
            _error = 'authx.invalidEmail'.tr();
            break;
          case 'too-many-requests':
            _error = 'otp.tooManyTries'.tr();
            break;
          case 'network-request-failed':
            _error = 'authx.networkError'.tr();
            break;
          default:
            _error = e.message ?? 'fp.somethingWrong'.tr();
        }
      });
    } catch (_) {
      setState(() => _error = 'common.errorGeneric'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('authx.forgotPassword'.tr()),
        backgroundColor: AppColors.background,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              if (!_sent) ...[
                Text(
                  'fp.chooseMethod'.tr(),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                // Toggle Email / Phone
                Row(children: [
                  Expanded(
                    child: _MethodChip(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      selected: _method == _Method.email,
                      onTap: () => setState(() => _method = _Method.email),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MethodChip(
                      icon: Icons.phone_outlined,
                      label: 'fp.phone'.tr(),
                      selected: _method == _Method.phone,
                      onTap: () => setState(() => _method = _Method.phone),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                // Input field
                if (_method == _Method.email)
                  TextField(
                    controller: _emailCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle:
                          const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.email_outlined,
                          color: AppColors.textHint),
                    ),
                  )
                else
                  TextField(
                    controller: _phoneCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'fp.phone'.tr(),
                      hintText: '6912345678',
                      labelStyle:
                          const TextStyle(color: AppColors.textSecondary),
                      hintStyle: const TextStyle(color: AppColors.textHint),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.phone_outlined,
                          color: AppColors.textHint),
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
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: AppColors.background, strokeWidth: 2))
                        : Text('fp.send'.tr(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ] else ...[
                // Success state
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.offer.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.offer.withValues(alpha: 0.4)),
                  ),
                  child: Column(children: [
                    const Icon(Icons.mark_email_read_outlined,
                        color: AppColors.offer, size: 48),
                    const SizedBox(height: 12),
                    Text('fp.emailSent'.tr(),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      'fp.checkInbox'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text('fp.backToLogin'.tr(),
                          style: const TextStyle(color: AppColors.primary)),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MethodChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color:
                    selected ? AppColors.background : AppColors.textSecondary,
                size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color:
                        selected ? AppColors.background : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
