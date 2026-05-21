import 'package:cloud_firestore/cloud_firestore.dart';

class TagsRepository {
  final _tagsRef = FirebaseFirestore.instance.collection('tags');

  /// Αυξάνει τον counter όταν δημιουργείται αγγελία
  Future<void> incrementTags(List<String> tags) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final tag in tags) {
      final ref = _tagsRef.doc(tag);
      batch.set(
        ref,
        {
          'name': tag,
          'count': FieldValue.increment(1),
          'lastUsedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Μειώνει τον counter όταν διαγράφεται αγγελία
  Future<void> decrementTags(List<String> tags) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final tag in tags) {
      batch.set(
        _tagsRef.doc(tag),
        {'count': FieldValue.increment(-1)},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Αυτόματη συμπλήρωση: tags που ξεκινούν με το query
  Future<List<TagSuggestion>> searchTags(String query, {int limit = 8}) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    try {
      final snap = await _tagsRef
          .orderBy('name')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(limit)
          .get();

      return snap.docs
          .map((d) => TagSuggestion(
                name: d['name'] as String,
                count: (d['count'] ?? 0) as int,
              ))
          .where((t) => t.count > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Top trending tags
  Future<List<TagSuggestion>> getTrendingTags({int limit = 10}) async {
    try {
      final snap =
          await _tagsRef.orderBy('count', descending: true).limit(limit).get();

      return snap.docs
          .map((d) => TagSuggestion(
                name: d['name'] as String,
                count: (d['count'] ?? 0) as int,
              ))
          .where((t) => t.count > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

class TagSuggestion {
  final String name;
  final int count;
  const TagSuggestion({required this.name, required this.count});
}
