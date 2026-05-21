import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/listing_repository.dart';
import '../presentation/widgets/search_filters_widget.dart';
export 'package:shareit/features/search/presentation/widgets/search_filters_widget.dart'
    show SearchSort;

class SearchState {
  final String query;
  final String? tagFilter;
  final ListingType? type;
  final SearchSort sort;
  final double distanceKm;
  final List<ListingModel> results;
  final bool loading;
  final String? error;

  const SearchState({
    this.query = '',
    this.tagFilter,
    this.type,
    this.sort = SearchSort.recent,
    this.distanceKm = 800,
    this.results = const [],
    this.loading = false,
    this.error,
  });

  SearchState copyWith({
    String? query,
    String? tagFilter,
    ListingType? type,
    SearchSort? sort,
    double? distanceKm,
    List<ListingModel>? results,
    bool? loading,
    String? error,
    bool clearTag = false,
    bool clearType = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        tagFilter: clearTag ? null : (tagFilter ?? this.tagFilter),
        type: clearType ? null : (type ?? this.type),
        sort: sort ?? this.sort,
        distanceKm: distanceKm ?? this.distanceKm,
        results: results ?? this.results,
        loading: loading ?? this.loading,
        error: error,
      );
}

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier() : super(const SearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty && state.tagFilter == null) {
      state = state.copyWith(results: [], loading: false, query: '');
      return;
    }
    state = state.copyWith(query: query, loading: true, error: null);
    try {
      var results = await ListingRepository().search(
        keyword: query,
        tag: state.tagFilter,
        type: state.type,
      );

      if (state.distanceKm < 800) {
        final pos = await _getUserPosition();
        if (pos != null) {
          results = results.where((l) {
            final dist = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              l.location.latitude,
              l.location.longitude,
            );
            return dist <= (state.distanceKm * 1000);
          }).toList();
        }
      }

      if (state.sort == SearchSort.nearest) {
        final pos = await _getUserPosition();
        if (pos != null) {
          results.sort((a, b) {
            final da = Geolocator.distanceBetween(pos.latitude, pos.longitude,
                a.location.latitude, a.location.longitude);
            final db = Geolocator.distanceBetween(pos.latitude, pos.longitude,
                b.location.latitude, b.location.longitude);
            return da.compareTo(db);
          });
        }
      } else {
        results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      state = state.copyWith(results: results, loading: false);
    } catch (e) {
      state = state.copyWith(
          loading: false, error: 'Σφάλμα αναζήτησης. Δοκίμασε ξανά.');
    }
  }

  Future<Position?> _getUserPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      return null;
    }
  }

  void setTagFilter(String? tag) {
    state = state.copyWith(tagFilter: tag, clearTag: tag == null);
    if (state.query.isNotEmpty || tag != null) search(state.query);
  }

  void setType(ListingType? t) {
    state = state.copyWith(type: t, clearType: t == null);
    if (state.query.isNotEmpty) search(state.query);
  }

  void setSort(SearchSort s) {
    state = state.copyWith(sort: s);
    if (state.query.isNotEmpty) search(state.query);
  }

  void setDistance(double km) {
    state = state.copyWith(distanceKm: km);
    if (state.query.isNotEmpty) search(state.query);
  }

  void clear() => state = const SearchState();
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>(
    (ref) => SearchNotifier());
