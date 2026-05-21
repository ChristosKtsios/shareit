import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/listing_model.dart';
import '../data/listing_repository.dart';
import '../../auth/providers/auth_provider.dart';

final listingRepoProvider = Provider<ListingRepository>((ref) => ListingRepository());

final activeListingsProvider = StreamProvider<List<ListingModel>>((ref) =>
    ref.watch(listingRepoProvider).watchActive());

final myListingsProvider = StreamProvider<List<ListingModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream<List<ListingModel>>.empty();
  return ref.watch(listingRepoProvider).watchUserListings(uid);
});

final listingByIdProvider = FutureProvider.family<ListingModel?, String>((ref, id) =>
    ref.watch(listingRepoProvider).getById(id));
