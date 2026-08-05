import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/providers/blocked_users_provider.dart';
import '../../../core/services/error_logger.dart';
import '../../../core/services/location_permission_gate.dart';
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
  final Ref _ref;
  List<ListingModel> _allListings = [];

  /// UIDs που έχει μπλοκάρει ο χρήστης — οι αγγελίες τους δεν μπαίνουν στα markers.
  Set<String> _blocked = const {};

  MapNotifier(this._repo, this._ref) : super(const MapState()) {
    _init();
  }

  Future<void> _init() async {
    _watchBlocked();
    await _resolveLocation();
    _listenListings();
  }

  void _watchBlocked() {
    _ref.listen<AsyncValue<Set<String>>>(
      blockedUidsProvider,
      (_, next) {
        final b = next.valueOrNull ?? const <String>{};
        // Ίδιο σύνολο → μην ξαναχτίζεις markers χωρίς λόγο (ακριβό).
        if (b.length == _blocked.length && b.containsAll(_blocked)) return;
        _blocked = b;
        if (mounted) _rebuildMarkers();
      },
      fireImmediately: true,
    );
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

      // 2) Permission flow (shows in-app rationale before the OS prompt)
      final perm = await LocationPermissionGate.ensure();
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

  /// Public: ξανα-προσπάθεια εντοπισμού (π.χ. από το "Δοκίμασε ξανά" hint).
  Future<void> retryLocation() async {
    state = state.copyWith(isLocating: true);
    await _resolveLocation();
  }

  /// Public: ανανέωση τοποθεσίας για το "locate me" κουμπί ΧΩΡΙΣ να ξεφορτωθεί
  /// ο χάρτης (δεν αγγίζει το isLocating, ώστε ο GoogleMapController να μείνει
  /// έγκυρος και το animateCamera να δουλέψει). Επιστρέφει το σημείο για
  /// κεντράρισμα, ή null αν δεν βρέθηκε θέση.
  Future<LatLng?> centerOnUser() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _existingTarget();
      }
      final perm = await LocationPermissionGate.ensure();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return _existingTarget();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      state = state.copyWith(
        userPosition: pos,
        usingFallbackLocation: false,
        isLocating: false,
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      // Timeout/σφάλμα: κεντράρισε στην τελευταία γνωστή θέση αν υπάρχει.
      return _existingTarget();
    }
  }

  LatLng? _existingTarget() {
    final p = state.userPosition;
    return p != null ? LatLng(p.latitude, p.longitude) : null;
  }

  StreamSubscription<List<ListingModel>>? _listingsSub;

  void _listenListings() {
    _listingsSub = _repo.watchActive().listen(
      (listings) async {
        if (!mounted) return;
        _allListings = listings;
        await _rebuildMarkers();
      },
      // permission-denied / network σφάλμα στο stream ΔΕΝ πρέπει να γίνεται
      // fatal — απλώς δεν ενημερώνουμε τα markers.
      onError: (e, s) => logSwallowed(e, s, 'map watchActive'),
    );
  }

  @override
  void dispose() {
    _listingsSub?.cancel();
    super.dispose();
  }

  /// Πλάτος της κάρτας-marker σε logical pixels, σε scale 1.0.
  /// ΠΡΕΠΕΙ να ταιριάζει με το `width` στο map_marker_widget.dart (180 * scale).
  static const double _markerWidthPx = 180.0;

  /// Μικρό περιθώριο ώστε οι κάρτες να μην ακουμπάνε ούτε οριακά.
  static const double _clusterPadding = 1.15;

  /// Πόσα ΜΕΤΡΑ αντιστοιχούν σε ένα logical pixel του χάρτη.
  ///
  /// Τυπικός τύπος Web Mercator (Google Maps): στο zoom z ο κόσμος έχει
  /// πλάτος 256·2^z pixels, άρα η κλίμακα εξαρτάται και από το γεωγραφικό
  /// πλάτος (οι μεσημβρινοί «στενεύουν» όσο ανεβαίνεις).
  double _metersPerPixel(double zoom, double latitude) =>
      156543.03392 * math.cos(latitude * math.pi / 180) / math.pow(2, zoom);

  /// Ακτίνα ομαδοποίησης — προκύπτει από το ΠΟΣΟ ΧΩΡΟ ΠΙΑΝΕΙ Η ΚΑΡΤΑ ΣΤΗΝ
  /// ΟΘΟΝΗ, όχι από αυθαίρετα μέτρα.
  ///
  /// ΠΡΙΝ ήταν σταθερές τιμές (10/30/100/500/1500m) διαλεγμένες «με το μάτι».
  /// Το πρόβλημα: η επικάλυψη συμβαίνει σε PIXELS, όχι σε μέτρα. Στο zoom 13
  /// μία κάρτα 140px «σκεπάζει» ~2.100m εδάφους, ενώ ομαδοποιούσαμε μόνο κάτω
  /// από 100m — δηλαδή ~21x μικρότερη ακτίνα από την πραγματικά αναγκαία. Έτσι
  /// δύο αγγελίες με 1 χλμ απόσταση εμφανίζονταν ως δύο κάρτες που
  /// επικαλύπτονταν σχεδόν πλήρως. Το ίδιο σφάλμα (14x–21x) σε ΚΑΘΕ zoom.
  ///
  /// Με τον υπολογισμό αυτό διορθώνεται αυτόματα σε κάθε zoom, και δεν
  /// ξαναχαλάει αν αλλάξει το μέγεθος της κάρτας (αρκεί να ενημερωθεί το
  /// [_markerWidthPx]).
  double _radiusForZoom(double zoom, double latitude) {
    final widthPx = _markerWidthPx * _markerScaleForZoom(zoom);
    return widthPx * _metersPerPixel(zoom, latitude) * _clusterPadding;
  }

  int _minClusterSize(double zoom) {
    return 2;
  }

  /// Πόσο «σφιχτό» είναι το clustering ανάλογα με το ΠΛΗΘΟΣ των ορατών
  /// αγγελιών. Με λίγες αγγελίες θέλουμε ΧΑΛΑΡΟ clustering (να φαίνονται
  /// ξεχωριστά)· με πολλές, ΣΦΙΧΤΟ (να μη γεμίζει ο χάρτης). Πολλαπλασιάζει την
  /// ακτίνα ομαδοποίησης: 0.7 (λίγες) → 1.35 (πολλές), γραμμικά.
  double _densityFactor(int count) {
    const fewCount = 12, manyCount = 60;
    const looseFactor = 0.7, tightFactor = 1.35;
    if (count <= fewCount) return looseFactor;
    if (count >= manyCount) return tightFactor;
    final t = (count - fewCount) / (manyCount - fewCount);
    return looseFactor + (tightFactor - looseFactor) * t;
  }

  /// Οι τελευταίες φιλτραρισμένες αγγελίες (για το global swipe carousel).
  List<ListingModel> _lastFiltered = const [];

  double _sqDist(LatLng a, ListingModel b) {
    final dx = a.latitude - b.location.latitude;
    final dy = a.longitude - b.location.longitude;
    return dx * dx + dy * dy;
  }

  /// Χτίζει τη λίστα του carousel ξεκινώντας από το cluster που πατήθηκε και
  /// συνεχίζοντας με ΟΛΕΣ τις υπόλοιπες αγγελίες κατά αύξουσα απόσταση από το
  /// κέντρο του cluster. Έτσι, με swipe πέρα από τις αγγελίες του cluster ο
  /// χρήστης «ταξιδεύει» στα επόμενα (κοντινότερα) clusters και ο χάρτης
  /// ακολουθεί (setClusterIndex → animateCamera).
  List<ListingModel> _orderedFromCluster(
      List<ListingModel> cluster, LatLng center) {
    final inCluster = cluster.map((l) => l.id).toSet();
    final rest =
        _lastFiltered.where((l) => !inCluster.contains(l.id)).toList()
          ..sort((a, b) => _sqDist(center, a).compareTo(_sqDist(center, b)));
    return [...cluster, ...rest];
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
    // Οι αγγελίες μπλοκαρισμένων χρηστών δεν εμφανίζονται στον χάρτη.
    final visible = _blocked.isEmpty
        ? _allListings
        : _allListings.where((l) => !_blocked.contains(l.userId)).toList();

    final filtered = state.activeTagFilter != null
        ? visible.where((l) => l.tags.contains(state.activeTagFilter)).toList()
        : visible;

    // Το γεωγραφικό πλάτος χρειάζεται γιατί η κλίμακα του Mercator αλλάζει με
    // αυτό. Παίρνουμε τη θέση του χρήστη· αν λείπει, το πλάτος της πρώτης
    // αγγελίας· αλλιώς το προεπιλεγμένο κέντρο (Αθήνα). Η ακρίβεια δεν είναι
    // κρίσιμη — μικρές διαφορές πλάτους αλλάζουν ελάχιστα την ακτίνα.
    final lat = state.userPosition?.latitude ??
        (filtered.isNotEmpty
            ? filtered.first.location.latitude
            : _defaultLocation.latitude);

    _lastFiltered = filtered;

    final radius =
        _radiusForZoom(state.zoomLevel, lat) * _densityFactor(filtered.length);
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
            // Global carousel: ξεκινά από τις αγγελίες του cluster και συνεχίζει
            // στις υπόλοιπες κατά απόσταση — swipe «ταξιδεύει» στα επόμενα
            // clusters με τον χάρτη να ακολουθεί.
            state = state.copyWith(
              clusterListings: _orderedFromCluster(cluster, center),
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
    (ref) => MapNotifier(ListingRepository(), ref));
