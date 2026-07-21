import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/location_permission_gate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const LocationPickerScreen({super.key, this.initialLocation});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
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
      final perm = await LocationPermissionGate.ensure();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission not granted');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(
            accuracy: LocationAccuracy.high,
            // ΧΩΡΙΣ timeLimit το getCurrentPosition ΔΕΝ επιστρέφει ποτέ σε
            // πραγματικές συσκευές Android όταν το GPS δεν πιάνει σήμα —
            // το loading έμενε true και το κουμπί «Δημοσίευση» ΝΕΚΡΟ.
            timeLimit: Duration(seconds: 12),
          ));
      if (!mounted) return; // το GPS αργεί έως 12s· ο χρήστης μπορεί να έφυγε
      setState(() {
        _selectedLocation = LatLng(pos.latitude, pos.longitude);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedLocation = const LatLng(39.6222, 20.8465); // Ιωάννινα default
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('locpick.title'.tr()),
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _selectedLocation),
              child: Text('common.confirm'.tr(),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Stack(children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _selectedLocation!,
                  zoom: 15,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
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
                onTap: (pos) => setState(() => _selectedLocation = pos),
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200, width: 0.5),
                  ),
                  child: Row(children: [
                    const Icon(Icons.touch_app_outlined,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('locpick.tapMapHint'.tr(),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}
