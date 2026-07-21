import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/location_permission_gate.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/listing_repository.dart';
import '../presentation/widgets/search_filters_widget.dart';
export 'package:shareit/features/search/presentation/widgets/search_filters_widget.dart'
    show SearchSort;

class SearchState {
  final String query;
  final Set<String> tags;
  final ListingType? type;
  final SearchSort sort;
  final double distanceKm;
  final List<ListingModel> results;
  final bool loading;
  final String? error;

  const SearchState({
    this.query = '',
    this.tags = const {},
    this.type,
    this.sort = SearchSort.recent,
    this.distanceKm = 800,
    this.results = const [],
    this.loading = false,
    this.error,
  });

  SearchState copyWith({
    String? query,
    Set<String>? tags,
    ListingType? type,
    SearchSort? sort,
    double? distanceKm,
    List<ListingModel>? results,
    bool? loading,
    String? error,
    bool clearType = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        tags: tags ?? this.tags,
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
    if (query.trim().isEmpty && state.tags.isEmpty) {
      state = state.copyWith(results: [], loading: false, query: '');
      return;
    }
    state = state.copyWith(query: query, loading: true, error: null);
    try {
      // Αντίγραφο (modifiable): το sort() παρακάτω δεν πρέπει να τροποποιεί τη
      // λίστα που επιστρέφει το repository (μπορεί να είναι read-only).
      var results = List<ListingModel>.of(await ListingRepository().search(
        keyword: query,
        tags: state.tags,
        type: state.type,
      ));

      // Φέρε τη θέση ΜΙΑ φορά αν τη χρειάζεται είτε το φίλτρο απόστασης είτε
      // η ταξινόμηση "κοντινά" — αποφεύγουμε διπλό (αργό) GPS fix.
      final needsPosition =
          state.distanceKm < 800 || state.sort == SearchSort.nearest;
      final pos = needsPosition ? await _getUserPosition() : null;

      if (state.distanceKm < 800 && pos != null) {
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

      if (state.sort == SearchSort.nearest) {
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
        // Προεπιλογή: ΣΧΕΤΙΚΟΤΗΤΑ. Όσο περισσότερες λέξεις του ερωτήματος
        // περιέχει η αγγελία, τόσο πιο ψηλά· σε ισοβαθμία, η νεότερη πρώτη.
        // Χωρίς όρους (π.χ. μόνο φίλτρο tag) κρατάμε την παλιά ταξινόμηση
        // κατά ημερομηνία, ώστε να μην αλλάξει η υπάρχουσα συμπεριφορά.
        final tokens = ListingRepository.queryTokens(query);
        if (tokens.isEmpty) {
          results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        } else {
          results.sort((a, b) {
            final byScore = ListingRepository.relevance(b, tokens)
                .compareTo(ListingRepository.relevance(a, tokens));
            return byScore != 0 ? byScore : b.createdAt.compareTo(a.createdAt);
          });
        }
      }

      state = state.copyWith(results: results, loading: false);
    } catch (e) {
      state = state.copyWith(
          loading: false, error: 'srch.searchError'.tr());
    }
  }

  Future<Position?> _getUserPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final perm = await LocationPermissionGate.ensure();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      // ΓΡΗΓΟΡΟ: πρώτα η τελευταία γνωστή θέση (ακαριαία). Μόνο αν λείπει,
      // ζητάμε νέο fix με medium accuracy + timeout, ώστε να μη «κολλάει» η
      // αναζήτηση περιμένοντας high-accuracy GPS.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Toggle a tag in/out of the active filter set. Tapping a selected tag
  /// removes it; multiple tags can be active at once.
  void toggleTag(String tag) {
    final next = Set<String>.from(state.tags);
    if (!next.add(tag)) next.remove(tag); // add() is false if already present
    state = state.copyWith(tags: next);
    search(state.query);
  }

  void clearTags() {
    state = state.copyWith(tags: const {});
    search(state.query);
  }

  void setType(ListingType? t) {
    state = state.copyWith(type: t, clearType: t == null);
    if (state.query.isNotEmpty || state.tags.isNotEmpty) search(state.query);
  }

  void setSort(SearchSort s) {
    state = state.copyWith(sort: s);
    if (state.query.isNotEmpty || state.tags.isNotEmpty) search(state.query);
  }

  void setDistance(double km) {
    state = state.copyWith(distanceKm: km);
    if (state.query.isNotEmpty || state.tags.isNotEmpty) search(state.query);
  }

  void clear() => state = const SearchState();
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>(
    (ref) => SearchNotifier());
