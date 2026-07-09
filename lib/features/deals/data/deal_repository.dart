import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'deal_model.dart';

class DealRepository {
  final _db = FirebaseFirestore.instance;

  /// Επιστρέφει true αν υπάρχει unrated/active deal μεταξύ 2 χρηστών.
  Future<bool> hasUnratedDeal({
    required String chatId,
    required String currentUid,
  }) async {
    final snap =
        await _db.collection('deals').where('chatId', isEqualTo: chatId).get();
    for (final doc in snap.docs) {
      final d = doc.data();
      final status = d['status'] as String?;
      final ownerRating = d['ownerRating'];
      final seekerRating = d['seekerRating'];
      if (status == 'pending' || status == 'active') return true;
      if (status == 'completed' &&
          (ownerRating == null || seekerRating == null)) {
        return true;
      }
    }
    return false;
  }

  /// Δημιουργία νέου deal με αρχική πρόταση από τον αποστολέα.
  /// Status: pending — περιμένει αποδοχή/απόρριψη από receiver.
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
      // Ο proposer είναι πάντα ο user1 (στέλνει το proposal1). Το χρειάζεται
      // το Cloud Function για να στείλει το push στον σωστό παραλήπτη.
      'proposerUid': user1Uid,
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

  /// Αποστολή πρότασης από τον sender (Α).
  /// Status παραμένει pending — μόνο ο receiver (Β) μπορεί να accept/reject.
  Future<void> sendProposal({
    required String dealId,
    required String userId,
    required DealProposal proposal,
  }) async {
    final doc = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final isUser1 = data['user1Uid'] == userId;
    final field = isUser1 ? 'proposal1' : 'proposal2';

    await _db.collection('deals').doc(dealId).update({
      field: proposal.copyWith(accepted: true).toMap(),
      'status': DealStatus.pending.name,
    });
  }

  /// Αποδοχή πρότασης από receiver → το deal γίνεται active.
  ///
  /// Τα 2 wall posts (countdown σε κάθε τοίχο) ΚΑΙ το dealsCount τα κάνει
  /// αποκλειστικά το Cloud Function `onDealUpdate` (server-side, με admin +
  /// σωστό allowedCommenters που περιλαμβάνει φίλους). Έτσι αποφεύγουμε τα
  /// διπλά wall posts που προέκυπταν όταν τα έφτιαχνε και ο client.
  Future<void> acceptProposal({
    required String dealId,
    required String userId,
  }) async {
    final doc = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final p1 = data['proposal1'];
    if (p1 == null) return;

    final startDate = (p1['startDate'] as Timestamp).toDate();
    final endDate = (p1['endDate'] as Timestamp).toDate();

    // Update deal → active. Τα startDate/endDate μπαίνουν top-level γιατί τα
    // διαβάζει το Cloud Function για να φτιάξει τα wall posts με το countdown.
    await _db.collection('deals').doc(dealId).update({
      'status': DealStatus.active.name,
      'activatedAt': FieldValue.serverTimestamp(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'proposal1.accepted': true,
      'proposal2.accepted': true,
    });
  }

  /// Ακύρωση deal — επιτρέπεται ΜΟΝΟ όσο είναι ακόμα pending (ο παραλήπτης δεν
  /// έχει απαντήσει). Με transaction ώστε ο έλεγχος status να είναι ατομικός —
  /// δεν γίνεται ακύρωση ενός accepted/active deal. Καλύπτει και την «Απόρριψη»
  /// του παραλήπτη (γίνεται επίσης σε pending).
  Future<void> cancel(String dealId) async {
    final ref = _db.collection('deals').doc(dealId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('deals.dealNotFound'.tr());
      final status = snap.data()?['status'] as String?;
      if (status != DealStatus.pending.name) {
        throw Exception('deals.errCannotCancel'.tr());
      }
      tx.update(ref, {
        'status': DealStatus.cancelled.name,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Έλεγχος αν χρήστης έχει ήδη αξιολογήσει — επιτρέπει μόνο 1 φορά.
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

  /// Αξιολόγηση deal — και οι 2 χρήστες μπορούν, μόνο 1 φορά ο καθένας.
  Future<void> rate({
    required String dealId,
    required String raterUid,
    required double rating,
  }) async {
    final doc = await _db.collection('deals').doc(dealId).get();
    final data = doc.data()!;
    final isUser1 = data['user1Uid'] == raterUid;
    final field = isUser1 ? 'ownerRating' : 'seekerRating';

    if (data[field] != null) {
      throw Exception('deals.errAlreadyRated'.tr());
    }

    // Έλεγχος ότι το deal είναι completed πριν επιτρέψει rate
    final status = data['status'] as String?;
    if (status != 'completed') {
      throw Exception('deals.errNotCompleted'.tr());
    }

    // Γράψε ΜΟΝΟ το rating στο deal (επιτρέπεται για τον συμμετέχοντα).
    // Η συγκέντρωση στο προφίλ του target user (rating/ratingCount) γίνεται
    // server-side από το Cloud Function onDealUpdate με admin privileges —
    // οι κανόνες δεν επιτρέπουν εγγραφή στο user doc άλλου χρήστη.
    await _db.collection('deals').doc(dealId).update({field: rating});
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
