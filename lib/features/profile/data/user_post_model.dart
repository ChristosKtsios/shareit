import 'package:cloud_firestore/cloud_firestore.dart';

class UserPostModel {
  final String id;
  final String authorUid;
  final String authorName;
  final String? authorAvatar;
  final String text;
  final List<String> mediaUrls;
  final List<String> mediaTypes;
  final List<String> likes;
  final int commentsCount;
  final String visibility;
  final DateTime createdAt;

  const UserPostModel({
    required this.id,
    required this.authorUid,
    required this.authorName,
    this.authorAvatar,
    required this.text,
    this.mediaUrls = const [],
    this.mediaTypes = const [],
    this.likes = const [],
    this.commentsCount = 0,
    this.visibility = 'friends',
    required this.createdAt,
  });

  bool isLikedBy(String uid) => likes.contains(uid);
  int get likesCount => likes.length;
  bool get hasMedia => mediaUrls.isNotEmpty;

  factory UserPostModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserPostModel(
      id: doc.id,
      authorUid: d['authorUid'] ?? '',
      authorName: d['authorName'] ?? '',
      authorAvatar: d['authorAvatar'],
      text: d['text'] ?? '',
      mediaUrls: List<String>.from(d['mediaUrls'] ?? []),
      mediaTypes: List<String>.from(d['mediaTypes'] ?? []),
      likes: List<String>.from(d['likes'] ?? []),
      commentsCount: (d['commentsCount'] as num?)?.toInt() ?? 0,
      visibility: d['visibility'] ?? 'friends',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
