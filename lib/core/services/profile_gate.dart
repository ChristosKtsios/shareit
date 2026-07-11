import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'error_logger.dart';

/// Τι πρέπει να ολοκληρώσει ο χρήστης πριν χρησιμοποιήσει την εφαρμογή.
enum ProfileGateStep {
  /// Όλα εντάξει — ελεύθερη πλοήγηση.
  none,

  /// Λείπει όνομα → οθόνη «Ολοκλήρωσε το προφίλ».
  completeProfile,

  /// Δεν έχει επαληθευμένο κινητό (OTP) → οθόνη επαλήθευσης κινητού.
  verifyPhone,
}

/// Έλεγχος πληρότητας/επαλήθευσης λογαριασμού πριν την είσοδο στην εφαρμογή.
///
/// **1. Όνομα.** Το `FcmService` δημιουργούσε «ghost» docs (μόνο fcmToken) σε
/// κάθε auth event χωρίς ολοκληρωμένο profile write → χρήστες ως «Χρήστης».
/// Η ρίζα διορθώθηκε (update-only), αλλά οι υπάρχοντες θέλουν επιδιόρθωση:
/// Google → auto-backfill από `displayName`· αλλιώς → «Ολοκλήρωσε το προφίλ».
///
/// **2. Επαληθευμένο κινητό.** Η εγγραφή με email απαιτεί OTP, το Google
/// sign-in ΟΧΙ — οπότε κάποιος έφτιαχνε ψεύτικο προφίλ σε δευτερόλεπτα, χωρίς
/// κανένα κινητό. Τώρα **όλοι** περνούν από OTP.
class ProfileGate {
  ProfileGate._();

  static String? _cachedUid;
  static ProfileGateStep? _cachedStep;

  /// Καθάρισε την cache (μετά από συμπλήρωση προφίλ / επαλήθευση κινητού).
  static void invalidate() {
    _cachedUid = null;
    _cachedStep = null;
  }

  /// Το επόμενο υποχρεωτικό βήμα για τον τρέχοντα χρήστη.
  ///
  /// Σκόπιμα επιστρέφει [ProfileGateStep.none] όταν **δεν υπάρχει** doc: αυτό
  /// σημαίνει εγγραφή σε εξέλιξη (το doc γράφεται σε λίγο) — δεν μπλοκάρουμε τη
  /// ροή εγγραφής. Το ίδιο και σε σφάλμα: ποτέ δεν κλειδώνουμε τον χρήστη έξω.
  static Future<ProfileGateStep> nextStep() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return ProfileGateStep.none;

    if (_cachedUid == user.uid && _cachedStep != null) return _cachedStep!;

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await ref.get();

      // Εγγραφή/Google sign-in σε εξέλιξη → μην μπλοκάρεις.
      //
      // ΠΡΟΣΟΧΗ: ΔΕΝ κάνουμε cache εδώ. Το doc γράφεται λίγα ms αργότερα, και αν
      // αποθηκεύαμε `none` θα παρακάμπτονταν μόνιμα η πύλη (π.χ. ο Google
      // χρήστης δεν θα καλούνταν ποτέ να επαληθεύσει κινητό).
      if (!doc.exists) return ProfileGateStep.none;

      final data = doc.data() ?? {};

      // ── 1) Όνομα ──
      var first = ((data['firstName'] as String?) ?? '').trim();
      if (first.isEmpty) {
        // Auto-backfill από Firebase Auth displayName (Google).
        final displayName = (user.displayName ?? '').trim();
        if (displayName.isNotEmpty) {
          final parts = displayName.split(RegExp(r'\s+'));
          await ref.set({
            'firstName': parts.first,
            'lastName': parts.length > 1 ? parts.sublist(1).join(' ') : '',
          }, SetOptions(merge: true));
          first = parts.first;
        } else {
          return _cache(user.uid, ProfileGateStep.completeProfile);
        }
      }

      // ── 2) Επαληθευμένο κινητό (OTP) ──
      final phoneVerified = (data['phoneVerified'] as bool?) ?? false;
      if (!phoneVerified) {
        return _cache(user.uid, ProfileGateStep.verifyPhone);
      }

      return _cache(user.uid, ProfileGateStep.none);
    } catch (e, s) {
      logSwallowed(e, s, 'ProfileGate.nextStep');
      return ProfileGateStep.none; // Σε σφάλμα ΜΗΝ μπλοκάρεις τον χρήστη.
    }
  }

  static ProfileGateStep _cache(String uid, ProfileGateStep step) {
    _cachedUid = uid;
    _cachedStep = step;
    return step;
  }
}
