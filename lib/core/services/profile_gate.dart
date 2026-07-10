import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'error_logger.dart';

/// Ελέγχει αν ο συνδεδεμένος χρήστης έχει **όνομα** στο user document.
///
/// Ιστορικό: το `FcmService` δημιουργούσε «ghost» docs (μόνο fcmToken/lastSeen)
/// σε κάθε auth event που δεν ολοκλήρωνε profile write, γι' αυτό πολλοί χρήστες
/// εμφανίζονταν ως «Χρήστης». Η ρίζα διορθώθηκε (update-only), αλλά οι
/// υπάρχοντες χρήστες χρειάζονται επιδιόρθωση:
///
/// 1. **Google users** → auto-backfill από `Auth.displayName` (αθόρυβα).
/// 2. **Phone/email users** → δεν υπάρχει ανακτήσιμο όνομα (το `displayName`
///    δεν είχε τεθεί ποτέ) → ο router τους στέλνει στην οθόνη
///    «Ολοκλήρωσε το προφίλ».
class ProfileGate {
  ProfileGate._();

  static String? _cachedUid;
  static bool? _cachedNeeds;

  /// Καθάρισε την cache (π.χ. αφού ο χρήστης συμπληρώσει το προφίλ).
  static void invalidate() {
    _cachedUid = null;
    _cachedNeeds = null;
  }

  /// `true` → πρέπει να δείξουμε την οθόνη «Ολοκλήρωσε το προφίλ».
  ///
  /// Σκόπιμα επιστρέφει `false` όταν **δεν υπάρχει** doc: αυτό σημαίνει είτε
  /// εγγραφή σε εξέλιξη (το doc γράφεται σε λίγο), είτε σφάλμα — δεν θέλουμε
  /// να μπλοκάρουμε τη ροή εγγραφής. Το bug αφορά docs που **υπάρχουν** αλλά
  /// τους λείπει το `firstName`.
  static Future<bool> needsCompletion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    if (_cachedUid == user.uid && _cachedNeeds != null) return _cachedNeeds!;

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await ref.get();

      if (!doc.exists) return _cache(user.uid, false);

      final first = ((doc.data()?['firstName'] as String?) ?? '').trim();
      if (first.isNotEmpty) return _cache(user.uid, false);

      // ── Auto-backfill από Firebase Auth displayName (Google) ──
      final displayName = (user.displayName ?? '').trim();
      if (displayName.isNotEmpty) {
        final parts = displayName.split(RegExp(r'\s+'));
        await ref.set({
          'firstName': parts.first,
          'lastName': parts.length > 1 ? parts.sublist(1).join(' ') : '',
        }, SetOptions(merge: true));
        return _cache(user.uid, false);
      }

      // Δεν ανακτάται → υποχρεωτική συμπλήρωση προφίλ.
      return _cache(user.uid, true);
    } catch (e, s) {
      logSwallowed(e, s, 'ProfileGate.needsCompletion');
      return false; // Σε σφάλμα ΜΗΝ μπλοκάρεις τον χρήστη.
    }
  }

  static bool _cache(String uid, bool needs) {
    _cachedUid = uid;
    _cachedNeeds = needs;
    return needs;
  }
}
