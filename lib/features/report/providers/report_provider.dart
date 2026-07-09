import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../data/report_model.dart';

final _db = FirebaseFirestore.instance;

Future<void> reportUser({
  required String reporterUid,
  required String targetUid,
  required ReportReason reason,
  String? details,
  String? listingId,
  String? chatId,
  String? messageId,
}) async {
  // Έλεγξε αν ο ίδιος user έχει κάνει ήδη report στο ίδιο αντικείμενο.
  // Για μηνύματα κάνουμε dedup ανά messageId, αλλιώς ανά listingId.
  var dedupQuery = _db
      .collection('reports')
      .where('reporterUid', isEqualTo: reporterUid)
      .where('targetUid', isEqualTo: targetUid);
  dedupQuery = messageId != null
      ? dedupQuery.where('messageId', isEqualTo: messageId)
      : dedupQuery.where('listingId', isEqualTo: listingId);
  final existingQuery = await dedupQuery.limit(1).get();

  if (existingQuery.docs.isNotEmpty) {
    throw Exception('report.alreadyReported'.tr());
  }

  // Δημιούργησε το report. Οι counters/flags στο target (reportCount,
  // isReported, isHidden, hiddenReason) ενημερώνονται server-side από το
  // Cloud Function onReportCreated με admin privileges — οι κανόνες δεν
  // επιτρέπουν στον reporter να γράψει σε listing/user που δεν του ανήκει.
  await _db.collection('reports').add(ReportModel(
        reporterUid: reporterUid,
        targetUid: targetUid,
        listingId: listingId,
        chatId: chatId,
        messageId: messageId,
        reason: reason,
        details: details,
      ).toFirestore());
}

Future<void> blockUser(String uid, String targetUid) async =>
    await _db.collection('users').doc(uid).update({
      'blockedUids': FieldValue.arrayUnion([targetUid])
    });

Future<void> unblockUser(String uid, String targetUid) async =>
    await _db.collection('users').doc(uid).update({
      'blockedUids': FieldValue.arrayRemove([targetUid])
    });
