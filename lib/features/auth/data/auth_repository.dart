import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/fcm_service.dart';
import '../../profile/data/user_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Ένας κανόνας κωδικού + αν ικανοποιείται. Κοινό μοντέλο για τη λίστα τικ
/// και τον validator (μία πηγή αλήθειας).
class PasswordRule {
  final String label;
  final bool met;
  const PasswordRule(this.label, this.met);
}

class AuthRepository {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ============================================================
  // PASSWORD VALIDATION
  // ============================================================
  // ============================================================
  // ΜΙΑ ΠΗΓΗ ΑΛΗΘΕΙΑΣ για τους κανόνες κωδικού — χρησιμοποιείται ΚΑΙ από τη
  // λίστα με τα τικ (PasswordStrengthIndicator) ΚΑΙ από τον validator/κουμπί.
  // Κανόνες: 8+ χαρακτήρες, 1 κεφαλαίο (A-Z), 1 αριθμός (0-9), 1 σύμβολο.
  // (ΔΕΝ απαιτείται πεζό.)
  // ============================================================
  static const int passwordMinLength = 8;
  static bool _hasUpper(String p) => RegExp(r'[A-Z]').hasMatch(p);
  static bool _hasDigit(String p) => RegExp(r'[0-9]').hasMatch(p);
  static final RegExp _symbolRegex =
      RegExp(r"""[!@#$%^&*(),.?":{}|<>_+=/\[\]~`;'-]""");
  static bool _hasSymbol(String p) => _symbolRegex.hasMatch(p);

  static List<PasswordRule> passwordRules(String password) {
    final p = password.trim();
    return [
      PasswordRule('pwrule.min8'.tr(), p.length >= passwordMinLength),
      PasswordRule('pwrule.upper'.tr(), _hasUpper(p)),
      PasswordRule('pwrule.digit'.tr(), _hasDigit(p)),
      PasswordRule('pwrule.symbol'.tr(), _hasSymbol(p)),
    ];
  }

  static String? validatePassword(String password) {
    for (final r in passwordRules(password)) {
      if (!r.met) return 'pwrule.needs'.tr(namedArgs: {'label': r.label});
    }
    return null;
  }

  // ============================================================
  // EMAIL VALIDATION — κοινό για login/register/forgot-password ώστε να μη
  // διαφέρουν οι κανόνες μεταξύ οθονών.
  // ============================================================
  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool isValidEmail(String email) => _emailRegex.hasMatch(email.trim());

  // ============================================================
  // LOGIN METHODS
  // ============================================================

  Future<void> loginWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> loginWithPhone(String phone, String password) async {
    // Το email βρίσκεται server-side (Cloud Function με admin) — δεν μπορούμε
    // να κάνουμε query στους users πριν συνδεθεί ο χρήστης.
    final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('getEmailByPhone')
        .call({'phone': phone.trim()});
    final email = (res.data as Map)['email'] as String?;

    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'authx.noAccountPhone'.tr(),
      );
    }

    await loginWithEmail(email, password);
  }

  // ============================================================
  // REGISTER METHODS
  // ============================================================

  // Ο έλεγχος «υπάρχει ήδη λογαριασμός με αυτό το κινητό;» γίνεται ΜΟΝΟ από το
  // Cloud Function `checkAccountExists` (Firebase Auth admin). Δεν κάνουμε
  // query στους users με `phone` — τα τηλέφωνα δεν είναι πια αναγνώσιμα.

  /// ΝΕΑ ΡΟΗ — Διορθωμένη:
  /// 1) ΠΡΩΤΑ γράφει user document με όνομα/επώνυμο (πιο σημαντικό)
  /// 2) ΜΕΤΑ link email/password
  /// 3) ΤΕΛΕΥΤΑΙΟ upload φωτογραφίας
  /// Αν σπάσει κάτι μετά το βήμα 1, ο χρήστης έχει τουλάχιστον προφίλ.
  Future<void> registerWithPhoneVerified({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    File? profilePhoto,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'authx.noActiveUser'.tr(),
      );
    }

    final uid = user.uid;

    // ============================================================
    // ΒΗΜΑ 0: ΠΛΗΡΗΣ ή HALF-ACCOUNT;
    // Ενιαίος ορισμός "πλήρους" λογαριασμού = υπάρχει user document ΚΑΙ
    // email/password provider. Μπλοκάρουμε ΜΟΝΟ αν είναι πραγματικά πλήρης.
    // Αν είναι half-account (doc χωρίς password provider, από παλιό race),
    // ΣΥΝΕΧΙΖΟΥΜΕ ώστε να το ΕΠΙΣΚΕΥΑΣΟΥΜΕ (link email + ενημέρωση doc) —
    // ΧΩΡΙΣ διαγραφή δεδομένων.
    // ============================================================
    final existingDoc = await _db.collection('users').doc(uid).get();
    final hadDocBefore = existingDoc.exists;
    final hasPasswordProvider =
        user.providerData.any((p) => p.providerId == 'password');

    if (hadDocBefore && hasPasswordProvider) {
      throw FirebaseAuthException(
        code: 'phone-already-in-use',
        message: 'reg.phoneExists'.tr(),
      );
    }

    // ============================================================
    // ΒΗΜΑ 1: LINK EMAIL/PASSWORD (και repair για half-accounts)
    // ============================================================
    try {
      final emailCredential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );
      await user.linkWithCredential(emailCredential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        // Το email ανήκει σε ΑΛΛΟΝ λογαριασμό. ΔΕΝ σβήνουμε δεδομένα χρήστη:
        // διαγράφουμε ΜΟΝΟ αν αυτός είναι κενός phone-only που μόλις
        // δημιουργήθηκε (δεν είχε προφίλ). Σε repair (υπήρχε doc) δεν αγγίζουμε
        // τίποτα — απλώς επιστρέφουμε σφάλμα.
        if (!hadDocBefore) {
          try {
            await user.delete();
          } catch (_) {}
        }
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'reg.emailExists'.tr(),
        );
      }
      // 'provider-already-linked' → το email είναι ήδη συνδεδεμένο σε ΑΥΤΟΝ τον
      // λογαριασμό· συνεχίζουμε. Οτιδήποτε άλλο (πχ network) το προωθούμε.
      if (e.code != 'provider-already-linked') rethrow;
    }

    // ============================================================
    // ΒΗΜΑ 2: ΓΡΑΨΕ/ΕΠΙΣΚΕΥΑΣΕ ΤΟ USER DOCUMENT
    // Σε repair (υπήρχε ήδη doc) ενημερώνουμε ΜΟΝΟ τα βασικά πεδία και ΔΕΝ
    // μηδενίζουμε τυχόν υπάρχοντα δεδομένα (friends, ratings, saved listings...).
    // ============================================================
    // ΠΡΟΣΟΧΗ: email/phone ΔΕΝ μπαίνουν εδώ — το δημόσιο user doc το διαβάζει
    // κάθε συνδεδεμένος χρήστης (search, inbox, αγγελίες). Πάνε στο private doc.
    final docData = <String, dynamic>{
      'uid': uid,
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'isVerified': true,
      'phoneVerified': true,
    };
    if (!hadDocBefore) {
      // Defaults ΜΟΝΟ για νέο λογαριασμό.
      docData.addAll({
        'rating': 0.0,
        'ratingCount': 0,
        'blockedUids': [],
        'savedListingIds': [],
        'friends': [],
        'dealsCount': 0,
        'isPrivateProfile': false,
        'showOnlineStatus': true,
        // Η οθόνη εγγραφής δεν επιτρέπει να προχωρήσεις χωρίς αποδοχή 18+ & όρων,
        // οπότε τα καταγράφουμε (νομικό/GDPR — όπως και στο Google sign-in).
        'ageVerified': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await _db.collection('users').doc(uid).set(docData, SetOptions(merge: true));

    // Ευαίσθητα δεδομένα → private doc (μόνο ο ίδιος + οι Cloud Functions).
    await UserRepository.privateRef(uid).set({
      'email': email.trim(),
      'phone': phone.trim(),
    }, SetOptions(merge: true));

    // Κράτα αντίγραφο του ονόματος και στο Firebase Auth (displayName), ώστε να
    // είναι ανακτήσιμο αν ποτέ χαθεί/λείψει το πεδίο στο Firestore doc.
    try {
      await user.updateDisplayName(
          '${firstName.trim()} ${lastName.trim()}'.trim());
    } catch (_) {
      // Μη κρίσιμο — το όνομα υπάρχει ήδη στο Firestore.
    }

    // Το doc μόλις δημιουργήθηκε → αποθήκευσε τώρα το FCM token (το init είχε
    // τρέξει νωρίτερα, όταν δεν υπήρχε ακόμα doc).
    await FcmService.syncToken(uid);

    // ============================================================
    // ΒΗΜΑ 3: UPLOAD ΦΩΤΟΓΡΑΦΙΑΣ (αν υπάρχει)
    // ============================================================
    if (profilePhoto != null) {
      try {
        final ref = _storage.ref('users/$uid/profile.jpg');
        await ref.putFile(profilePhoto);
        final photoUrl = await ref.getDownloadURL();
        await _db.collection('users').doc(uid).update({
          'photoUrl': photoUrl,
          'avatarUrl': photoUrl,
        });
      } catch (_) {
        // Αν αποτύχει το upload, δεν πειράζει — ο χρήστης έχει profile
      }
    }
  }

  // ============================================================
  // OTHER
  // ============================================================
  Future<void> logout() => _auth.signOut();

  Future<void> updatePassword(String newPassword) =>
      _auth.currentUser!.updatePassword(newPassword);

  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
}
