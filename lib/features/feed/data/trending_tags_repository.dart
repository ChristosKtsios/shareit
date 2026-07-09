import 'package:cloud_firestore/cloud_firestore.dart';

class TrendingTagsRepository {
  final _db = FirebaseFirestore.instance;

  /// Επιστρέφει τα top N tags από όλα τα active listings.
  Future<List<MapEntry<String, int>>> topTags({int limit = 10}) async {
    final snap = await _db.collection('listings').limit(200).get();
    final counts = <String, int>{};
    for (final doc in snap.docs) {
      final tags = List<String>.from(doc.data()['tags'] ?? []);
      for (final t in tags) {
        if (t.trim().isEmpty) continue;
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }
}
