import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FriendsRepository {
  final _db = FirebaseFirestore.instance;

  /// Στέλνει αίτημα φιλίας από [fromUid] προς [toUid].
  Future<void> sendRequest({
    required String fromUid,
    required String toUid,
  }) async {
    if (fromUid == toUid) return;

    final outgoing = await _db
        .collection('friendRequests')
        .where('fromUid', isEqualTo: fromUid)
        .where('toUid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (outgoing.docs.isNotEmpty) return;

    final incoming = await _db
        .collection('friendRequests')
        .where('fromUid', isEqualTo: toUid)
        .where('toUid', isEqualTo: fromUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (incoming.docs.isNotEmpty) return;

    await _db.collection('friendRequests').add({
      'fromUid': fromUid,
      'toUid': toUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Αποδοχή αιτήματος — atomic WriteBatch ώστε και τα 3 writes να γίνουν
  /// μαζί ή καθόλου (αποφεύγουμε μονόπλευρη φιλία αν αποτύχει κάποιο βήμα).
  /// Όλα τα writes είναι συμβατά με τους κανόνες:
  ///  - friendRequests update: ο acceptor είναι ο toUid
  ///  - users/{fromUid}: diff μόνο 'friends' (επιτρέπεται)
  ///  - users/{toUid}: δικό μου doc (isOwner)
  Future<void> accept({
    required String requestId,
    required String fromUid,
    required String toUid,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('friendRequests').doc(requestId), {
      'status': 'accepted',
      'respondedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('users').doc(fromUid), {
      'friends': FieldValue.arrayUnion([toUid]),
    });
    batch.update(_db.collection('users').doc(toUid), {
      'friends': FieldValue.arrayUnion([fromUid]),
    });
    await batch.commit();
  }

  /// Απόρριψη αιτήματος.
  Future<void> reject(String requestId) async {
    await _db.collection('friendRequests').doc(requestId).update({
      'status': 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Αφαίρεση φίλου από τη λίστα και των δύο.
  Future<void> remove({
    required String currentUid,
    required String targetUid,
  }) async {
    // Δικό μου doc (επιτρέπεται από rules: isOwner)
    try {
      await _db.collection('users').doc(currentUid).update({
        'friends': FieldValue.arrayRemove([targetUid]),
      });
    } catch (e) {
      debugPrint('❌ Remove from currentUid failed: $e');
    }

    // Doc του άλλου (επιτρέπεται από νέο rule: friends-only update)
    try {
      await _db.collection('users').doc(targetUid).update({
        'friends': FieldValue.arrayRemove([currentUid]),
      });
    } catch (e) {
      debugPrint('❌ Remove from targetUid failed: $e');
    }
  }

  /// Status: 'none' | 'sent' | 'received' | 'friends'
  Stream<String> friendshipStatus({
    required String currentUid,
    required String targetUid,
  }) {
    return _db
        .collection('users')
        .doc(currentUid)
        .snapshots()
        .asyncMap((userDoc) async {
      final friends = (userDoc.data()?['friends'] as List?) ?? [];
      if (friends.contains(targetUid)) return 'friends';

      try {
        final sent = await _db
            .collection('friendRequests')
            .where('fromUid', isEqualTo: currentUid)
            .where('toUid', isEqualTo: targetUid)
            .where('status', isEqualTo: 'pending')
            .limit(1)
            .get();
        if (sent.docs.isNotEmpty) return 'sent';
      } catch (_) {}

      try {
        final received = await _db
            .collection('friendRequests')
            .where('fromUid', isEqualTo: targetUid)
            .where('toUid', isEqualTo: currentUid)
            .where('status', isEqualTo: 'pending')
            .limit(1)
            .get();
        if (received.docs.isNotEmpty) return 'received';
      } catch (_) {}

      return 'none';
    });
  }
}
