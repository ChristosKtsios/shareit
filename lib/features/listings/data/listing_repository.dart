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

  Stream<List<ListingModel>> watchUserListings(String uid) => _col
      .where('userId', isEqualTo: uid)
      .where('isActive', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => _filterVisible(s.docs));

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

  Future<ListingModel?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    final isHidden = data['isHidden'] as bool? ?? false;
    if (isHidden) return null; // Hidden αγγελίες δεν εμφανίζονται καν
    return ListingModel.fromFirestore(doc);
  }

  Future<List<ListingModel>> search({
    required String keyword,
    Set<String> tags = const {},
    ListingType? type,
  }) async {
    final lowerKeyword = keyword.toLowerCase().trim();
    Query<Map<String, dynamic>> q = _col.where('isActive', isEqualTo: true);

    if (lowerKeyword.isNotEmpty) {
      q = q.where('searchKeywords', arrayContains: lowerKeyword);
    }
    if (type != null) {
      q = q.where('type', isEqualTo: type.name);
    }

    final snap = await q.limit(40).get();
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
