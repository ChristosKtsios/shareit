import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const LocationPickerScreen({super.key, this.initialLocation});

  @override
  State<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState
    extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.initialLocation != null) {
      setState(() {
        _selectedLocation = widget.initialLocation;
        _loading = false;
      });
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _selectedLocation = LatLng(pos.latitude, pos.longitude);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _selectedLocation =
            const LatLng(39.6222, 20.8465); // Ιωάννινα default
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Επίλεξε τοποθεσία'),
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _selectedLocation),
              child: const Text('Επιβεβαίωση',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.primary))
          : Stack(children: [

              // Χάρτης
              GoogleMap(
                onMapCreated: (c) { _mapController = c; },
                initialCameraPosition: CameraPosition(
                  target: _selectedLocation!,
                  zoom: 15,
                ),
                myLocationEnabled:       true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled:     false,
                markers: _selectedLocation != null
                    ? {
                        Marker(
                          markerId: const MarkerId('selected'),
                          position: _selectedLocation!,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueAzure),
                        ),
                      }
                    : {},
                onTap: (pos) =>
                    setState(() => _selectedLocation = pos),
              ),

              // Οδηγίες
              Positioned(
                top: 12, left: 16, right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.grey.shade200, width: 0.5),
                  ),
                  child: const Row(children: [
                    Icon(Icons.touch_app_outlined,
                        color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Πάτα στον χάρτη για να επιλέξεις τοποθεσία',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13)),
                    ),
                  ]),
                ),
              ),

              // Locate me
              Positioned(
                bottom: 100, right: 16,
                child: FloatingActionButton.small(
                  heroTag:         'locate_picker',
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  elevation: 2,
                  onPressed: () async {
                    try {
                      final pos =
                          await Geolocator.getCurrentPosition(
                              desiredAccuracy:
                                  LocationAccuracy.high);
                      final loc =
                          LatLng(pos.latitude, pos.longitude);
                      setState(() => _selectedLocation = loc);
                      _mapController?.animateCamera(
                          CameraUpdate.newLatLng(loc));
                    } catch (_) {}
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),

              // Confirm button
              Positioned(
                bottom: 20, left: 16, right: 16,
                child: ElevatedButton.icon(
                  onPressed: _selectedLocation == null
                      ? null
                      : () => Navigator.pop(
                          context, _selectedLocation),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Επιβεβαίωση τοποθεσίας'),
                ),
              ),
            ]),
    );
  }
}