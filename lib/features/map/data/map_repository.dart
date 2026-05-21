import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../listings/data/listing_model.dart';

class MapRepository {
  final _db = FirebaseFirestore.instance;

  Stream<List<ListingModel>> watchListingsNear({
    required Position position, double radiusKm = 10, ListingCategory? category,
  }) {
    var q = _db.collection('listings').where('isActive', isEqualTo: true);
    if (category != null) q = q.where('category', isEqualTo: category.name);
    return q.snapshots().map((snap) => snap.docs
        .map(ListingModel.fromFirestore)
        .where((l) {
          final dist = Geolocator.distanceBetween(position.latitude, position.longitude,
              l.location.latitude, l.location.longitude);
          return dist <= radiusKm * 1000;
        }).toList());
  }
}
