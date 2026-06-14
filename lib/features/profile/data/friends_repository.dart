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

  /// Αποδοχή αιτήματος — με detailed logging για debug.
  /// Κάνει 3 ξεχωριστά operations αντί για batch ώστε να εντοπίζουμε
  /// ποιο συγκεκριμένα αποτυγχάνει (αν αποτυγχάνει).
  Future<void> accept({
    required String requestId,
    required String fromUid,
    required String toUid,
  }) async {
    debugPrint('🤝 FriendsRepo.accept START: req=$requestId, '
        'from=$fromUid, to=$toUid');

    // Step 1: Mark request as accepted
    try {
      await _db.collection('friendRequests').doc(requestId).update({
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Step 1 OK: request marked accepted');
    } catch (e) {
      debugPrint('❌ Step 1 FAIL (request update): $e');
      rethrow;
    }

    // Step 2: Add toUid (current user) στα friends του fromUid
    try {
      await _db.collection('users').doc(fromUid).update({
        'friends': FieldValue.arrayUnion([toUid]),
      });
      debugPrint('✅ Step 2 OK: $toUid added to friends of $fromUid');
    } catch (e) {
      debugPrint('❌ Step 2 FAIL (update fromUid friends): $e');
      // Δεν κάνουμε rethrow γιατί το step 1 ήδη έγινε.
      // Καλύτερα να συνεχίσουμε με το step 3 για να κάνουμε τουλάχιστον
      // το δικό μας user document σωστό.
    }

    // Step 3: Add fromUid στα friends του toUid (current user — δικό μου)
    try {
      await _db.collection('users').doc(toUid).update({
        'friends': FieldValue.arrayUnion([fromUid]),
      });
      debugPrint('✅ Step 3 OK: $fromUid added to friends of $toUid');
    } catch (e) {
      debugPrint('❌ Step 3 FAIL (update toUid friends): $e');
      rethrow;
    }

    debugPrint('🎉 FriendsRepo.accept COMPLETE');
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
