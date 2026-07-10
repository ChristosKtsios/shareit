import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/profile_gate.dart';

/// Υποχρεωτική οθόνη: εμφανίζεται όταν ο χρήστης έχει user document χωρίς
/// `firstName` (παλιά «ghost» docs) και το όνομα ΔΕΝ ανακτάται από το
/// Firebase Auth `displayName`. Χωρίς αυτό, ο χρήστης εμφανιζόταν ως «Χρήστης».
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _error = 'reg.fillName'.tr());
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw FirebaseAuthException(code: 'no-user');

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'firstName': first, 'lastName': last},
        SetOptions(merge: true),
      );

      // Αντίγραφο και στο Auth, ώστε να είναι ανακτήσιμο στο μέλλον.
      try {
        await user.updateDisplayName('$first $last');
      } catch (_) {}

      ProfileGate.invalidate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('completeProfile.saved'.tr()),
          backgroundColor: AppColors.offer,
        ),
      );
      context.go('/map');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${'common.error'.tr()}: $e';
      });
    }
  }

  Future<void> _logout() async {
    ProfileGate.invalidate();
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    // Δεν επιτρέπουμε back — η συμπλήρωση είναι υποχρεωτική.
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('completeProfile.title'.tr()),
          actions: [
            TextButton(
              onPressed: _saving ? null : _logout,
              child: Text('settings.logout'.tr(),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.badge_outlined,
                    color: AppColors.primary, size: 56),
                const SizedBox(height: 20),
                Text(
                  'completeProfile.subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _firstCtrl,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration:
                      InputDecoration(labelText: 'auth.firstName'.tr()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _lastCtrl,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(labelText: 'auth.lastName'.tr()),
                  onSubmitted: (_) => _saving ? null : _save(),
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
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.background))
                      : Text('common.save'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
