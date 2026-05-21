import 'package:cloud_firestore/cloud_firestore.dart';

class WallPostModel {
  final String id, targetUid, authorUid, authorName, dealId, listingTitle, text;
  final double rating;
  final DateTime createdAt;

  const WallPostModel({
    required this.id, required this.targetUid, required this.authorUid,
    required this.authorName, required this.dealId, required this.listingTitle,
    required this.text, required this.rating, required this.createdAt,
  });

  factory WallPostModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WallPostModel(
      id: doc.id, targetUid: d['targetUid'] ?? '', authorUid: d['authorUid'] ?? '',
      authorName: d['authorName'] ?? '', dealId: d['dealId'] ?? '',
      listingTitle: d['listingTitle'] ?? '', text: d['text'] ?? '',
      rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'targetUid': targetUid, 'authorUid': authorUid, 'authorName': authorName,
    'dealId': dealId, 'listingTitle': listingTitle, 'text': text,
    'rating': rating, 'createdAt': FieldValue.serverTimestamp(),
  };
}
