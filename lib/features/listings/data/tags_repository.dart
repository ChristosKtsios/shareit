import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/greek_text.dart';

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

  /// Top trending tags — ενώνει accent-variants (π.χ. "ψάχνω" + "ψαχνω") σε ΕΝΑ
  /// tag: αθροίζει τα counts και εμφανίζει την τονισμένη μορφή. Φέρνει
  /// περισσότερα docs ώστε μετά το merge να μένουν αρκετά για το [limit].
  Future<List<TagSuggestion>> getTrendingTags({int limit = 10}) async {
    try {
      final snap = await _tagsRef
          .orderBy('count', descending: true)
          .limit(limit * 4)
          .get();

      // folded key -> (καλύτερο display name, άθροισμα count)
      final display = <String, String>{};
      final counts = <String, int>{};
      for (final d in snap.docs) {
        final name = (d['name'] as String?) ?? '';
        final count = (d['count'] ?? 0) as int;
        if (name.isEmpty || count <= 0) continue;
        final key = GreekText.fold(name);
        counts[key] = (counts[key] ?? 0) + count;
        final current = display[key];
        // Προτίμησε την τονισμένη εκδοχή για εμφάνιση.
        if (current == null ||
            (GreekText.hasAccent(name) && !GreekText.hasAccent(current))) {
          display[key] = name;
        }
      }

      final merged = counts.keys
          .map((k) => TagSuggestion(name: display[k]!, count: counts[k]!))
          .toList()
        ..sort((a, b) => b.count.compareTo(a.count));
      return merged.take(limit).toList();
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
