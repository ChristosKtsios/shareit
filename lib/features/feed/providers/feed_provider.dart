import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/location_permission_gate.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/listing_repository.dart';
import '../../search/presentation/widgets/search_filters_widget.dart';

/// Όρια ακτίνας φίλτρου feed. Το «Παντού» (χωρίς φίλτρο απόστασης) αναπαρίσταται
/// με το [kFeedEverywhereKm] — το τελευταίο σκαλί του slider, πάνω από τα 100 χλμ.
const double kFeedMinKm = 1;
const double kFeedMaxKm = 100;
const double kFeedEverywhereKm = 101;

class FeedState {
  final List<ListingModel> listings;
  final String? tagFilter;
  final ListingType? type;
  final SearchSort sort;
  final double distanceKm; // 1–100 χλμ, ή kFeedEverywhereKm (101) = «Παντού»
  final Position? userPosition;
  final bool isLoading;
  final bool hasMore;
  final DocumentSnapshot? lastDoc;

  const FeedState({
    this.listings = const [],
    this.tagFilter,
    this.type,
    this.sort = SearchSort.recent,
    this.distanceKm = kFeedEverywhereKm,
    this.userPosition,
    this.isLoading = false,
    this.hasMore = true,
    this.lastDoc,
  });

  List<ListingModel> get filtered {
    // Αντίγραφο: το state.listings μπορεί να είναι const [] (unmodifiable) και
    // το sort() παρακάτω θα το τροποποιούσε in-place → «Cannot modify an
    // unmodifiable list». Το copy το κάνει πάντα modifiable ΚΑΙ προστατεύει το
    // state από in-place μετάλλαξη.
    var list = [...listings];

    if (type != null) list = list.where((l) => l.type == type).toList();
    if (tagFilter != null) {
      list = list.where((l) => l.tags.contains(tagFilter)).toList();
    }

    // Φίλτρο απόστασης: εφαρμόζεται όταν έχουμε θέση χρήστη ΚΑΙ η ακτίνα είναι
    // εντός 1–100 χλμ. Στο «Παντού» (distanceKm > 100) ΔΕΝ εφαρμόζεται φίλτρο →
    // όλες οι αγγελίες (το pagination φορτώνει σελίδα-σελίδα, χωρίς lag).
    if (userPosition != null && distanceKm <= kFeedMaxKm) {
      list = list.where((l) {
        final dist = Geolocator.distanceBetween(
          userPosition!.latitude,
          userPosition!.longitude,
          l.location.latitude,
          l.location.longitude,
        );
        return dist <= (distanceKm * 1000);
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
    double? distanceKm,
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
        distanceKm: distanceKm ?? this.distanceKm,
        userPosition: userPosition ?? this.userPosition,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        lastDoc: clearLastDoc ? null : (lastDoc ?? this.lastDoc),
      );
}

class FeedNotifier extends StateNotifier<FeedState> {
  final _repo = ListingRepository();

  static const _distancePrefKey = 'feed_distance_km';

  FeedNotifier() : super(const FeedState()) {
    _init();
  }

  Future<void> _init() async {
    await _loadDistance();
    await _loadLocation();
    await loadFirstPage();
  }

  /// Φόρτωση της τελευταίας αποθηκευμένης απόστασης (persist). Clamp στα όρια
  /// 1–100 για ασφάλεια, ώστε να μη φορτώνει υπερβολικά δεδομένα.
  Future<void> _loadDistance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final km = prefs.getDouble(_distancePrefKey);
      if (km != null) {
        state = state.copyWith(
            distanceKm: km.clamp(kFeedMinKm, kFeedEverywhereKm));
      }
    } catch (_) {}
  }

  Future<void> _loadLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final perm = await LocationPermissionGate.ensure();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
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
      hasMore: result.fetched >= 20,
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
      hasMore: result.fetched >= 20,
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

  Future<void> setDistance(double km) async {
    final clamped = km.clamp(kFeedMinKm, kFeedEverywhereKm);
    state = state.copyWith(distanceKm: clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_distancePrefKey, clamped);
    } catch (_) {}
  }

  Future<void> refresh() => loadFirstPage();
}

final feedProvider =
    StateNotifierProvider<FeedNotifier, FeedState>((ref) => FeedNotifier());
