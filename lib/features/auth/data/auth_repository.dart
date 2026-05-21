import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AuthRepository {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ============================================================
  // PASSWORD VALIDATION
  // ============================================================
  /// Επιστρέφει null αν ο κωδικός είναι έγκυρος, αλλιώς error message.
  static String? validatePassword(String password) {
    if (password.length < 8) {
      return 'Ο κωδικός πρέπει να έχει τουλάχιστον 8 χαρακτήρες';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Ο κωδικός πρέπει να έχει τουλάχιστον 1 κεφαλαίο γράμμα';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Ο κωδικός πρέπει να έχει τουλάχιστον 1 πεζό γράμμα';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Ο κωδικός πρέπει να έχει τουλάχιστον 1 αριθμό';
    }
    return null;
  }

  // ============================================================
  // LOGIN METHODS
  // ============================================================

  /// Σύνδεση με email και κωδικό.
  Future<void> loginWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Σύνδεση με κινητό και κωδικό.
  /// Πρώτα ψάχνει το email του χρήστη από τον αριθμό κινητού στο Firestore,
  /// μετά κάνει κανονικό login με email/password.
  Future<void> loginWithPhone(String phone, String password) async {
    // Βρες το email από το κινητό
    final query = await _db
        .collection('users')
        .where('phone', isEqualTo: phone.trim())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Δεν βρέθηκε χρήστης με αυτό το κινητό.',
      );
    }

    final email = query.docs.first.data()['email'] as String?;
    if (email == null) {
      throw FirebaseAuthException(
        code: 'no-email',
        message: 'Ο λογαριασμός δεν έχει συνδεδεμένο email.',
      );
    }

    await loginWithEmail(email, password);
  }

  // ============================================================
  // REGISTER METHODS
  // ============================================================

  /// Ελέγχει αν ένα κινητό υπάρχει ήδη στη βάση.
  Future<bool> phoneExists(String phone) async {
    final query = await _db
        .collection('users')
        .where('phone', isEqualTo: phone.trim())
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  /// Δημιουργεί νέο λογαριασμό μετά από επιτυχή OTP verification.
  /// Καλείται από το RegisterScreen → PhoneOtpScreen flow.
  Future<void> registerWithPhoneVerified({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    File? profilePhoto,
  }) async {
    // 1) Δημιουργία Firebase Auth account με email/password
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;

    // 2) Upload φωτογραφίας (αν υπάρχει)
    String? photoUrl;
    if (profilePhoto != null) {
      try {
        final ref = _storage.ref('users/$uid/profile.jpg');
        await ref.putFile(profilePhoto);
        photoUrl = await ref.getDownloadURL();
      } catch (_) {
        // αν αποτύχει το upload, συνεχίζουμε χωρίς φωτογραφία
        photoUrl = null;
      }
    }

    // 3) Δημιουργία Firestore document
    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'photoUrl': photoUrl,
      'rating': 0.0,
      'ratingCount': 0,
      'isVerified': true, // verified μέσω OTP
      'phoneVerified': true,
      'blockedUids': [],
      'savedListingIds': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
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
