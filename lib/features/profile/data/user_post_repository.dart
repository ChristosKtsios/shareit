import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_post_model.dart';
import 'user_post_comment.dart';

class UserPostRepository {
  final _db = FirebaseFirestore.instance;

  Future<String> create({
    required String authorUid,
    required String authorName,
    String? authorAvatar,
    required String text,
    List<String> mediaUrls = const [],
    List<String> mediaTypes = const [],
  }) async {
    final doc = await _db.collection('userPosts').add({
      'authorUid': authorUid,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'text': text,
      'mediaUrls': mediaUrls,
      'mediaTypes': mediaTypes,
      'likes': [],
      'commentsCount': 0,
      'visibility': 'friends',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Περιεχόμενο που κρύφτηκε από reports (`isHidden`, το θέτει server-side το
  /// `onReportCreated` στα 3 reports) δεν εμφανίζεται πουθενά.
  static bool _visible(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>?;
    return d?['isHidden'] != true;
  }

  Stream<List<UserPostModel>> watchUserPosts(String uid) => _db
      .collection('userPosts')
      .where('authorUid', isEqualTo: uid)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .where(_visible)
            .map(UserPostModel.fromFirestore)
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Future<void> toggleLike({
    required String postId,
    required String userId,
  }) async {
    final ref = _db.collection('userPosts').doc(postId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final likes = List<String>.from(snap.data()?['likes'] ?? []);
    if (likes.contains(userId)) {
      await ref.update({'likes': FieldValue.arrayRemove([userId])});
    } else {
      await ref.update({'likes': FieldValue.arrayUnion([userId])});
    }
  }

  Future<void> delete(String postId) =>
      _db.collection('userPosts').doc(postId).delete();

  Future<String> addComment({
    required String postId,
    required String authorUid,
    required String authorName,
    String? authorAvatar,
    required String text,
    String? parentCommentId,
    String? parentAuthorName,
  }) async {
    final docRef = await _db
        .collection('userPosts')
        .doc(postId)
        .collection('comments')
        .add({
      'authorUid': authorUid,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'likes': <String>[],
      'parentCommentId': parentCommentId,
      'parentAuthorName': parentAuthorName,
    });
    await _db.collection('userPosts').doc(postId).update({
      'commentsCount': FieldValue.increment(1),
    });
    return docRef.id;
  }

  Stream<List<UserPostComment>> watchComments(String postId) => _db
      .collection('userPosts')
      .doc(postId)
      .collection('comments')
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .where(_visible)
            .map(UserPostComment.fromFirestore)
            .toList();
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return list;
      });

  Future<void> toggleCommentLike({
    required String postId,
    required String commentId,
    required String uid,
    required bool like,
  }) async {
    await _db
        .collection('userPosts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .update({
      'likes': like
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    });
  }

  Future<void> toggleCommentReaction({
    required String postId,
    required String commentId,
    required String uid,
    required String emoji,
  }) async {
    final ref = _db
        .collection('userPosts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);
    final snap = await ref.get();
    final reactions =
        Map<String, dynamic>.from(snap.data()?['reactions'] ?? {});
    final users = List<String>.from(reactions[emoji] ?? []);
    if (users.contains(uid)) {
      users.remove(uid);
    } else {
      users.add(uid);
    }
    if (users.isEmpty) {
      reactions.remove(emoji);
    } else {
      reactions[emoji] = users;
    }
    await ref.update({'reactions': reactions});
  }

  /// Διαγραφή σχολίου (**soft**) — ίδια συμπεριφορά με τα wall posts.
  ///
  /// Το σχόλιο δεν εξαφανίζεται: μένει ως «Το σχόλιο διαγράφηκε». Έτσι οι
  /// απαντήσεις σε αυτό δεν κρέμονται στο κενό, και ο συνομιλητής βλέπει ότι
  /// κάτι γράφτηκε και αφαιρέθηκε. Ο μετρητής σχολίων ΔΕΝ μειώνεται (το σχόλιο
  /// εξακολουθεί να υπάρχει στη λίστα).
  Future<void> deleteComment(String postId, String commentId) async {
    await _db
        .collection('userPosts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'text': '',
    });
  }
}
