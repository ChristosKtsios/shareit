import 'package:cloud_firestore/cloud_firestore.dart';
import 'deal_model.dart';

class DealRepository {
  final _db = FirebaseFirestore.instance;

  Future<String> create({
    required String chatId,
    required String listingId,
    required String listingTitle,
    required String user1Uid,
    required String user2Uid,
  }) async {
    final doc = await _db.collection('deals').add({
      'chatId': chatId,
      'listingId': listingId,
      'listingTitle': listingTitle,
      'user1Uid': user1Uid,
      'user2Uid': user2Uid,
      'status': DealStatus.pending.name,
      'proposal1': null,
      'proposal2': null,
      'activatedAt': null,
      'startDate': null,
      'endDate': null,
      'ownerRating': null,
      'seekerRating': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Αποστολή πρότασης. Ο αποστολέας ΣΥΜΦΩΝΕΙ ΑΥΤΟΜΑΤΑ (accepted=true).
  Future<void> sendProposal({
    required String dealId,
    required String userId,
    required DealProposal proposal,
  }) async {
    final doc = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final isUser1 = data['user1Uid'] == userId;
    final field = isUser1 ? 'proposal1' : 'proposal2';
    final otherField = isUser1 ? 'proposal2' : 'proposal1';

    final updates = <String, dynamic>{
      field: proposal.copyWith(accepted: true).toMap(),
    };
    if (data[otherField] != null) {
      updates['$otherField.accepted'] = false;
    }

    await _db.collection('deals').doc(dealId).update(updates);

    // Αν και τα 2 accepted → active
    final updated = await _db.collection('deals').doc(dealId).get();
    final p1 = updated.data()?['proposal1'];
    final p2 = updated.data()?['proposal2'];

    if (p1?['accepted'] == true && p2?['accepted'] == true) {
      final startDate = (p1['startDate'] as Timestamp).toDate();
      final endDate = (p1['endDate'] as Timestamp).toDate();
      await _db.collection('deals').doc(dealId).update({
        'status': DealStatus.active.name,
        'activatedAt': FieldValue.serverTimestamp(),
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
      });
    }
  }

  /// Αποδοχή πρότασης. Όταν συμφωνούν και οι 2, deal -> active.
  Future<void> acceptProposal({
    required String dealId,
    required String userId,
  }) async {
    final doc = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final isUser1 = data['user1Uid'] == userId;
    final field = isUser1 ? 'proposal1' : 'proposal2';

    await _db.collection('deals').doc(dealId).update({
      '$field.accepted': true,
    });

    final updated = await _db.collection('deals').doc(dealId).get();
    final p1 = updated.data()?['proposal1'];
    final p2 = updated.data()?['proposal2'];

    if (p1?['accepted'] == true && p2?['accepted'] == true) {
      final startDate = (p1['startDate'] as Timestamp).toDate();
      final endDate = (p1['endDate'] as Timestamp).toDate();
      await _db.collection('deals').doc(dealId).update({
        'status': DealStatus.active.name,
        'activatedAt': FieldValue.serverTimestamp(),
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
      });

      // Αύξησε dealsCount και για τους 2 χρήστες
      await _incrementDealsCount(data['user1Uid'] as String);
      await _incrementDealsCount(data['user2Uid'] as String);
    }
  }

  Future<void> _incrementDealsCount(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      // Safe access — αν λείπει field, default 0
      final data = snap.data() ?? <String, dynamic>{};
      final cur = (data['dealsCount'] as num?)?.toInt() ?? 0;
      tx.update(userRef, {'dealsCount': cur + 1});
    });
  }

  Future<void> cancel(String dealId) async =>
      await _db.collection('deals').doc(dealId).update({
        'status': DealStatus.cancelled.name,
      });

  /// Επιστρέφει true αν ο χρήστης έχει ήδη αξιολογήσει το deal.
  Future<bool> hasUserRated({
    required String dealId,
    required String userId,
  }) async {
    final doc = await _db.collection('deals').doc(dealId).get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final isUser1 = data['user1Uid'] == userId;
    final field = isUser1 ? 'ownerRating' : 'seekerRating';
    return data[field] != null;
  }

  /// Αξιολόγηση deal — ένας χρήστης βαθμολογεί τον άλλο.
  /// ΠΡΟΣΤΑΣΙΑ: Δεν επιτρέπεται διπλή αξιολόγηση.
  /// SAFE: Δεν σπάει αν λείπουν fields από user document.
  Future<void> rate({
    required String dealId,
    required String raterUid,
    required double rating,
  }) async {
    final doc = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final isUser1 = data['user1Uid'] == raterUid;
    final field = isUser1 ? 'ownerRating' : 'seekerRating';
    final targetUid = isUser1 ? data['user2Uid'] : data['user1Uid'];

    if (data[field] != null) {
      throw Exception('Έχεις ήδη αξιολογήσει αυτό το deal');
    }

    // Πρώτα αποθηκεύουμε το rating στο deal
    await _db.collection('deals').doc(dealId).update({field: rating});

    // Μετά ενημερώνουμε το rating + ratingCount του target user.
    // SAFE: χρησιμοποιούμε .data() ?? {} αντί για snap['field'] για να
    // αποφύγουμε "Bad state: field does not exist" αν λείπει.
    final userRef = _db.collection('users').doc(targetUid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);

      // Αν το user document δεν υπάρχει, μην κάνουμε τίποτα
      if (!snap.exists) return;

      final userData = snap.data() ?? <String, dynamic>{};
      final cur = (userData['rating'] as num?)?.toDouble() ?? 0.0;
      final cnt = (userData['ratingCount'] as num?)?.toInt() ?? 0;
      final newCnt = cnt + 1;
      final newAvg = ((cur * cnt) + rating) / newCnt;

      tx.update(userRef, {
        'rating': newAvg,
        'ratingCount': newCnt,
      });
    });
  }

  Stream<List<DealModel>> watchUserDeals(String uid) => _db
      .collection('deals')
      .where(Filter.or(Filter('user1Uid', isEqualTo: uid),
          Filter('user2Uid', isEqualTo: uid)))
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(DealModel.fromFirestore).toList());

  Stream<DealModel?> watchByChatId(String chatId) => _db
      .collection('deals')
      .where('chatId', isEqualTo: chatId)
      .snapshots()
      .map((s) {
        if (s.docs.isEmpty) return null;
        final sorted = s.docs.toList()
          ..sort((a, b) {
            final aTs = a.data()['createdAt'] as Timestamp?;
            final bTs = b.data()['createdAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });
        return DealModel.fromFirestore(sorted.first);
      });
}
