import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'listing_model.dart';

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

    // Διαγραφή εικόνων από Storage (αν αποτύχει κάποια, συνεχίζουμε)
    for (final url in urls) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }

    // Διαγραφή του document
    await _col.doc(id).delete();
  }

  /// Cleanup των ληγμένων αγγελιών του χρήστη που έχουν autoDelete=true.
  /// Καλείται στο app launch του owner.
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
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deactivate(String id) async =>
      await _col.doc(id).update({'isActive': false});

  Stream<List<ListingModel>> watchActive() => _col
      .where('isActive', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(ListingModel.fromFirestore).toList());

  Stream<List<ListingModel>> watchUserListings(String uid) => _col
      .where('userId', isEqualTo: uid)
      .where('isActive', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ListingModel.fromFirestore).toList());

  Future<({List<ListingModel> listings, DocumentSnapshot? lastDoc})>
      getPageWithCursor({DocumentSnapshot? lastDoc}) async {
    var q = _col
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);
    if (lastDoc != null) q = q.startAfterDocument(lastDoc);
    final snap = await q.get();
    final listings = snap.docs.map(ListingModel.fromFirestore).toList();
    final newLastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
    return (listings: listings, lastDoc: newLastDoc);
  }

  Future<ListingModel?> getById(String id) async {
    final doc = await _col.doc(id).get();
    return doc.exists ? ListingModel.fromFirestore(doc) : null;
  }

  Future<List<ListingModel>> search({
    required String keyword,
    String? tag,
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
    var results = snap.docs.map(ListingModel.fromFirestore).toList();

    if (tag != null && tag.isNotEmpty) {
      results = results.where((l) => l.tags.contains(tag)).toList();
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
    return snap.docs.map(ListingModel.fromFirestore).toList();
  }

  Future<void> createListing(ListingModel l) => create(l);

  /// Πραγματική διαγραφή — αντικαθιστά το παλιό deleteListing που έκανε
  /// μόνο isActive=false και άφηνε την αγγελία στη βάση.
  Future<void> deleteListing(String id) => deleteFully(id);

  Future<ListingModel?> getListingById(String id) => getById(id);
}
