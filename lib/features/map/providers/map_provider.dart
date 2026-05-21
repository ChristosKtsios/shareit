import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../listings/data/listing_model.dart';
import '../../listings/data/listing_repository.dart';
import '../presentation/widgets/map_marker_widget.dart';
import '../presentation/widgets/map_cluster_widget.dart';

class MapState {
  final Position? userPosition;
  final Set<Marker> markers;
  final ListingModel? selectedListing;
  final String? activeTagFilter;
  final double zoomLevel;
  final LatLng? clusterTapPosition;
  final double? clusterTapZoom;

  const MapState({
    this.userPosition,
    this.markers = const {},
    this.selectedListing,
    this.activeTagFilter,
    this.zoomLevel = 14.0,
    this.clusterTapPosition,
    this.clusterTapZoom,
  });

  MapState copyWith({
    Position? userPosition,
    Set<Marker>? markers,
    ListingModel? selectedListing,
    String? activeTagFilter,
    double? zoomLevel,
    LatLng? clusterTapPosition,
    double? clusterTapZoom,
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
      );
}

class MapNotifier extends StateNotifier<MapState> {
  final ListingRepository _repo;
  List<ListingModel> _allListings = [];

  MapNotifier(this._repo) : super(const MapState()) {
    _init();
  }

  Future<void> _init() async {
    await _requestLocation();
    _listenListings();
  }

  Future<void> _requestLocation() async {
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
  }

  void _listenListings() {
    _repo.watchActive().listen((listings) async {
      _allListings = listings;
      await _rebuildMarkers();
    });
  }

  double _radiusForZoom(double zoom) {
    if (zoom >= 15) return 0;
    if (zoom >= 12) return 50;
    if (zoom >= 10) return 300;
    return 1000;
  }

  int _minClusterSize(double zoom) {
    if (zoom >= 12) return 5;
    return 2;
  }

  Future<void> _rebuildMarkers() async {
    final filtered = state.activeTagFilter != null
        ? _allListings
            .where((l) => l.tags.contains(state.activeTagFilter))
            .toList()
        : _allListings;

    final radius = _radiusForZoom(state.zoomLevel);
    final minSize = _minClusterSize(state.zoomLevel);

    final clusters = radius == 0
        ? filtered.map((l) => [l]).toList()
        : _clusterListings(filtered, radiusMeters: radius, minSize: minSize);

    final markers = <Marker>{};

    for (final cluster in clusters) {
      if (cluster.length == 1) {
        final listing = cluster.first;
        final icon = await MapMarkerBuilder.buildMarker(listing: listing);
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
        );
        final clusterId = 'cluster_${cluster.map((l) => l.id).join('_')}';
        markers.add(Marker(
          markerId: MarkerId(clusterId),
          position: center,
          icon: icon,
          onTap: () {
            state = state.copyWith(
              clusterTapPosition: center,
              clusterTapZoom: state.zoomLevel + 3,
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
