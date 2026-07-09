import 'package:cloud_firestore/cloud_firestore.dart';

class UserPostComment {
  final String id;
  final String authorUid;
  final String authorName;
  final String? authorAvatar;
  final String text;
  final DateTime createdAt;
  final List<String> likes;
  final String? parentCommentId;
  final String? parentAuthorName;
  final Map<String, List<String>> reactions;

  const UserPostComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    this.authorAvatar,
    required this.text,
    required this.createdAt,
    this.likes = const [],
    this.parentCommentId,
    this.parentAuthorName,
    this.reactions = const {},
  });

  factory UserPostComment.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserPostComment(
      id: doc.id,
      reactions: ((d['reactions'] as Map<String, dynamic>?) ?? {}).map(
        (k, v) => MapEntry(k, List<String>.from(v ?? [])),
      ),
      authorUid: d['authorUid'] ?? '',
      authorName: d['authorName'] ?? '',
      authorAvatar: d['authorAvatar'],
      text: d['text'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      likes: List<String>.from(d['likes'] ?? []),
      parentCommentId: d['parentCommentId'],
      parentAuthorName: d['parentAuthorName'],
    );
  }
}
