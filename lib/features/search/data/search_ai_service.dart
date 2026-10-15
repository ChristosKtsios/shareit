import '../../../core/services/ai_functions.dart';
import '../../listings/data/listing_model.dart';

/// Τα φίλτρα που «κατάλαβε» το AI από μια φράση σε φυσική γλώσσα.
///
/// Όλα προαιρετικά: το AI συμπληρώνει μόνο ό,τι ζήτησε ρητά ο χρήστης.
class AiSearchFilters {
  final List<String> keywords;
  final ListingType? type;
  final ListingCategory? category;
  final double? maxDistanceKm;
  final DateTime? availableFrom;
  final DateTime? availableUntil;
  final bool sortNearest;

  /// Σημασιολογικά αποτελέσματα (embeddings): id αγγελίας → ομοιότητα 0..1.
  /// Αγγελίες που ταιριάζουν στο ΝΟΗΜΑ, ακόμα κι αν δεν έχουν καμία κοινή
  /// λέξη με το ερώτημα («μεταφορά καναπέ» → «Βοήθεια σε μετακόμιση»).
  final Map<String, double> matches;

  const AiSearchFilters({
    this.keywords = const [],
    this.type,
    this.category,
    this.maxDistanceKm,
    this.availableFrom,
    this.availableUntil,
    this.sortNearest = false,
    this.matches = const {},
  });

  /// Ανεκτικό parsing: άγνωστη/κακή τιμή → null, ποτέ throw. Ο server ήδη
  /// καθαρίζει (sanitizeFilters στο push-notifications/src/ai.ts), αλλά η
  /// εφαρμογή δεν πρέπει να σπάει αν αλλάξει το συμβόλαιο.
  factory AiSearchFilters.fromMap(Map<String, dynamic> m) {
    T? byName<T extends Enum>(List<T> values, Object? raw) {
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return null;
    }

    DateTime? date(Object? raw) =>
        raw is String ? DateTime.tryParse(raw) : null;

    return AiSearchFilters(
      keywords: (m['keywords'] as List? ?? const [])
          .whereType<String>()
          .where((k) => k.trim().isNotEmpty)
          .toList(),
      type: byName(ListingType.values, m['type']),
      category: byName(ListingCategory.values, m['category']),
      maxDistanceKm: (m['maxDistanceKm'] as num?)?.toDouble(),
      availableFrom: date(m['availableFrom']),
      availableUntil: date(m['availableUntil']),
      sortNearest: m['sort'] == 'nearest',
      matches: {
        for (final raw in (m['matches'] as List? ?? const []))
          if (raw is Map &&
              raw['id'] is String &&
              (raw['score'] is num))
            raw['id'] as String: (raw['score'] as num).toDouble(),
      },
    );
  }
}

/// Καλεί το callable `parseSearchQuery`.
class SearchAiService {
  final AiFunctions _ai;

  SearchAiService({AiFunctions? ai}) : _ai = ai ?? const AiFunctions();

  /// Πετάει [AiException] σε κάθε αποτυχία.
  Future<AiSearchFilters> parse(String query) async => AiSearchFilters.fromMap(
      await _ai.call('parseSearchQuery', {'query': query},
          timeout: const Duration(seconds: 20)));
}
