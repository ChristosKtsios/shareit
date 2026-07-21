import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/utils/greek_text.dart';
import 'listing_model.dart';
import 'tags_repository.dart';

class ListingRepository {
  final _col = FirebaseFirestore.instance.collection('listings');
  static const int _pageSize = 20;

  Future<void> create(ListingModel l) async => await _col.add(l.toFirestore());

  /// ΠΛΗΡΗΣ διαγραφή αγγελίας — διαγράφει και τις εικόνες από Storage.
  Future<void> deleteFully(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return;

    final data = doc.data();
    final urls =
        (data?['imageUrls'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final tags =
        (data?['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];

    for (final url in urls) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }

    await _col.doc(id).delete();

    // Μείωσε τους trending-tag counters (best-effort).
    if (tags.isNotEmpty) {
      try {
        await TagsRepository().decrementTags(tags);
      } catch (_) {}
    }
  }

  Future<int> cleanupExpiredForUser(String uid) async {
    final now = DateTime.now();
    final snap = await _col
        .where('userId', isEqualTo: uid)
        .where('autoDelete', isEqualTo: true)
        .get();

    int deleted = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final expiresAt = (data['availableUntil'] as Timestamp?)?.toDate();
      if (expiresAt != null && expiresAt.isBefore(now)) {
        await deleteFully(doc.id);
        deleted++;
      }
    }
    return deleted;
  }

  Future<void> updateListing(String id, ListingModel listing) async {
    await _col.doc(id).update({
      'title': listing.title,
      'description': listing.description,
      'tags': listing.tags,
      'searchKeywords': listing.searchKeywords,
      'locationLabel': listing.locationLabel,
      'imageUrls': listing.imageUrls,
      'location': listing.location,
      'type': listing.type.name,
      'availableFrom': listing.availableFrom != null
          ? Timestamp.fromDate(listing.availableFrom!)
          : null,
      'availableUntil': listing.availableUntil != null
          ? Timestamp.fromDate(listing.availableUntil!)
          : null,
      'hasFromTime': listing.hasFromTime,
      'hasUntilTime': listing.hasUntilTime,
      'autoDelete': listing.autoDelete,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deactivate(String id) async =>
      await _col.doc(id).update({'isActive': false});

  /// Ανανέωση αγγελίας: μηδενίζει το «ρολόι» λήξης (30 μέρες από τώρα) φέρνοντας
  /// το `createdAt` στο τώρα, καθαρίζει το flag προειδοποίησης, και τη γυρίζει
  /// ενεργή. Έτσι η αγγελία ξαναεμφανίζεται φρέσκια στην κορυφή του feed.
  Future<void> renew(String id) async => await _col.doc(id).update({
        'createdAt': FieldValue.serverTimestamp(),
        'expiryWarned': false,
        'isActive': true,
      });

  /// Helper για να φιλτράρουμε hidden αγγελίες client-side.
  /// (Firestore δεν επιτρέπει "where != true" εύκολα)
  List<ListingModel> _filterVisible(List<DocumentSnapshot> docs) {
    return docs
        .where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final isHidden = data['isHidden'] as bool? ?? false;
          return !isHidden;
        })
        .map(ListingModel.fromFirestore)
        .toList();
  }

  Stream<List<ListingModel>> watchActive() => _col
      .where('isActive', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => _filterVisible(s.docs));

  /// ΟΛΕΣ οι αγγελίες του χρήστη — και ενεργές ΚΑΙ σε παύση (isActive=false) —
  /// ώστε ο ίδιος να μπορεί να διαχειριστεί/ξαναενεργοποιήσει τις παγωμένες.
  /// Ταξινόμηση στον client (χωρίς orderBy) → δεν χρειάζεται composite index:
  /// ένα σκέτο where('userId') χρησιμοποιεί μόνο το αυτόματο single-field index.
  Stream<List<ListingModel>> watchUserListings(String uid) => _col
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((s) {
        final list = _filterVisible(s.docs);
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// Οι ΔΗΜΟΣΙΑ ορατές αγγελίες ενός χρήστη — μόνο ενεργές.
  ///
  /// Διαφέρει από το [watchUserListings], που δείχνει ΚΑΙ τις παγωμένες επειδή
  /// προορίζεται για τον ίδιο τον κάτοχο. Όταν κοιτάζει ΑΛΛΟΣ το προφίλ, οι
  /// παγωμένες δεν πρέπει να φαίνονται: ο χρήστης τις έβγαλε επίτηδες από
  /// χάρτη/feed και θα ήταν έκπληξη να εμφανίζονται εδώ.
  ///
  /// Το φιλτράρισμα γίνεται στον client (όχι δεύτερο where) ώστε να μη
  /// χρειάζεται composite index — ίδια λογική με το [watchUserListings].
  Stream<List<ListingModel>> watchUserActiveListings(String uid) =>
      watchUserListings(uid)
          .map((list) => list.where((l) => l.isActive).toList());

  /// Παύση/επανενεργοποίηση αγγελίας (isActive). Σε παύση φεύγει από χάρτη/feed
  /// αλλά ΔΕΝ σβήνεται και ΔΕΝ μηδενίζει το ρολόι λήξης (σε αντίθεση με το renew).
  Future<void> setActive(String id, bool active) async =>
      await _col.doc(id).update({'isActive': active});

  Future<({List<ListingModel> listings, DocumentSnapshot? lastDoc, int fetched})>
      getPageWithCursor({DocumentSnapshot? lastDoc}) async {
    var q = _col
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);
    if (lastDoc != null) q = q.startAfterDocument(lastDoc);
    final snap = await q.get();
    final listings = _filterVisible(snap.docs);
    final newLastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
    // fetched = ΩΜΟ πλήθος (πριν το φιλτράρισμα κρυμμένων) — ώστε το hasMore να
    // μη σταματάει το pagination όταν μια σελίδα περιέχει κρυμμένες αγγελίες.
    return (listings: listings, lastDoc: newLastDoc, fetched: snap.docs.length);
  }

  /// Live stream μιας αγγελίας. Χρησιμοποιείται από την οθόνη λεπτομερειών ώστε
  /// να βλέπει ΠΑΝΤΑ φρέσκα δεδομένα (π.χ. φωτογραφίες που προστέθηκαν μετά),
  /// όπως ακριβώς κάνει ο χάρτης με το [watchActive].
  Stream<ListingModel?> watchById(String id) =>
      _col.doc(id).snapshots().map((doc) {
        if (!doc.exists) return null;
        final data = doc.data() as Map<String, dynamic>;
        if (data['isHidden'] as bool? ?? false) return null;
        return ListingModel.fromFirestore(doc);
      });

  Future<ListingModel?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    final isHidden = data['isHidden'] as bool? ?? false;
    if (isHidden) return null; // Hidden αγγελίες δεν εμφανίζονται καν
    return ListingModel.fromFirestore(doc);
  }

  /// Firestore: το `arrayContainsAny` δέχεται έως 30 τιμές.
  static const int _maxQueryTokens = 30;

  /// Οι όροι του χρήστη, κανονικοποιημένοι ΑΚΡΙΒΩΣ όπως τα searchKeywords των
  /// αγγελιών (ίδιο [ListingModel.tokenize]) — αλλιώς δεν ταιριάζουν ποτέ.
  static List<String> queryTokens(String raw) {
    final t = ListingModel.tokenize(raw);
    return t.length > _maxQueryTokens ? t.sublist(0, _maxQueryTokens) : t;
  }

  /// Πόντοι για όρο που βρίσκεται στον ΤΙΤΛΟ (έναντι 1 για οπουδήποτε αλλού).
  ///
  /// Μια αγγελία με τίτλο «Τρυπάνι» είναι προφανώς πιο σχετική από μία που
  /// απλώς αναφέρει «τρυπάνι» μέσα στην περιγραφή. Χωρίς αυτό, οι δύο έπαιρναν
  /// ακριβώς το ίδιο score και η σειρά έβγαινε ουσιαστικά τυχαία.
  static const int _titleWeight = 3;

  /// Σκορ σχετικότητας: όσο μεγαλύτερο, τόσο πιο ψηλά στα αποτελέσματα.
  ///
  /// Κάθε όρος του χρήστη μετράει μία φορά:
  /// - στον τίτλο            → [_titleWeight] πόντοι
  /// - αλλού (περιγραφή/tags/τοποθεσία) → 1 πόντος
  /// Μπόνους για αγγελία ΜΕ φωτογραφία.
  ///
  /// Σε marketplace, αγγελία χωρίς φωτό εμπνέει λιγότερη εμπιστοσύνη και
  /// αγνοείται. Το μπόνους είναι μικρό επίτηδες: σπάει την ισοπαλία υπέρ των
  /// πλήρων αγγελιών, αλλά ΔΕΝ θάβει μια πιο σχετική αγγελία χωρίς φωτό.
  static const int _photoBonus = 1;

  static int relevance(ListingModel l, List<String> tokens) {
    if (tokens.isEmpty) return 0;
    final all = l.searchKeywords.toSet();
    final titleWords = ListingModel.tokenize(l.title).toSet();
    var score = 0;
    for (final t in tokens) {
      // Πλήρης λέξη τίτλου ή ΠΡΟΘΕΜΑ λέξης τίτλου («τρυπ» → «τρυπανι»):
      // και τα δύο δείχνουν ότι ο όρος αφορά τον τίτλο.
      final hitsTitle =
          titleWords.contains(t) || titleWords.any((w) => w.startsWith(t));
      if (hitsTitle) {
        score += _titleWeight;
      } else if (all.contains(t)) {
        score += 1;
      }
    }
    // Μόνο σε αγγελίες που ήδη ταιριάζουν — δεν εμφανίζει άσχετες.
    if (score > 0 && l.imageUrls.isNotEmpty) score += _photoBonus;
    return score;
  }

  Future<List<ListingModel>> search({
    required String keyword,
    Set<String> tags = const {},
    ListingType? type,
  }) async {
    final tokens = queryTokens(keyword);

    // Ο χρήστης έγραψε κάτι, αλλά καμία λέξη δεν είναι αναζητήσιμη (π.χ. μόνο
    // 1-2 χαρακτήρες). Τα searchKeywords κρατούν λέξεις >2 χαρ., οπότε τίποτα
    // δεν θα ταίριαζε — γύρνα κενό αντί για ΟΛΕΣ τις αγγελίες.
    if (keyword.trim().isNotEmpty && tokens.isEmpty) return [];

    Query<Map<String, dynamic>> q = _col.where('isActive', isEqualTo: true);

    if (tokens.isNotEmpty) {
      // OR: κάθε αγγελία που περιέχει ΕΣΤΩ ΜΙΑ από τις λέξεις.
      //
      // ΠΡΙΝ: `arrayContains: lowerKeyword` έψαχνε ΟΛΟ το κείμενο ως ΜΙΑ λέξη.
      // Τα searchKeywords όμως είναι μεμονωμένες λέξεις, οπότε κάθε αναζήτηση
      // με 2+ λέξεις («τρυπάνι bosch») επέστρεφε ΠΑΝΤΑ 0 αποτελέσματα.
      q = q.where('searchKeywords', arrayContainsAny: tokens);
    }
    if (type != null) {
      q = q.where('type', isEqualTo: type.name);
    }

    // Μεγαλύτερο από το παλιό 40: με OR έρχονται περισσότεροι υποψήφιοι και
    // θέλουμε αρκετούς για να έχει νόημα η ταξινόμηση κατά σχετικότητα.
    final snap = await q.limit(60).get();
    var results = _filterVisible(snap.docs);

    // Multi-tag filter (OR): keep listings matching ANY selected tag.
    // Accent-insensitive: "ψάχνω" ταιριάζει και με "ψαχνω".
    if (tags.isNotEmpty) {
      final wanted = tags.map(GreekText.fold).toSet();
      results = results
          .where((l) => l.tags.any((t) => wanted.contains(GreekText.fold(t))))
          .toList();
    }
    return results;
  }

  Future<List<ListingModel>> getByTag(String tag, {int limit = 40}) async {
    final snap = await _col
        .where('isActive', isEqualTo: true)
        .where('tags', arrayContains: tag)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return _filterVisible(snap.docs);
  }

  Future<void> createListing(ListingModel l) => create(l);

  Future<void> deleteListing(String id) => deleteFully(id);

  Future<ListingModel?> getListingById(String id) => getById(id);
}
