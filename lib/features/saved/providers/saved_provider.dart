import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../listings/data/listing_model.dart';
import '../../auth/providers/auth_provider.dart';

final savedListingsProvider = StreamProvider<List<ListingModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream<List<ListingModel>>.empty();
  final db = FirebaseFirestore.instance;
  return db.collection('users').doc(uid).snapshots().asyncMap((snap) async {
    final ids = List<String>.from(snap.data()?['savedListingIds'] ?? []);
    if (ids.isEmpty) return <ListingModel>[];
    final snaps = await Future.wait(ids.map((id) => db.collection('listings').doc(id).get()));
    return snaps.where((d) => d.exists).map(ListingModel.fromFirestore).toList();
  });
});

Future<void> toggleSaved(String uid, String listingId, bool save) async =>
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'savedListingIds': save
          ? FieldValue.arrayUnion([listingId])
          : FieldValue.arrayRemove([listingId]),
    });
