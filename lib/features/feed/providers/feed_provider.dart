import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/listing_repository.dart';
import '../../search/presentation/widgets/search_filters_widget.dart';

class FeedState {
  final List<ListingModel> listings;
  final String? tagFilter;
  final ListingType? type;
  final SearchSort sort;
  final SearchDistance distance;
  final Position? userPosition;
  final bool isLoading;
  final bool hasMore;
  final DocumentSnapshot? lastDoc;

  const FeedState({
    this.listings = const [],
    this.tagFilter,
    this.type,
    this.sort = SearchSort.recent,
    this.distance = SearchDistance.all,
    this.userPosition,
    this.isLoading = false,
    this.hasMore = true,
    this.lastDoc,
  });

  List<ListingModel> get filtered {
    var list = listings;

    if (type != null) list = list.where((l) => l.type == type).toList();
    if (tagFilter != null) {
      list = list.where((l) => l.tags.contains(tagFilter)).toList();
    }

    if (distance != SearchDistance.all &&
        userPosition != null &&
        distance.km != null) {
      list = list.where((l) {
        final dist = Geolocator.distanceBetween(
          userPosition!.latitude,
          userPosition!.longitude,
          l.location.latitude,
          l.location.longitude,
        );
        return dist <= (distance.km! * 1000);
      }).toList();
    }

    if (sort == SearchSort.nearest && userPosition != null) {
      list.sort((a, b) {
        final da = Geolocator.distanceBetween(userPosition!.latitude,
            userPosition!.longitude, a.location.latitude, a.location.longitude);
        final db = Geolocator.distanceBetween(userPosition!.latitude,
            userPosition!.longitude, b.location.latitude, b.location.longitude);
        return da.compareTo(db);
      });
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return list;
  }

  FeedState copyWith({
    List<ListingModel>? listings,
    String? tagFilter,
    ListingType? type,
    SearchSort? sort,
    SearchDistance? distance,
    Position? userPosition,
    bool? isLoading,
    bool? hasMore,
    DocumentSnapshot? lastDoc,
    bool clearTag = false,
    bool clearType = false,
    bool clearLastDoc = false,
  }) =>
      FeedState(
        listings: listings ?? this.listings,
        tagFilter: clearTag ? null : (tagFilter ?? this.tagFilter),
        type: clearType ? null : (type ?? this.type),
        sort: sort ?? this.sort,
        distance: distance ?? this.distance,
        userPosition: userPosition ?? this.userPosition,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        lastDoc: clearLastDoc ? null : (lastDoc ?? this.lastDoc),
      );
}

class FeedNotifier extends StateNotifier<FeedState> {
  final _repo = ListingRepository();

  FeedNotifier() : super(const FeedState()) {
    _init();
  }

  Future<void> _init() async {
    await _loadLocation();
    await loadFirstPage();
  }

  Future<void> _loadLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      state = state.copyWith(userPosition: pos);
    } catch (_) {}
  }

  Future<void> loadFirstPage() async {
    state = state.copyWith(
        isLoading: true, listings: [], hasMore: true, clearLastDoc: true);

    final result = await _repo.getPageWithCursor();
    state = state.copyWith(
      listings: result.listings,
      lastDoc: result.lastDoc,
      hasMore: result.listings.length >= 20,
      isLoading: false,
    );
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);

    final result = await _repo.getPageWithCursor(lastDoc: state.lastDoc);

    state = state.copyWith(
      listings: [...state.listings, ...result.listings],
      lastDoc: result.lastDoc,
      hasMore: result.listings.length >= 20,
      isLoading: false,
    );
  }

  void setTagFilter(String? tag) {
    state = state.copyWith(tagFilter: tag, clearTag: tag == null);
  }

  void setType(ListingType? t) {
    state = state.copyWith(type: t, clearType: t == null);
  }

  void setSort(SearchSort s) {
    state = state.copyWith(sort: s);
  }

  void setDistance(SearchDistance d) {
    state = state.copyWith(distance: d);
  }

  Future<void> refresh() => loadFirstPage();
}

final feedProvider =
    StateNotifierProvider<FeedNotifier, FeedState>((ref) => FeedNotifier());
