import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

class UserRepository {
  final _db = FirebaseFirestore.instance;

  Stream<UserModel?> watch(String uid) =>
      _db.collection('users').doc(uid).snapshots()
          .map((d) => d.exists ? UserModel.fromFirestore(d) : null);

  Future<UserModel?> get(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists ? UserModel.fromFirestore(doc) : null;
  }

  Future<void> update(String uid, Map<String, dynamic> data) async =>
      await _db.collection('users').doc(uid).update(data);

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
}
