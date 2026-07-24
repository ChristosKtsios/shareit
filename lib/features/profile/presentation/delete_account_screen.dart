import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _agreed = false;

  String get _confirmWord => 'delacc.confirmWord'.tr();

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Προειδοποίηση (ΟΧΙ φραγμός) αν υπάρχουν ενεργά/εκκρεμή deals.
  ///
  /// Η διαγραφή λογαριασμού ΔΕΝ μπλοκάρεται ποτέ: το Google Play απαιτεί ο
  /// χρήστης να μπορεί πάντα να διαγράψει τον λογαριασμό του. Παλιότερα
  /// μπλοκάραμε και όταν έλειπε αξιολόγηση — που σήμαινε ότι, αν ο ΑΛΛΟΣ δεν σε
  /// βαθμολογούσε ποτέ, δεν μπορούσες να διαγραφείς ποτέ.
  Future<String?> _activeDealsWarning(String uid) async {
    try {
      // `participants` (όχι user1Uid/user2Uid): τα rules επιτρέπουν ανάγνωση
      // deal μόνο στους συμμετέχοντες και το query πρέπει να το δηλώνει.
      final snap = await FirebaseFirestore.instance
          .collection('deals')
          .where('participants', arrayContains: uid)
          .get();

      final activeCount = snap.docs.where((d) {
        final status = d.data()['status'] as String?;
        return status == 'pending' || status == 'active';
      }).length;

      if (activeCount > 0) {
        return 'delacc.activeDealsWarn'.tr(namedArgs: {'n': '$activeCount'});
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Δείχνει την προειδοποίηση για ενεργά deals και επιστρέφει αν ο χρήστης
  /// θέλει να συνεχίσει παρόλα αυτά.
  Future<bool> _confirmDespiteActiveDeals(String warning) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('delacc.warning'.tr(),
            style: const TextStyle(
                color: AppColors.danger, fontWeight: FontWeight.w700)),
        content: Text(warning,
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('delacc.continueAnyway'.tr(),
                style: const TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool> _showConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('delacc.confirmDeleteTitle'.tr(),
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'delacc.confirmDeleteBody'.tr(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('delacc.yesDelete'.tr(),
                style: const TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteAccount() async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loading = true);

    // 1. Ενεργά deals → ΠΡΟΕΙΔΟΠΟΙΗΣΗ, όχι φραγμός. Ο χρήστης αποφασίζει.
    final warning = await _activeDealsWarning(uid);
    if (warning != null) {
      if (!mounted) return;
      setState(() => _loading = false);
      final proceed = await _confirmDespiteActiveDeals(warning);
      if (!proceed) return;
      if (!mounted) return;
      setState(() => _loading = true);
    }

    // 2. Επιβεβαίωση
    final confirmed = await _showConfirmDialog();
    if (!confirmed) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // 3. Cloud Function call
    //
    // ΠΡΟΣΟΧΗ: ΠΟΤΕ μη δηλώσεις επιτυχία αν δεν επιβεβαιώθηκε από τον server.
    // Παλιότερα κάθε σφάλμα (δίκτυο, λάθος region, App Check) το θεωρούσαμε
    // «επιτυχία»: ο χρήστης έβλεπε «ο λογαριασμός σου διαγράφηκε», αποσυνδεόταν
    // — και ο λογαριασμός με όλα του τα δεδομένα υπήρχε ακόμα. Ψευδής
    // επιβεβαίωση διαγραφής είναι και παραβίαση GDPR και του Play.
    bool deletionSucceeded = false;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('deleteUserAccount');
      await callable.call();
      deletionSucceeded = true;
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('delacc.failed'.tr()),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    if (deletionSucceeded) {
      // Καθάρισε ΚΑΙ το Google session (disconnect → θα ξαναζητηθεί λογαριασμός).
      // Χωρίς αυτό, μια αμέσως επόμενη «Σύνδεση με Google» έβρισκε την cached
      // κατάσταση του μόλις διαγραμμένου λογαριασμού: flash στον χάρτη και
      // επιστροφή στο login αντί για τη φόρμα ονόματος/όρων.
      try {
        await GoogleSignIn().disconnect();
      } catch (_) {
        try {
          await GoogleSignIn().signOut();
        } catch (_) {}
      }
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('delacc.deleted'.tr()),
          backgroundColor: AppColors.offer,
          duration: const Duration(seconds: 2),
        ),
      );

      // Πήγαινε στη σύνδεση (ΟΧΙ SystemNavigator.pop που κλείνει την εφαρμογή).
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete =
        _agreed && _confirmCtrl.text.trim().toUpperCase() == _confirmWord;

    return Scaffold(
      appBar: AppBar(title: Text('settings.deleteAccount'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.4), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.danger, size: 22),
                      const SizedBox(width: 8),
                      Text('delacc.warning'.tr(),
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'delacc.warningBodyLong'.tr(),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('delacc.whatDeleted'.tr(),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _DeleteItem('delacc.item1'.tr()),
              _DeleteItem('delacc.item2'.tr()),
              _DeleteItem('delacc.item3'.tr()),
              _DeleteItem('delacc.item4'.tr()),
              _DeleteItem('delacc.item5'.tr()),
              _DeleteItem('delacc.item6'.tr()),
              const SizedBox(height: 24),
              Row(children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  activeColor: AppColors.danger,
                ),
                Expanded(
                  child: Text(
                    'delacc.understand'.tr(),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              Text(
                'delacc.typeToConfirm'.tr(namedArgs: {'word': _confirmWord}),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: _confirmWord,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: canDelete && !_loading ? _deleteAccount : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.surfaceVariant,
                  disabledForegroundColor: AppColors.textHint,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('settings.deleteAccount'.tr(),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => context.pop(),
                  child: Text('common.cancel'.tr(),
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteItem extends StatelessWidget {
  final String text;
  const _DeleteItem(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Icon(Icons.close, color: AppColors.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
        ]),
      );
}
