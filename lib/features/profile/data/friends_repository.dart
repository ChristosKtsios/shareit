import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  /// Ακύρωση αιτήματος που **εσύ** έστειλες, όσο είναι ακόμα σε αναμονή.
  ///
  /// Το σβήνει τελείως (αντί για `status: cancelled`) ώστε να μπορείς να
  /// ξαναστείλεις αργότερα — το [sendRequest] μπλοκάρει αν βρει pending αίτημα.
  /// Τα rules επιτρέπουν διαγραφή μόνο στον αποστολέα ή τον παραλήπτη.
  Future<void> cancelRequest({
    required String fromUid,
    required String toUid,
  }) async {
    final snap = await _db
        .collection('friendRequests')
        .where('fromUid', isEqualTo: fromUid)
        .where('toUid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending')
        .get();

    for (final doc in snap.docs) {
      try {
        await doc.reference.delete();
      } catch (e) {
        debugPrint('❌ cancelRequest ${doc.id}: $e');
      }
    }
  }

  /// Αποδοχή αιτήματος.
  ///
  /// Ο client γράφει ΜΟΝΟ το `status: accepted` στο αίτημα (μόνο ο παραλήπτης
  /// μπορεί — το επιβάλλουν τα rules). Τη φιλία τη γράφει **server-side** το
  /// Cloud Function `onFriendRequestAccepted`, και στα δύο προφίλ.
  ///
  /// Γιατί όχι από τον client: το `friends` άλλου χρήστη δεν είναι εγγράψιμο.
  /// Αν ήταν, οποιοσδήποτε θα μπορούσε να αυτοπροστεθεί στη λίστα φίλων σου —
  /// και να δει ιδιωτικό προφίλ / να σχολιάσει, χωρίς να τον δεχτείς ποτέ.
  Future<void> accept({
    required String requestId,
    required String fromUid,
    required String toUid,
  }) async {
    await _db.collection('friendRequests').doc(requestId).update({
      'status': 'accepted',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Απόρριψη αιτήματος.
  Future<void> reject(String requestId) async {
    await _db.collection('friendRequests').doc(requestId).update({
      'status': 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Αφαίρεση φίλου — και από τις δύο λίστες, **server-side** (Cloud Function
  /// `unfriendUser`). Ο client δεν γράφει το `friends` κανενός doc.
  Future<void> remove({
    required String currentUid,
    required String targetUid,
  }) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('unfriendUser')
          .call({'targetUid': targetUid});
    } catch (e) {
      debugPrint('❌ unfriendUser failed: $e');
      rethrow;
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
