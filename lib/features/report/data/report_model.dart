import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

enum ReportReason { spam, inappropriate, fake, harassment, other }

extension ReportReasonX on ReportReason {
  String get label { switch (this) {
    case ReportReason.spam:          return 'Spam';
    case ReportReason.inappropriate: return 'report.reasonInappropriate'.tr();
    case ReportReason.fake:          return 'report.reasonFake'.tr();
    case ReportReason.harassment:    return 'report.reasonHarassment'.tr();
    case ReportReason.other:         return 'report.reasonOther'.tr();
  }}
}

class ReportModel {
  final String reporterUid, targetUid;
  final String? listingId, details, chatId, messageId;
  final ReportReason reason;
  const ReportModel({required this.reporterUid, required this.targetUid,
      this.listingId, this.chatId, this.messageId, required this.reason, this.details});
  Map<String, dynamic> toFirestore() => {
    'reporterUid': reporterUid, 'targetUid': targetUid, 'listingId': listingId,
    'chatId': chatId, 'messageId': messageId,
    'reason': reason.name, 'details': details, 'createdAt': FieldValue.serverTimestamp(),
  };
}
