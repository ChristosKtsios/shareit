import 'package:cloud_firestore/cloud_firestore.dart';
import 'deal_model.dart';

class DealRepository {
  final _db = FirebaseFirestore.instance;

  // Δημιουργία νέου deal (pending)
  Future<String> create({
    required String chatId,
    required String listingId,
    required String listingTitle,
    required String user1Uid,
    required String user2Uid,
  }) async {
    final doc = await _db.collection('deals').add({
      'chatId':       chatId,
      'listingId':    listingId,
      'listingTitle': listingTitle,
      'user1Uid':     user1Uid,
      'user2Uid':     user2Uid,
      'status':       DealStatus.pending.name,
      'proposal1':    null,
      'proposal2':    null,
      'activatedAt':  null,
      'deliveryAt':   null,
      'ownerRating':  null,
      'seekerRating': null,
      'createdAt':    FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  // Αποστολή πρότασης από χρήστη
  Future<void> sendProposal({
    required String dealId,
    required String userId,
    required DealProposal proposal,
  }) async {
    final doc  = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final isUser1 = data['user1Uid'] == userId;
    final field   = isUser1 ? 'proposal1' : 'proposal2';

    await _db.collection('deals').doc(dealId).update({
      field: proposal.copyWith(accepted: false).toMap(),
    });
  }

  // Αποδοχή πρότασης
  Future<void> acceptProposal({
    required String dealId,
    required String userId,
  }) async {
    final doc  = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final isUser1 = data['user1Uid'] == userId;
    final field   = isUser1 ? 'proposal1' : 'proposal2';

    // Σήμανση ως accepted
    await _db.collection('deals').doc(dealId).update({
      '$field.accepted': true,
    });

    // Έλεγχος αν και οι 2 έχουν κάνει accept
    final updated = await _db.collection('deals').doc(dealId).get();
    final p1 = updated.data()?['proposal1'];
    final p2 = updated.data()?['proposal2'];

    if (p1?['accepted'] == true && p2?['accepted'] == true) {
      final deliveryAt = isUser1
          ? (p1['deliveryAt'] as Timestamp).toDate()
          : (p2['deliveryAt'] as Timestamp).toDate();

      await _db.collection('deals').doc(dealId).update({
        'status':      DealStatus.active.name,
        'activatedAt': FieldValue.serverTimestamp(),
        'deliveryAt':  Timestamp.fromDate(deliveryAt),
      });
    }
  }

  // Ολοκλήρωση deal
  Future<void> complete(String dealId) async =>
      await _db.collection('deals').doc(dealId).update({
        'status': DealStatus.completed.name,
      });

  // Ακύρωση deal
  Future<void> cancel(String dealId) async =>
      await _db.collection('deals').doc(dealId).update({
        'status': DealStatus.cancelled.name,
      });

  // Αξιολόγηση
  Future<void> rate({
    required String dealId,
    required String raterUid,
    required double rating,
  }) async {
    final doc  = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final isUser1  = data['user1Uid'] == raterUid;
    final field    = isUser1 ? 'ownerRating' : 'seekerRating';
    final targetUid = isUser1 ? data['user2Uid'] : data['user1Uid'];

    await _db.collection('deals').doc(dealId).update({field: rating});

    // Ενημέρωση rating χρήστη
    final userRef = _db.collection('users').doc(targetUid);
    await _db.runTransaction((tx) async {
      final snap   = await tx.get(userRef);
      final cur    = (snap['rating'] as num).toDouble();
      final cnt    = (snap['ratingCount'] as num).toInt();
      final newCnt = cnt + 1;
      tx.update(userRef, {
        'rating':      ((cur * cnt) + rating) / newCnt,
        'ratingCount': newCnt,
      });
    });
  }

  // Stream deals για χρήστη
  Stream<List<DealModel>> watchUserDeals(String uid) =>
      _db.collection('deals')
          .where(Filter.or(
              Filter('user1Uid', isEqualTo: uid),
              Filter('user2Uid', isEqualTo: uid)))
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(DealModel.fromFirestore).toList());

  // Stream deal από chatId
  Stream<DealModel?> watchByChatId(String chatId) =>
      _db.collection('deals')
          .where('chatId', isEqualTo: chatId)
          .limit(1)
          .snapshots()
          .map((s) => s.docs.isEmpty
              ? null : DealModel.fromFirestore(s.docs.first));
}