import 'package:cloud_firestore/cloud_firestore.dart';

enum ReportReason { spam, inappropriate, fake, harassment, other }

extension ReportReasonX on ReportReason {
  String get label { switch (this) {
    case ReportReason.spam:          return 'Spam';
    case ReportReason.inappropriate: return 'Ακατάλληλο περιεχόμενο';
    case ReportReason.fake:          return 'Ψεύτικη αγγελία';
    case ReportReason.harassment:    return 'Παρενόχληση';
    case ReportReason.other:         return 'Άλλο';
  }}
}

class ReportModel {
  final String reporterUid, targetUid;
  final String? listingId, details;
  final ReportReason reason;
  const ReportModel({required this.reporterUid, required this.targetUid,
      this.listingId, required this.reason, this.details});
  Map<String, dynamic> toFirestore() => {
    'reporterUid': reporterUid, 'targetUid': targetUid, 'listingId': listingId,
    'reason': reason.name, 'details': details, 'createdAt': FieldValue.serverTimestamp(),
  };
}
