import '../../../core/services/ai_functions.dart';
import 'listing_model.dart';

/// Ό,τι πρότεινε το AI για μια φωτογραφία.
class ListingSuggestion {
  /// false → η φωτογραφία δεν δείχνει κάτι κατάλληλο για αγγελία (θολή,
  /// έγγραφο ταυτότητας, πρόσωπα κ.λπ.). Τότε τα υπόλοιπα είναι κενά.
  final bool suitable;
  final String title;
  final String description;
  final ListingCategory? category;
  final List<String> tags;

  const ListingSuggestion({
    required this.suitable,
    this.title = '',
    this.description = '',
    this.category,
    this.tags = const [],
  });

  /// Ανεκτικό parsing — ποτέ throw (βλ. και sanitizeSuggestion στον server).
  factory ListingSuggestion.fromMap(Map<String, dynamic> m) {
    ListingCategory? category;
    for (final c in ListingCategory.values) {
      if (c.name == m['category']) category = c;
    }
    final suitable = m['suitable'] == true;
    return ListingSuggestion(
      suitable: suitable,
      title: suitable ? (m['title'] as String? ?? '').trim() : '',
      description: suitable ? (m['description'] as String? ?? '').trim() : '',
      category: suitable ? category : null,
      tags: suitable
          ? (m['tags'] as List? ?? const [])
              .whereType<String>()
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList()
          : const [],
    );
  }
}

/// Τα πεδία της φόρμας ΠΡΙΝ και ΜΕΤΑ την εφαρμογή μιας πρότασης.
class ListingDraft {
  final String title;
  final String description;
  final ListingCategory? category;
  final List<String> tags;

  const ListingDraft({
    this.title = '',
    this.description = '',
    this.category,
    this.tags = const [],
  });

  /// Συμπληρώνει ΜΟΝΟ ό,τι είναι κενό: το AI βοηθά, δεν σβήνει ποτέ κάτι
  /// που έγραψε ήδη ο χρήστης. Τα tags ΠΡΟΣΤΙΘΕΝΤΑΙ (χωρίς διπλά) έως
  /// [maxTags].
  ListingDraft fillFrom(ListingSuggestion s, {required int maxTags}) {
    if (!s.suitable) return this;
    final merged = [...tags];
    for (final t in s.tags) {
      if (merged.length >= maxTags) break;
      if (!merged.contains(t)) merged.add(t);
    }
    return ListingDraft(
      title: title.trim().isEmpty ? s.title : title,
      description: description.trim().isEmpty ? s.description : description,
      category: category ?? s.category,
      tags: merged,
    );
  }
}

/// Καλεί το callable `suggestListingFromImage`.
class ListingAiService {
  final AiFunctions _ai;

  ListingAiService({AiFunctions? ai}) : _ai = ai ?? const AiFunctions();

  /// [storagePath]: η εικόνα έχει ήδη ανέβει στο `listings/{uid}/...`.
  /// Πετάει [AiException] σε κάθε αποτυχία.
  Future<ListingSuggestion> suggestFromImage({
    required String storagePath,
    required ListingType type,
    required String locale,
  }) async =>
      ListingSuggestion.fromMap(await _ai.call(
        'suggestListingFromImage',
        {'storagePath': storagePath, 'type': type.name, 'locale': locale},
        timeout: const Duration(seconds: 60),
      ));
}
