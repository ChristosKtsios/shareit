import 'package:cloud_firestore/cloud_firestore.dart';

class WallPostModel {
  final String id;
  final String? dealId;
  final String targetUid;
  final String type;
  final String title;
  final String details;
  final String listingTitle;
  final String user1Uid;
  final String user2Uid;
  final String user1Name;
  final String user2Name;
  final String? user1Avatar;
  final String? user2Avatar;
  final String authorUid;
  final String authorName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final String dealStatus;
  final List<String> allowedCommenters;
  final int commentsCount;
  final DateTime createdAt;
  final DateTime? completedAt;

  const WallPostModel({
    required this.id,
    this.dealId,
    required this.targetUid,
    required this.type,
    required this.title,
    required this.details,
    required this.listingTitle,
    required this.user1Uid,
    required this.user2Uid,
    required this.user1Name,
    required this.user2Name,
    this.user1Avatar,
    this.user2Avatar,
    required this.authorUid,
    required this.authorName,
    this.startDate,
    this.endDate,
    required this.status,
    required this.dealStatus,
    required this.allowedCommenters,
    required this.commentsCount,
    required this.createdAt,
    this.completedAt,
  });

  bool get isCompleted => status == 'completed';
  bool get isActive => status == 'active';

  Duration get remaining =>
      endDate?.difference(DateTime.now()) ?? Duration.zero;

  bool get hasExpired => endDate != null && endDate!.isBefore(DateTime.now());

  bool get hasStarted =>
      startDate != null && startDate!.isBefore(DateTime.now());

  bool canComment(String uid) => allowedCommenters.contains(uid);

  String? get rateDealId => isCompleted ? dealId : null;

  factory WallPostModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WallPostModel(
      id: doc.id,
      dealId: d['dealId'] as String?,
      targetUid: d['targetUid'] as String? ?? '',
      type: d['type'] as String? ?? 'deal',
      title: d['title'] as String? ?? '',
      details: d['details'] as String? ?? d['description'] as String? ?? '',
      listingTitle: d['listingTitle'] as String? ?? '',
      user1Uid: d['user1Uid'] as String? ?? '',
      user2Uid: d['user2Uid'] as String? ?? '',
      user1Name: d['user1Name'] as String? ?? 'Χρήστης',
      user2Name: d['user2Name'] as String? ?? 'Χρήστης',
      user1Avatar: d['user1Avatar'] as String?,
      user2Avatar: d['user2Avatar'] as String?,
      authorUid: d['authorUid'] as String? ?? '',
      authorName: d['authorName'] as String? ?? 'Χρήστης',
      startDate: (d['startDate'] as Timestamp?)?.toDate(),
      endDate: (d['endDate'] as Timestamp?)?.toDate() ??
          (d['deliveryAt'] as Timestamp?)?.toDate(),
      status: d['status'] as String? ?? 'active',
      dealStatus: d['dealStatus'] as String? ?? 'active',
      allowedCommenters:
          List<String>.from(d['allowedCommenters'] as List? ?? []),
      commentsCount: (d['commentsCount'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class CommentModel {
  final String id;
  final String authorUid;
  final String authorName;
  final String? authorAvatar;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  const CommentModel({
    required this.id,
    required this.authorUid,
    required this.authorName,
    this.authorAvatar,
    required this.text,
    this.imageUrl,
    required this.createdAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  factory CommentModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return CommentModel(
      id: doc.id,
      authorUid: d['authorUid'] as String? ?? '',
      authorName: d['authorName'] as String? ?? 'Χρήστης',
      authorAvatar: d['authorAvatar'] as String?,
      text: d['text'] as String? ?? '',
      imageUrl: d['imageUrl'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDeleted: d['isDeleted'] as bool? ?? false,
      deletedAt: (d['deletedAt'] as Timestamp?)?.toDate(),
    );
  }
}
