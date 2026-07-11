import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'user_model.dart';

class UserRepository {
  final _db = FirebaseFirestore.instance;

  /// Το doc με τα ευαίσθητα δεδομένα του χρήστη (email, phone, fcmToken,
  /// language). Το διαβάζει/γράφει **μόνο ο ίδιος** — βλ. firestore.rules.
  static DocumentReference<Map<String, dynamic>> privateRef(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('data');

  bool _isMe(String uid) => FirebaseAuth.instance.currentUser?.uid == uid;

  /// Για τον ΙΔΙΟ τον χρήστη ενώνει δημόσιο + private doc (ώστε οι οθόνες
  /// «Το προφίλ μου»/Ρυθμίσεις να βλέπουν email/κινητό). Για ξένο προφίλ
  /// επιστρέφει μόνο τα δημόσια πεδία — το private doc δεν είναι αναγνώσιμο.
  Stream<UserModel?> watch(String uid) {
    final pub = _db.collection('users').doc(uid).snapshots();
    if (!_isMe(uid)) {
      return pub.map((d) => d.exists ? UserModel.fromFirestore(d) : null);
    }
    return pub.asyncMap((d) async {
      if (!d.exists) return null;
      final priv = await privateRef(uid).get();
      return UserModel.fromFirestore(d, priv.data());
    });
  }

  Future<UserModel?> get(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    if (!_isMe(uid)) return UserModel.fromFirestore(doc);
    final priv = await privateRef(uid).get();
    return UserModel.fromFirestore(doc, priv.data());
  }

  /// Update στο ΔΗΜΟΣΙΟ doc. Τα ευαίσθητα πεδία απορρίπτονται από τα rules —
  /// χρησιμοποίησε το [updatePrivate].
  Future<void> update(String uid, Map<String, dynamic> data) async =>
      await _db.collection('users').doc(uid).update(data);

  /// Update στο private doc (email / phone / fcmToken / language).
  Future<void> updatePrivate(String uid, Map<String, dynamic> data) async =>
      await privateRef(uid).set(data, SetOptions(merge: true));

  Future<void> toggleSaved(String uid, String listingId, bool save) async =>
      await _db.collection('users').doc(uid).update({
        'savedListingIds': save
            ? FieldValue.arrayUnion([listingId])
            : FieldValue.arrayRemove([listingId]),
      });

  Future<void> block(String uid, String targetUid) async =>
      await _db.collection('users').doc(uid).update(
          {'blockedUids': FieldValue.arrayUnion([targetUid])});

  Future<void> unblock(String uid, String targetUid) async =>
      await _db.collection('users').doc(uid).update(
          {'blockedUids': FieldValue.arrayRemove([targetUid])});

  /// Αφαίρεση φιλίας. Γίνεται server-side: το `friends` του ΑΛΛΟΥ χρήστη δεν
  /// είναι εγγράψιμο από τον client (αλλιώς θα μπορούσε ο καθένας να
  /// αυτοπροστεθεί στη λίστα φίλων σου και να δει ιδιωτικό προφίλ).
  Future<void> unfriend(String targetUid) async {
    await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('unfriendUser')
        .call({'targetUid': targetUid});
  }
}
