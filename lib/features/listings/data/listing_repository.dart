import 'package:cloud_firestore/cloud_firestore.dart';
import 'listing_model.dart';

class ListingRepository {
  final _col = FirebaseFirestore.instance.collection('listings');
  static const int _pageSize = 20;

  Future<void> create(ListingModel l) async => await _col.add(l.toFirestore());

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

  /// Search με keyword + προαιρετικά filter τύπου και tag.
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

  /// Παίρνει όλες τις αγγελίες με συγκεκριμένο tag
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
  Future<void> deleteListing(String id) => deactivate(id);
  Future<ListingModel?> getListingById(String id) => getById(id);
}
