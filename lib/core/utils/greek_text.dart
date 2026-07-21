/// Βοηθητικά για ελληνικό κείμενο: accent- & case-insensitive σύγκριση.
///
/// Χρησιμοποιείται ώστε "ψάχνω" και "ψαχνω" να θεωρούνται το ΙΔΙΟ tag/όρος:
/// - [fold] δίνει μια κανονικοποιημένη μορφή (χωρίς τόνους, πεζά, τελικό σίγμα)
///   για ομαδοποίηση & αναζήτηση.
/// - [hasAccent] λέει αν μια λέξη έχει τόνο, ώστε να προτιμάμε την τονισμένη
///   μορφή για εμφάνιση.
class GreekText {
  static const Map<String, String> _foldMap = {
    'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω',
    'ϊ': 'ι', 'ϋ': 'υ', 'ΐ': 'ι', 'ΰ': 'υ', 'ς': 'σ',
  };

  /// Κανονικοποιημένη μορφή για σύγκριση: πεζά, χωρίς τόνους, τελικό ς -> σ.
  static String fold(String s) {
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      buf.write(_foldMap[ch] ?? ch);
    }
    return buf.toString();
  }

  /// True αν η λέξη έχει τουλάχιστον έναν τόνο (ή τελικό σίγμα) — προτιμάται
  /// για εμφάνιση έναντι της "άτονης" εκδοχής.
  static bool hasAccent(String s) => fold(s) != s.toLowerCase();

  // ── Greeklish ────────────────────────────────────────────────────────────
  //
  // Ο χρήστης γράφει «mikrofono» και η αγγελία λέει «μικρόφωνο» → μηδέν
  // αποτελέσματα. Πολύ συχνό: πολλοί ψάχνουν με λατινικούς χαρακτήρες.
  //
  // ΚΑΤΕΥΘΥΝΣΗ: μεταγράφουμε ΕΛΛΗΝΙΚΑ → GREEKLISH, όχι το αντίστροφο.
  // Το ελληνικά→greeklish είναι **μονοσήμαντο** (μ→m, φ→f, ω→o), ενώ το
  // αντίστροφο είναι διφορούμενο (i → ι/η/υ/ει/οι, o → ο/ω, e → ε/αι) και θα
  // απαιτούσε συνδυαστική έκρηξη παραλλαγών.
  //
  // Έτσι, η αγγελία αποθηκεύει ΚΑΙ τη greeklish μορφή των λέξεών της, και η
  // αναζήτηση με λατινικά ταιριάζει απευθείας.

  // ΔΥΟ παραλλαγές, γιατί τα greeklish δεν γράφονται με έναν τρόπο:
  //   «τρυπάνι»  → trypani  (φωνητικά)  ή  tripani  (οπτικά, υ→i)
  //   «παιχνίδι» → paichnidi            ή  paixnidi (χ→x)
  //   «μπάλα»    → bala                 ή  mpala
  // Με μία μόνο μορφή, ο μισός κόσμος δεν θα έβρισκε τίποτα.

  /// Παραλλαγή Α — «φωνητική»: μπ→b, ντ→d, χ→ch, υ→y.
  static const Map<String, String> _digraphsA = {
    'ου': 'ou', 'αι': 'ai', 'ει': 'ei', 'οι': 'oi', 'αυ': 'af', 'ευ': 'ef',
    'γγ': 'ng', 'γκ': 'gk', 'μπ': 'b', 'ντ': 'd', 'τσ': 'ts', 'τζ': 'tz',
  };
  static const Map<String, String> _lettersA = {
    'α': 'a', 'β': 'v', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'i',
    'θ': 'th', 'ι': 'i', 'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'x',
    'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'τ': 't', 'υ': 'y', 'φ': 'f',
    'χ': 'ch', 'ψ': 'ps', 'ω': 'o',
  };

  /// Παραλλαγή Β — «οπτική»: ο χρήστης πληκτρολογεί γράμμα-γράμμα ό,τι βλέπει
  /// (μπ→mp, ντ→nt, χ→x, υ→i, ξ→ks, η→h, ω→w).
  ///
  /// ΣΗΜΑΝΤΙΚΟ: εδώ ΔΕΝ μπαίνουν φωνητικά δίψηφα φωνηέντων (αι→e, ει→i), γιατί
  /// κανείς δεν γράφει «pexnidi» — γράφουν «paixnidi», γράμμα προς γράμμα.
  static const Map<String, String> _digraphsB = {
    'ου': 'ou', 'γγ': 'gg', 'γκ': 'gk', 'μπ': 'mp', 'ντ': 'nt',
    'τσ': 'ts', 'τζ': 'tz',
  };
  static const Map<String, String> _lettersB = {
    'α': 'a', 'β': 'b', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'h',
    'θ': 'th', 'ι': 'i', 'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'ks',
    'ο': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'τ': 't', 'υ': 'i', 'φ': 'f',
    'χ': 'x', 'ψ': 'ps', 'ω': 'w',
  };

  static String _map(String s, Map<String, String> di, Map<String, String> le) {
    var t = fold(s); // πεζά, χωρίς τόνους, τελικό ς → σ
    for (final e in di.entries) {
      t = t.replaceAll(e.key, e.value);
    }
    final buf = StringBuffer();
    for (final ch in t.split('')) {
      buf.write(le[ch] ?? ch);
    }
    return buf.toString();
  }

  /// «μικρόφωνο» → «mikrofono». Η κύρια (φωνητική) μεταγραφή.
  static String toGreeklish(String s) => _map(s, _digraphsA, _lettersA);

  /// Όλες οι παραλλαγές greeklish μιας λέξης (χωρίς διπλότυπα, χωρίς την ίδια
  /// τη λέξη αν δεν έχει ελληνικά).
  static Set<String> greeklishVariants(String s) {
    if (!hasGreek(s)) return const {};
    return {
      _map(s, _digraphsA, _lettersA),
      _map(s, _digraphsB, _lettersB),
    }..removeWhere((w) => w.length < 3);
  }

  /// True αν το κείμενο περιέχει ελληνικούς χαρακτήρες.
  static bool hasGreek(String s) => RegExp(r'[α-ωΑ-Ωά-ώΆ-Ώ]').hasMatch(s);
}
