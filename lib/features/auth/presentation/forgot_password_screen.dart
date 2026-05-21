import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();

    // Validation
    if (email.isEmpty) {
      setState(() => _error = 'Συμπλήρωσε το email σου.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Μη έγκυρη μορφή email.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _error = 'Δεν υπάρχει λογαριασμός με αυτό το email.';
            break;
          case 'invalid-email':
            _error = 'Μη έγκυρη μορφή email.';
            break;
          case 'too-many-requests':
            _error = 'Πολλές προσπάθειες. Δοκίμασε αργότερα.';
            break;
          case 'network-request-failed':
            _error = 'Πρόβλημα σύνδεσης. Έλεγξε το internet.';
            break;
          default:
            _error = e.message ?? 'Κάτι πήγε στραβά.';
        }
      });
    } catch (_) {
      setState(() => _error = 'Κάτι πήγε στραβά. Δοκίμασε ξανά.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ξέχασα τον κωδικό')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _sent
              ? _SuccessView(email: _emailCtrl.text.trim())
              : _FormView(
                  emailCtrl: _emailCtrl,
                  loading: _loading,
                  error: _error,
                  onSend: _send,
                ),
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  final TextEditingController emailCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSend;

  const _FormView({
    required this.emailCtrl,
    required this.loading,
    required this.error,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Text('Επαναφορά κωδικού',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
            'Γράψε το email σου και θα σου στείλουμε σύνδεσμο για να αλλάξεις τον κωδικό σου.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        const SizedBox(height: 32),
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Email',
            prefixIcon: Icon(Icons.email_outlined,
                color: AppColors.textSecondary, size: 20),
          ),
        ),
        if (error != null) ...[
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
                  child: Text(error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: loading ? null : onSend,
          child: loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.background))
              : const Text('Αποστολή συνδέσμου'),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String email;
  const _SuccessView({required this.email});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.offer.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mark_email_read_outlined,
              color: AppColors.offer, size: 40),
        ),
        const SizedBox(height: 24),
        const Text('Email στάλθηκε!',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
            'Έλεγξε το inbox του $email και ακολούθησε τον σύνδεσμο για να αλλάξεις τον κωδικό σου.',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
            'Αν δεν εμφανιστεί στα Εισερχόμενα, έλεγξε και τον φάκελο Ανεπιθύμητα.',
            style:
                TextStyle(color: AppColors.textHint, fontSize: 12, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => context.pop(),
          child: const Text('Πίσω στη σύνδεση'),
        ),
      ],
    );
  }
}
