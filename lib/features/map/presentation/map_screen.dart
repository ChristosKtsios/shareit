import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
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
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapProvider);
    final notifier = ref.read(mapProvider.notifier);

    ref.listen(mapProvider, (prev, next) {
      print('🔵 LISTENER triggered. clusterListings.length=${next.clusterListings.length}');
      if (next.clusterListings.isNotEmpty &&
          (prev == null || prev.clusterListings.isEmpty)) {
        print('🟢 OPENING SHEET');
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
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(next.clusterTapPosition!),
        );
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
                  if (_mapController != null) {
                    final zoom = await _mapController!.getZoomLevel();
                    notifier.updateZoom(zoom);
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
                    // Αν δεν έχουμε πραγματική τοποθεσία, ξαναπροσπαθούμε.
                    if (mapState.userPosition == null) {
                      await notifier.retryLocation();
                    }
                    final pos = ref.read(mapProvider).userPosition;
                    if (pos != null && _mapController != null) {
                      _mapController!.animateCamera(
                        CameraUpdate.newLatLng(
                            LatLng(pos.latitude, pos.longitude)),
                      );
                    }
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, color: Colors.white, size: 14),
            SizedBox(width: 6),
            Text('Δεν βρέθηκε η τοποθεσία — Δοκίμασε ξανά',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
