/// Υπηρεσία που εξάγει πιθανές λέξεις-tags από τίτλο και περιγραφή
/// αγγελίας, φιλτράροντας stop words και κοινές μη-χρήσιμες λέξεις.
class TagExtractorService {
  // Ελληνικά stop words (χωρίς duplicates)
  static const _greekStopWords = {
    // Άρθρα
    'ο', 'η', 'το', 'οι', 'τα', 'τον', 'την', 'του', 'της', 'των', 'τους',
    'τις',
    'ένα', 'μια', 'μία', 'ένας', 'έναν',
    // Προθέσεις
    'σε', 'στο', 'στη', 'στην', 'στον', 'στις', 'στα', 'στους', 'για', 'με',
    'από', 'απο', 'προς', 'παρά', 'μετά', 'πριν', 'μέσα', 'έξω', 'πάνω', 'κάτω',
    'μαζί', 'χωρίς', 'εκτός', 'και', 'κι',
    // Ρήματα βοηθητικά
    'είμαι', 'είσαι', 'είναι', 'είμαστε', 'είστε', 'ήμουν', 'ήσουν', 'ήταν',
    'ήμασταν', 'ήσασταν', 'έχω', 'έχει', 'έχουν', 'είχα', 'είχε', 'είχαν',
    'θέλω', 'θέλει', 'μπορώ', 'μπορεί', 'πρέπει', 'πρεπει',
    // Σύνδεσμοι
    'που', 'πως', 'πού', 'πώς', 'πότε', 'γιατί', 'εάν', 'αν', 'όταν', 'καθώς',
    'όπως', 'ενώ', 'αλλά', 'όμως', 'παρόλο', 'επειδή', 'δηλαδή', 'δλδ',
    'ή', 'είτε', 'ούτε', 'μήτε',
    // Αρνήσεις/καταφάσεις
    'δεν', 'δε', 'μη', 'μην', 'ναι', 'όχι', 'οχι',
    // Χρόνος
    'ίσως', 'σίγουρα', 'πάντα', 'ποτέ', 'τώρα', 'τότε', 'σήμερα', 'αύριο',
    'χθες',
    'σύντομα', 'πάλι', 'ξανά', 'ακόμα', 'ακόμη', 'ήδη',
    // Αντωνυμίες
    'εγώ', 'εσύ', 'αυτός', 'αυτή', 'αυτό', 'εμείς', 'εσείς', 'αυτοί',
    'αυτές', 'αυτά', 'μου', 'σου', 'μας', 'σας',
    'εμένα', 'εσένα', 'αυτόν', 'αυτήν', 'εμάς', 'εσάς',
    // Ποσοτικά
    'πολύ', 'λίγο', 'λίγα', 'πολλά', 'όλα', 'όλος', 'όλη', 'όλο',
    'κάθε', 'κάποιο', 'κάποια', 'κάποιος', 'κάποιες', 'τίποτα', 'τίποτε',
    'κανείς', 'καμία', 'κανένας', 'κανένα', 'άλλος', 'άλλη', 'άλλο',
    'τέτοιο', 'τόσο', 'τοσο', 'μόνο', 'μονο', 'απλά', 'απλώς', 'σχεδόν',
    'περίπου', 'τόσα', 'τοσα',
    // Διάφορα
    'ωστόσο', 'εντάξει', 'οκ', 'καλά', 'καλό', 'καλή', 'καλός',
    'θα', 'να', 'γία', 'εκεί', 'εδώ',
  };

  // Αγγλικά stop words
  static const _englishStopWords = {
    'the',
    'a',
    'an',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'being',
    'have',
    'has',
    'had',
    'do',
    'does',
    'did',
    'will',
    'would',
    'could',
    'should',
    'may',
    'might',
    'must',
    'can',
    'in',
    'on',
    'at',
    'to',
    'for',
    'of',
    'with',
    'by',
    'from',
    'about',
    'into',
    'through',
    'and',
    'or',
    'but',
    'not',
    'no',
    'yes',
    'this',
    'that',
    'these',
    'those',
    'i',
    'you',
    'he',
    'she',
    'it',
    'we',
    'they',
    'me',
    'him',
    'her',
    'us',
    'them',
    'my',
    'your',
    'his',
    'its',
    'our',
    'their',
    'what',
    'which',
    'who',
    'whom',
    'whose',
    'where',
    'when',
    'why',
    'how',
    'all',
    'any',
    'both',
    'each',
    'few',
    'more',
    'most',
    'other',
    'some',
    'such',
    'so',
    'too',
    'very',
    'just',
    'also',
    'only',
    'own',
    'same',
    'than',
    'now',
    'then',
    'here',
    'there'
  };

  /// Εξάγει πιθανά tags από τίτλο και περιγραφή
  static List<String> extractTags({
    required String title,
    required String description,
    List<String> existingTags = const [],
    int maxSuggestions = 8,
  }) {
    final allText = '$title $description'.toLowerCase();

    final words = allText
        .replaceAll(RegExp(r'[^\w\sα-ωάέήίόύώϊϋΐΰ]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    final wordFrequency = <String, int>{};
    for (final word in words) {
      if (_shouldKeep(word)) {
        wordFrequency[word] = (wordFrequency[word] ?? 0) + 1;
      }
    }

    // Bonus για λέξεις στον τίτλο
    final titleWords = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sα-ωάέήίόύώϊϋΐΰ]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => _shouldKeep(w))
        .toSet();

    for (final word in titleWords) {
      wordFrequency[word] = (wordFrequency[word] ?? 0) + 2;
    }

    final existingNormalized = existingTags.map((t) => t.toLowerCase()).toSet();
    wordFrequency.removeWhere((k, v) => existingNormalized.contains(k));

    final sorted = wordFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(maxSuggestions).map((e) => e.key).toList();
  }

  static bool _shouldKeep(String word) {
    final w = word.trim();
    if (w.length < 3) return false;
    if (w.length > 25) return false;
    if (_greekStopWords.contains(w)) return false;
    if (_englishStopWords.contains(w)) return false;
    if (RegExp(r'^\d+$').hasMatch(w)) return false;
    return true;
  }

  /// Σπάει search query σε tokens
  static List<String> tokenizeQuery(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sα-ωάέήίόύώϊϋΐΰ]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => _shouldKeep(w))
        .toList();
  }
}
