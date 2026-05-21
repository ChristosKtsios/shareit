import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType { newMessage, dealStarted, dealExpired, newRating, newComment }

extension NotificationTypeX on NotificationType {
  String get title { switch (this) {
    case NotificationType.newMessage:  return 'Νέο μήνυμα';
    case NotificationType.dealStarted: return 'Deal κλείστηκε!';
    case NotificationType.dealExpired: return 'Deal ολοκληρώθηκε';
    case NotificationType.newRating:   return 'Νέα αξιολόγηση';
    case NotificationType.newComment:  return 'Νέο σχόλιο';
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
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'targetUid': targetUid, 'type': type.name, 'title': title, 'body': body,
    'routePath': routePath, 'isRead': isRead, 'createdAt': FieldValue.serverTimestamp(),
  };
}
