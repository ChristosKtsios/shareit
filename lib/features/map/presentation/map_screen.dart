import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/error_logger.dart';
import '../providers/map_provider.dart';
import 'widgets/map_listing_card.dart';
import 'widgets/cluster_carousel_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;

  @override
  void dispose() {
    // Ο GoogleMap widget κάνει ο ίδιος το πραγματικό dispose του controller·
    // εμείς απλώς καθαρίζουμε την αναφορά ώστε τίποτα να μην τον χρησιμοποιήσει
    // μετά (ΔΕΝ ξανακαλούμε .dispose() → double-dispose crash).
    _mapController = null;
    super.dispose();
  }

  /// Ασφαλής χρήση του χάρτη: μόνο αν το widget είναι mounted ΚΑΙ ο controller
  /// υπάρχει. Τυλίγει σε try/catch το «used after being disposed» (π.χ. όταν ο
  /// χάρτης ξεφορτώθηκε λόγω isLocating) ώστε να μη γίνεται fatal crash.
  void _withMap(void Function(GoogleMapController c) action) {
    final c = _mapController;
    if (!mounted || c == null) return;
    try {
      action(c);
    } catch (e, s) {
      logSwallowed(e, s, 'map controller');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapProvider);
    final notifier = ref.read(mapProvider.notifier);

    ref.listen(mapProvider, (prev, next) {
      // Όταν ξεκινά νέος εντοπισμός, ο χάρτης ξεφορτώνεται και ο controller
      // γίνεται invalid → καθάρισε την αναφορά ώστε να μη χρησιμοποιηθεί stale.
      if (next.isLocating && !(prev?.isLocating ?? false)) {
        _mapController = null;
      }
      if (next.clusterListings.isNotEmpty &&
          (prev == null || prev.clusterListings.isEmpty)) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ClusterCarouselSheet(
            listings: next.clusterListings,
            initialIndex: next.clusterIndex,
          ),
        ).whenComplete(() {
          notifier.clearClusterTap();
        });
      }
      if (next.clusterListings.isNotEmpty &&
          next.clusterTapPosition != null &&
          next.clusterTapPosition != prev?.clusterTapPosition) {
        _withMap((c) => c.animateCamera(
              CameraUpdate.newLatLng(next.clusterTapPosition!),
            ));
      }
    });

    return Scaffold(
      // ΑΛΛΑΓΗ: ο spinner δείχνεται μόνο όσο τρέχει ο εντοπισμός (isLocating),
      // ΟΧΙ με βάση το userPosition. Έτσι, ακόμα κι αν το GPS αποτύχει,
      // ο χάρτης εμφανίζεται με το default location αντί για ατέρμονο spinner.
      body: mapState.isLocating
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Stack(children: [
              GoogleMap(
                onMapCreated: (c) {
                  _mapController = c;
                },
                // ΑΛΛΑΓΗ: cameraTarget αντί για userPosition! (έχει fallback)
                initialCameraPosition: CameraPosition(
                  target: mapState.cameraTarget,
                  zoom: 14,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: mapState.markers,
                onTap: (_) => notifier.clearSelected(),
                onCameraIdle: () async {
                  final c = _mapController;
                  if (c == null) return;
                  try {
                    final zoom = await c.getZoomLevel();
                    if (!mounted) return;
                    notifier.updateZoom(zoom);
                  } catch (e, s) {
                    logSwallowed(e, s, 'map getZoomLevel');
                  }
                },
              ),

              // Active tag filter chip (αν υπάρχει)
              if (mapState.activeTagFilter != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 12,
                  right: 52,
                  child: _ActiveFilterChip(
                    tag: mapState.activeTagFilter!,
                    onClear: () => notifier.setTagFilter(null),
                  ),
                ),

              // Subtle hint όταν χρησιμοποιούμε default location
              // (δεν βρέθηκε πραγματική τοποθεσία)
              if (mapState.usingFallbackLocation)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 12,
                  right: 52,
                  child: _LocationHintChip(
                    onRetry: () => notifier.retryLocation(),
                  ),
                ),

              // Locate me
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 12,
                child: FloatingActionButton.small(
                  heroTag: 'locate',
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  onPressed: () async {
                    // Ανανεώνει τη θέση ΧΩΡΙΣ να ξεφορτωθεί ο χάρτης, ώστε ο
                    // controller να μείνει έγκυρος και το animateCamera να δουλέψει.
                    final target = await notifier.centerOnUser();
                    if (!mounted || target == null) return;
                    _withMap((c) => c.animateCamera(
                          CameraUpdate.newLatLngZoom(target, 15),
                        ));
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),

              // Selected listing card
              if (mapState.selectedListing != null)
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: MapListingCard(
                    listing: mapState.selectedListing!,
                    onClose: () => notifier.clearSelected(),
                  ),
                ),
            ]),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final String tag;
  final VoidCallback onClear;

  const _ActiveFilterChip({required this.tag, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_alt, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text('#$tag',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }
}

class _LocationHintChip extends StatelessWidget {
  final VoidCallback onRetry;

  const _LocationHintChip({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text('mapx.locationNotFoundRetry'.tr(),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
