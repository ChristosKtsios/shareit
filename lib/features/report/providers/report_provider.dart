import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/report_model.dart';

final _db = FirebaseFirestore.instance;

Future<void> reportUser({required String reporterUid, required String targetUid,
    required ReportReason reason, String? details, String? listingId}) async {
  await _db.collection('reports').add(ReportModel(
    reporterUid: reporterUid, targetUid: targetUid,
    listingId: listingId, reason: reason, details: details,
  ).toFirestore());
  if (listingId != null) {
    await _db.collection('listings').doc(listingId).update({'isReported': true});
  }
}

Future<void> blockUser(String uid, String targetUid) async =>
    await _db.collection('users').doc(uid)
        .update({'blockedUids': FieldValue.arrayUnion([targetUid])});

Future<void> unblockUser(String uid, String targetUid) async =>
    await _db.collection('users').doc(uid)
        .update({'blockedUids': FieldValue.arrayRemove([targetUid])});
