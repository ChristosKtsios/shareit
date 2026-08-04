import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

enum NotificationType {
  newMessage,
  dealStarted,
  dealExpired,
  newRating,
  newComment,
  listingExpiring,
  friendRequest,
  friendAccepted,
  listingDeleted,
}

extension NotificationTypeX on NotificationType {
  String get title { switch (this) {
    case NotificationType.newMessage:  return 'notif.newMessage'.tr();
    case NotificationType.dealStarted: return 'notif.dealStarted'.tr();
    case NotificationType.dealExpired: return 'notif.dealExpired'.tr();
    case NotificationType.newRating:   return 'notif.newRating'.tr();
    case NotificationType.newComment:  return 'notif.newComment'.tr();
    case NotificationType.listingExpiring: return 'notif.listingExpiring'.tr();
    case NotificationType.friendRequest:   return 'notif.friendRequest'.tr();
    case NotificationType.friendAccepted:  return 'notif.friendAccepted'.tr();
    case NotificationType.listingDeleted:  return 'notif.listingDeleted'.tr();
  }}
  static NotificationType fromString(String? v) =>
      NotificationType.values.firstWhere((e) => e.name == v,
          orElse: () => NotificationType.newMessage);
}

class NotificationModel {
  final String id, targetUid, title, body;
  final NotificationType type;
  final String? routePath;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id, required this.targetUid, required this.type,
    required this.title, required this.body,
    this.routePath, required this.isRead, required this.createdAt,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id, targetUid: d['targetUid'] ?? '',
      type: NotificationTypeX.fromString(d['type']),
      title: d['title'] ?? '', body: d['body'] ?? '',
      routePath: d['routePath'],
      isRead: d['isRead'] ?? false,
      // Το `as Timestamp` σκέτο κρασάριζε ΟΛΗ τη λίστα ειδοποιήσεων αν ένα doc
      // δεν είχε ακόμα createdAt (serverTimestamp: null για λίγα ms).
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'targetUid': targetUid, 'type': type.name, 'title': title, 'body': body,
    'routePath': routePath, 'isRead': isRead, 'createdAt': FieldValue.serverTimestamp(),
  };
}
