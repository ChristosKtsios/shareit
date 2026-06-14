import 'package:cloud_firestore/cloud_firestore.dart';
import 'wall_post_model.dart';

class WallPostRepository {
  final _db = FirebaseFirestore.instance;

  /// Stream με όλα τα wall posts του target user (στο profile του).
  Stream<List<WallPostModel>> watchUserWallPosts(String targetUid) => _db
      .collection('wallPosts')
      .where('targetUid', isEqualTo: targetUid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(WallPostModel.fromFirestore).toList());

  /// Stream με ένα συγκεκριμένο wall post.
  Stream<WallPostModel?> watchById(String postId) => _db
      .collection('wallPosts')
      .doc(postId)
      .snapshots()
      .map((s) => s.exists ? WallPostModel.fromFirestore(s) : null);

  /// Stream με σχόλια ενός wall post (συμπεριλαμβάνει διαγραμμένα).
  Stream<List<CommentModel>> watchComments(String postId) => _db
      .collection('wallPosts')
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(CommentModel.fromFirestore).toList());

  /// Προσθέτει σχόλιο.
  Future<void> addComment({
    required String postId,
    required String authorUid,
    required String authorName,
    String? authorAvatar,
    required String text,
    String? imageUrl,
  }) async {
    final batch = _db.batch();
    final commentRef =
        _db.collection('wallPosts').doc(postId).collection('comments').doc();
    batch.set(commentRef, {
      'authorUid': authorUid,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'text': text,
      'imageUrl': imageUrl,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('wallPosts').doc(postId), {
      'commentsCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Soft delete σχολίου — δεν σβήνεται, μένει με isDeleted=true.
  /// Το commentsCount ΔΕΝ μειώνεται (γιατί το σχόλιο μένει).
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    await _db
        .collection('wallPosts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'text': '', // καθαρίζουμε το text για ασφάλεια
    });
  }
}
