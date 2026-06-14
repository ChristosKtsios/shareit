import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/listing_repository.dart';
import '../presentation/widgets/map_marker_widget.dart';
import '../presentation/widgets/map_cluster_widget.dart';

/// Default fallback location (Athens center) — χρησιμοποιείται ΜΟΝΟ
/// όταν δεν μπορούμε να πάρουμε την πραγματική τοποθεσία του χρήστη
/// (permission denied, location services off, ή GPS timeout).
/// Έτσι ο χάρτης εμφανίζεται ΠΑΝΤΑ αντί για ατέρμονο spinner.
const _defaultLocation = LatLng(37.9838, 23.7275);

class MapState {
  final Position? userPosition;
  final Set<Marker> markers;
  final ListingModel? selectedListing;
  final String? activeTagFilter;
  final double zoomLevel;
  final LatLng? clusterTapPosition;
  final double? clusterTapZoom;
  final List<ListingModel> clusterListings;
  final int clusterIndex;

  /// true όσο τρέχει η αρχικοποίηση της τοποθεσίας.
  /// Όταν γίνει false, ο χάρτης εμφανίζεται (με πραγματική ή default θέση).
  final bool isLocating;

  /// true αν δεν καταφέραμε να πάρουμε πραγματική τοποθεσία και
  /// πέσαμε στο default. Χρήσιμο για να δείξεις ένα subtle hint στον χρήστη.
  final bool usingFallbackLocation;

  const MapState({
    this.userPosition,
    this.markers = const {},
    this.selectedListing,
    this.activeTagFilter,
    this.zoomLevel = 14.0,
    this.clusterTapPosition,
    this.clusterTapZoom,
    this.clusterListings = const [],
    this.clusterIndex = 0,
    this.isLocating = true,
    this.usingFallbackLocation = false,
  });

  /// Η θέση στην οποία πρέπει να κεντράρει ο χάρτης.
  /// Επιστρέφει την πραγματική τοποθεσία αν υπάρχει, αλλιώς το default.
  LatLng get cameraTarget => userPosition != null
      ? LatLng(userPosition!.latitude, userPosition!.longitude)
      : _defaultLocation;

  MapState copyWith({
    Position? userPosition,
    Set<Marker>? markers,
    ListingModel? selectedListing,
    String? activeTagFilter,
    double? zoomLevel,
    LatLng? clusterTapPosition,
    double? clusterTapZoom,
    List<ListingModel>? clusterListings,
    int? clusterIndex,
    bool? isLocating,
    bool? usingFallbackLocation,
    bool clearSelected = false,
    bool clearFilter = false,
    bool clearClusterTap = false,
  }) =>
      MapState(
        userPosition: userPosition ?? this.userPosition,
        markers: markers ?? this.markers,
        selectedListing:
            clearSelected ? null : (selectedListing ?? this.selectedListing),
        activeTagFilter:
            clearFilter ? null : (activeTagFilter ?? this.activeTagFilter),
        zoomLevel: zoomLevel ?? this.zoomLevel,
        clusterTapPosition: clearClusterTap
            ? null
            : (clusterTapPosition ?? this.clusterTapPosition),
        clusterTapZoom:
            clearClusterTap ? null : (clusterTapZoom ?? this.clusterTapZoom),
        clusterListings: clearClusterTap
            ? const []
            : (clusterListings ?? this.clusterListings),
        clusterIndex:
            clearClusterTap ? 0 : (clusterIndex ?? this.clusterIndex),
        isLocating: isLocating ?? this.isLocating,
        usingFallbackLocation:
            usingFallbackLocation ?? this.usingFallbackLocation,
      );
}

class MapNotifier extends StateNotifier<MapState> {
  final ListingRepository _repo;
  List<ListingModel> _allListings = [];

  MapNotifier(this._repo) : super(const MapState()) {
    _init();
  }

  Future<void> _init() async {
    await _resolveLocation();
    _listenListings();
  }

  /// Προσπαθεί να βρει την πραγματική τοποθεσία του χρήστη.
  /// Αν αποτύχει σε οποιοδήποτε σημείο, πέφτει σε fallback ώστε
  /// ο χάρτης να εμφανίζεται ΠΑΝΤΑ (ποτέ ατέρμονος spinner).
  Future<void> _resolveLocation() async {
    try {
      // 1) Location services ενεργά;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _fallback();
        return;
      }

      // 2) Permission flow
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _fallback();
        return;
      }

      // 3) Γρήγορο cached fix πρώτα (ακαριαίο, αν υπάρχει).
      //    Δείχνουμε αμέσως κάτι ενώ περιμένουμε ακριβές fix.
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        state = state.copyWith(
          userPosition: lastKnown,
          isLocating: false,
          usingFallbackLocation: false,
        );
      }

      // 4) Ακριβές fix ΜΕ timeout — το κρίσιμο fix.
      //    Χωρίς timeLimit, σε πραγματικό Samsung/Android 15 το
      //    getCurrentPosition μπορεί να κρεμάσει επ' αόριστον.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      state = state.copyWith(
        userPosition: pos,
        isLocating: false,
        usingFallbackLocation: false,
      );
    } catch (e) {
      // Timeout ή οποιοδήποτε άλλο σφάλμα GPS.
      // Αν είχαμε ήδη πάρει lastKnown, το κρατάμε. Αλλιώς fallback.
      if (state.userPosition == null) {
        _fallback();
      } else {
        state = state.copyWith(isLocating: false);
      }
    }
  }

  /// Πέφτει στο default location ώστε ο χάρτης να εμφανιστεί.
  void _fallback() {
    state = state.copyWith(
      isLocating: false,
      usingFallbackLocation: true,
    );
  }

  /// Public: ξανα-προσπάθεια εντοπισμού (π.χ. από το "locate me" κουμπί).
  Future<void> retryLocation() async {
    state = state.copyWith(isLocating: true);
    await _resolveLocation();
  }

  void _listenListings() {
    _repo.watchActive().listen((listings) async {
      _allListings = listings;
      await _rebuildMarkers();
    });
  }

  double _radiusForZoom(double zoom) {
    if (zoom >= 17) return 10;
    if (zoom >= 15) return 30;
    if (zoom >= 12) return 100;
    if (zoom >= 10) return 500;
    return 1500;
  }
  int _minClusterSize(double zoom) {
    return 2;
  }

  /// Υπολογίζει το μέγεθος (scale) των markers με βάση το zoom.
  /// - Zoom out (μικρό zoom) -> μικρά markers (min 0.55)
  /// - Zoom in (μεγάλο zoom) -> φτάνει σε max 1.0 και ΔΕΝ μεγαλώνει άλλο
  /// Γραμμική παρεμβολή μεταξύ zoom 10 (0.55) και zoom 16 (1.0).
  double _markerScaleForZoom(double zoom) {
    const minScale = 0.55;
    const maxScale = 1.0;
    const minZoom = 10.0;
    const maxZoom = 16.0;

    if (zoom <= minZoom) return minScale;
    if (zoom >= maxZoom) return maxScale;

    final t = (zoom - minZoom) / (maxZoom - minZoom);
    return minScale + (maxScale - minScale) * t;
  }

  void setClusterIndex(int i) {
    state = state.copyWith(clusterIndex: i);
    if (i < state.clusterListings.length) {
      final listing = state.clusterListings[i];
      state = state.copyWith(
        clusterTapPosition: LatLng(
            listing.location.latitude, listing.location.longitude),
      );
    }
  }

  Future<void> _rebuildMarkers() async {
    final filtered = state.activeTagFilter != null
        ? _allListings
            .where((l) => l.tags.contains(state.activeTagFilter))
            .toList()
        : _allListings;

    final radius = _radiusForZoom(state.zoomLevel);
    final minSize = _minClusterSize(state.zoomLevel);
    final scale = _markerScaleForZoom(state.zoomLevel);

    final clusters = radius == 0
        ? filtered.map((l) => [l]).toList()
        : _clusterListings(filtered, radiusMeters: radius, minSize: minSize);

    final markers = <Marker>{};

    for (final cluster in clusters) {
      if (cluster.length == 1) {
        final listing = cluster.first;
        final icon =
            await MapMarkerBuilder.buildMarker(listing: listing, scale: scale);
        markers.add(Marker(
          markerId: MarkerId(listing.id),
          position:
              LatLng(listing.location.latitude, listing.location.longitude),
          icon: icon,
          onTap: () => state = state.copyWith(selectedListing: listing),
        ));
      } else {
        final center = _clusterCenter(cluster);
        final offerCount =
            cluster.where((l) => l.type == ListingType.offer).length;
        final seekCount = cluster.length - offerCount;
        final icon = await MapClusterBuilder.build(
          count: cluster.length,
          listings: cluster,
          offerCount: offerCount,
          seekCount: seekCount,
          scale: scale,
        );
        final clusterId = 'cluster_${cluster.map((l) => l.id).join('_')}';
        markers.add(Marker(
          markerId: MarkerId(clusterId),
          position: center,
          icon: icon,
          onTap: () {
            print('🟠 CLUSTER TAPPED: ${cluster.length} listings');
            state = state.copyWith(
              clusterListings: cluster,
              clusterIndex: 0,
              clusterTapPosition: center,
            );
          },
        ));
      }
    }

    state = state.copyWith(markers: markers);
  }

  List<List<ListingModel>> _clusterListings(
    List<ListingModel> listings, {
    required double radiusMeters,
    required int minSize,
  }) {
    final clusters = <List<ListingModel>>[];
    final processed = <String>{};

    for (final listing in listings) {
      if (processed.contains(listing.id)) continue;
      final cluster = [listing];
      processed.add(listing.id);

      for (final other in listings) {
        if (processed.contains(other.id)) continue;
        final dist = Geolocator.distanceBetween(
          listing.location.latitude,
          listing.location.longitude,
          other.location.latitude,
          other.location.longitude,
        );
        if (dist <= radiusMeters) {
          cluster.add(other);
          processed.add(other.id);
        }
      }

      if (cluster.length < minSize) {
        for (final l in cluster) {
          clusters.add([l]);
        }
      } else {
        clusters.add(cluster);
      }
    }
    return clusters;
  }

  LatLng _clusterCenter(List<ListingModel> listings) {
    final lat =
        listings.map((l) => l.location.latitude).reduce((a, b) => a + b) /
            listings.length;
    final lng =
        listings.map((l) => l.location.longitude).reduce((a, b) => a + b) /
            listings.length;
    return LatLng(lat, lng);
  }

  Future<void> updateZoom(double zoom) async {
    if ((zoom - state.zoomLevel).abs() > 0.5) {
      state = state.copyWith(zoomLevel: zoom);
      await _rebuildMarkers();
    }
  }

  void clearClusterTap() => state = state.copyWith(clearClusterTap: true);

  void setTagFilter(String? tag) {
    state = state.copyWith(activeTagFilter: tag, clearFilter: tag == null);
    _rebuildMarkers();
  }

  void clearSelected() => state = state.copyWith(clearSelected: true);
}

final mapProvider = StateNotifierProvider<MapNotifier, MapState>(
    (ref) => MapNotifier(ListingRepository()));
