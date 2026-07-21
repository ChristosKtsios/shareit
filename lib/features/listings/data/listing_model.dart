import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/greek_text.dart';

enum ListingType { offer, seek }

class ListingModel {
  final String id, userId, userFirstName;
  final String? userAvatarUrl;
  final ListingType type;
  final String title, description, locationLabel;
  final List<String> imageUrls, tags, searchKeywords;
  final GeoPoint location;

  /// Έναρξη διαθεσιμότητας (μπορεί να περιλαμβάνει και ώρα)
  final DateTime? availableFrom;

  /// Λήξη διαθεσιμότητας (μπορεί να περιλαμβάνει και ώρα)
  final DateTime? availableUntil;

  /// True αν ο χρήστης συμπλήρωσε ώρα στο availableFrom
  final bool hasFromTime;

  /// True αν ο χρήστης συμπλήρωσε ώρα στο availableUntil
  final bool hasUntilTime;
  final bool autoDelete, isActive, isReported;
  final double rating;
  final DateTime createdAt;

  const ListingModel({
    required this.id,
    required this.userId,
    required this.userFirstName,
    this.userAvatarUrl,
    required this.type,
    required this.title,
    required this.description,
    required this.locationLabel,
    this.imageUrls = const [],
    this.tags = const [],
    this.searchKeywords = const [],
    required this.location,
    this.availableFrom,
    this.availableUntil,
    this.hasFromTime = false,
    this.hasUntilTime = false,
    required this.autoDelete,
    required this.isActive,
    this.isReported = false,
    required this.rating,
    required this.createdAt,
  });

  /// Κόβει κείμενο σε λέξεις >2 χαρακτήρων.
  ///
  /// - [fold] true  → πεζά ΧΩΡΙΣ τόνους (GreekText.fold, τελικό ς→σ)
  /// - [fold] false → απλώς πεζά, ΜΕ τους τόνους
  /// Σημεία στίξης γίνονται κενό, ώστε «σκάλα,ξύλινη» να δίνει 2 λέξεις.
  static List<String> _words(String text, {required bool fold}) =>
      (fold ? GreekText.fold(text) : text.toLowerCase())
          .replaceAll(RegExp(r'[^\w\sα-ωάέήίόύώϊϋΐΰ]', unicode: true), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 2)
          .toSet()
          .toList();

  /// Η κανονικοποίηση για ΑΝΑΖΗΤΗΣΗ (ερώτημα χρήστη ΚΑΙ matching): άτονη.
  /// Χάρη σε αυτό το «τρυπανι» βρίσκει το «Τρυπάνι».
  static List<String> tokenize(String text) => _words(text, fold: true);

  /// Tokens που ΑΠΟΘΗΚΕΥΟΝΤΑΙ στην αγγελία.
  ///
  /// Καλύπτει τίτλο, περιγραφή, **tags** και **τοποθεσία** — ό,τι βλέπει ο
  /// χρήστης πάνω στην κάρτα. Πριν μπαίναν μόνο τίτλος+περιγραφή, οπότε αν
  /// έγραφες το tag που έβλεπες («#εργαλεια») ή την πόλη («Αθήνα») έπαιρνες
  /// ΜΗΔΕΝ αποτελέσματα — κάτι εντελώς μη διαισθητικό.
  ///
  /// Αποθηκεύονται άτονα **και** τονισμένα:
  /// - άτονα     → τα ψάχνει η ΝΕΑ αναζήτηση (arrayContainsAny με άτονους όρους)
  /// - τονισμένα → τα ψάχνει η ΠΑΛΙΑ έκδοση (arrayContains με τονισμένη λέξη).
  ///   Χωρίς αυτά, όποιος δεν ενημερώθηκε θα έβλεπε την αναζήτηση να σπάει.
  ///
  /// Οι άτονες λέξεις ταυτίζονται με τον εαυτό τους → το Set δεν διπλασιάζεται
  /// άσκοπα. Αν αλλάξει η μορφή, ξανατρέξε: shareit-functions/reindex-search.mjs
  /// Ελάχιστο μήκος προθέματος. Κάτω από 3 χαρακτήρες τα αποτελέσματα είναι
  /// άχρηστα (π.χ. «τρ» ταιριάζει με τα πάντα) και φουσκώνουν τα δεδομένα.
  static const int minPrefixLength = 3;

  /// Προθέματα μιας λέξης: «τρυπανι» → τρυ, τρυπ, τρυπα, τρυπαν, τρυπανι.
  ///
  /// Χάρη σε αυτά, γράφοντας «τρυπ» βρίσκεις το «Τρυπάνι» — το Firestore ΔΕΝ
  /// υποστηρίζει αναζήτηση «αρχίζει με» μέσα σε πίνακες, οπότε ο μόνος τρόπος
  /// είναι να αποθηκευτούν τα προθέματα.
  static Iterable<String> _prefixes(String word) sync* {
    for (var i = minPrefixLength; i <= word.length; i++) {
      yield word.substring(0, i);
    }
  }

  static List<String> generateKeywords(
    String title,
    String desc, {
    List<String> tags = const [],
    String locationLabel = '',
  }) {
    final text = '$title $desc $locationLabel ${tags.join(' ')}';
    final out = <String>{
      ..._words(text, fold: true),
      ..._words(text, fold: false),
    };

    // Προθέματα ΜΟΝΟ από τον τίτλο (και άτονα).
    //
    // Γιατί όχι από την περιγραφή: μια περιγραφή 100 λέξεων θα παρήγαγε
    // εκατοντάδες προθέματα ανά αγγελία — τεράστιο κόστος αποθήκευσης/εγγραφών
    // για ελάχιστο όφελος. Ο κόσμος ψάχνει με λέξεις του ΤΙΤΛΟΥ.
    for (final w in _words(title, fold: true)) {
      out.addAll(_prefixes(w));
    }
    return out.toList();
  }

  static String normalizeTag(String tag) {
    var t = tag.trim().toLowerCase();
    if (t.startsWith('#')) t = t.substring(1);
    return t.replaceAll(RegExp(r'\s+'), '_');
  }

  factory ListingModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ListingModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      userFirstName: d['userFirstName'] ?? '',
      userAvatarUrl: d['userAvatarUrl'],
      type: d['type'] == 'offer' ? ListingType.offer : ListingType.seek,
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      locationLabel: d['locationLabel'] ?? '',
      imageUrls: List<String>.from(d['imageUrls'] ?? []),
      tags: List<String>.from(d['tags'] ?? []),
      searchKeywords: List<String>.from(d['searchKeywords'] ?? []),
      location: d['location'] as GeoPoint? ?? const GeoPoint(0, 0),
      availableFrom: (d['availableFrom'] as Timestamp?)?.toDate(),
      availableUntil: (d['availableUntil'] as Timestamp?)?.toDate(),
      hasFromTime: d['hasFromTime'] ?? false,
      hasUntilTime: d['hasUntilTime'] ?? false,
      autoDelete: d['autoDelete'] ?? false,
      rating: (d['rating'] ?? 0).toDouble(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: d['isActive'] ?? true,
      isReported: d['isReported'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userFirstName': userFirstName,
        'userAvatarUrl': userAvatarUrl,
        'type': type.name,
        'title': title,
        'description': description,
        'locationLabel': locationLabel,
        'imageUrls': imageUrls,
        'tags': tags,
        'searchKeywords': searchKeywords,
        'location': location,
        'availableFrom':
            availableFrom != null ? Timestamp.fromDate(availableFrom!) : null,
        'availableUntil':
            availableUntil != null ? Timestamp.fromDate(availableUntil!) : null,
        'hasFromTime': hasFromTime,
        'hasUntilTime': hasUntilTime,
        'autoDelete': autoDelete,
        'rating': rating,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': isActive,
        'isReported': isReported,
      };
}
