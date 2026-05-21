import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id, text, senderId;
  final DateTime sentAt;
  const MessageModel({required this.id, required this.text,
      required this.senderId, required this.sentAt});
  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MessageModel(id: doc.id, text: d['text'] ?? '', senderId: d['senderId'] ?? '',
        sentAt: (d['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now());
  }
}
